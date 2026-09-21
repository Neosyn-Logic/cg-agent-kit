#!/usr/bin/env python3
"""Stdlib-unittest suite for cg_mcp_server.

Two groups:

  * FAST unit tests on the pure helpers (no external process) — always run.
  * INTEGRATION tests that spawn the compiler jar / yosys / iverilog — each
    skips gracefully via `unittest.skipUnless` when its dependency is absent.

Run:
    cd tools/cg-agent-kit
    NEOSYN_CG_DEV=1 .venv/bin/python -m unittest test_cg_mcp_server -v
    # (or `python3 -m unittest ...` if the venv python is missing)

Exact values (cell counts, sim numbers) are intentionally NOT hard-coded — they
drift with the compiler/yosys; the tests assert types, shapes, ok-flags, and
error substrings instead.
"""
import asyncio
import json
import os
import re
import subprocess
import sys
import tempfile
import pathlib
import shutil
import unittest

from neosyn_fpga_mcp import cg_mcp_server as cg

# Dependency gates for the integration tests.
JAR_OK = cg.JAR.is_file()
YOSYS_OK = shutil.which("yosys") is not None
IVERILOG_OK = shutil.which("iverilog") is not None and shutil.which("vvp") is not None
# The open-source compiler jar, when a checkout of it is present. It has no
# `simulate` verb, which makes it the only honest control for the probe: it is
# the OTHER environment this kit runs in, not a simulation of it.
OSS_JAR = cg.Path.home() / "neosyn/cg-compiler/releng/lsp-server/target/cg-language-server.jar"
OSS_JAR_OK = OSS_JAR.is_file()

# Which jar is this? The kit supports BOTH compilers, and the two differ in ways
# that are features of the build, not faults of the kit:
#   * the fast bytecode simulator ships only with the commercial distribution;
#   * file-scope `const`/`typedef`/`struct`/`enum` are commercial-only too --
#     the open build answers `missing EOF at 'const'`, which the kit's own hint
#     text already explains to users.
# Tests that depend on either must SKIP on a jar that lacks it, not fail: CI's
# integration job runs the OPEN jar on purpose, and a red suite there says
# "the kit is broken" when it means "this compiler does not do that".
# Probed, never assumed from a jar path or a version string.
BYTECODE_OK = bool(cg.probe_bytecode().get("available")) if JAR_OK else False


def _file_scope_supported() -> bool:
    if not JAR_OK:
        return False
    try:
        return bool(cg.check("package t;\nconst int N = 4;\n"
                             "task Foo { out sync u8 y; void loop() { y.write(N); } }\n")["ok"])
    except Exception:
        return False


FILE_SCOPE_OK = _file_scope_supported()

try:  # the `mcp` package is only needed to RUN as a server, not to test the core
    import mcp  # noqa: F401
    MCP_OK = True
except ImportError:
    MCP_OK = False

# A self-contained DUT + a CAPITAL-`Test` network. The HDL backend only emits a
# `<Name>.tb.v` when the network name contains "Test" (capital T); a `source`
# task drives the DUT and a `monitor` reads it back so the testbench has a real
# datapath. `terminate: "monitor.finished"` is the bytecode-sim terminate hook.
TEST_NETWORK_SRC = """package com.example;

task Dut {
  in push u8 x;
  out push u8 y;
  void loop() {
    u8 v = x.read();
    y.write(v);
  }
}

network TestDut {
  properties { test: { terminate: "monitor.finished" } }
  source = new task {
    out push u8 x;
    u8 n = 0;
    void loop() {
      x.write(n);
      n = n + 1;
    }
  };
  dut = new Dut();
  monitor = new task {
    in push u8 y;
    bool finished = false;
    void setup() {
      u8 a = y.read();
      print("y = ", a, "\\n");
      finished = true;
    }
  };
  dut.reads(source.x);
  monitor.reads(dut.y);
}
"""


def _counter_src():
    return (cg._EXAMPLES_DIR / "Counter.cg").read_text()


# ============================================================ FAST UNIT TESTS
class TestEntityHelpers(unittest.TestCase):
    """_entity_name / _test_entity / _synth_top on representative sources."""

    SRC = (
        "package com.example;\n"
        "task Foo {\n"
        "  out push u8 c;\n"
        "  u8 v = 0;\n"
        "  void loop() { c.write(v); v = v + 1; }\n"
        "}\n"
        "network Foo_test {\n"
        "  properties { test: { terminate: \"monitor.finished\" } }\n"
        "  dut = new Foo();\n"
        "  monitor = new task { in push u8 c; bool finished = false;\n"
        "    void setup() { u8 a = c.read(); finished = true; } };\n"
        "  monitor.reads(dut.c);\n"
        "}\n"
    )

    def test_entity_name_first_entity(self):
        # _entity_name picks the first network/task/bundle declared.
        self.assertEqual(cg._entity_name(self.SRC), "Foo")

    def test_entity_name_fallback_main(self):
        self.assertEqual(cg._entity_name("// nothing here\n"), "Main")

    def test_test_entity_picks_test_network(self):
        # The `task Foo` + `network Foo_test` layout -> simulate Foo_test.
        self.assertEqual(cg._test_entity(self.SRC), "Foo_test")

    def test_test_entity_via_test_property(self):
        # A network carrying a `test` property wins even without a `_test` suffix.
        self.assertEqual(cg._test_entity(TEST_NETWORK_SRC), "TestDut")

    def test_test_entity_none_single_entity(self):
        single = "task Lonely {\n  out push u8 c;\n  void loop() { c.write(0); }\n}\n"
        self.assertIsNone(cg._test_entity(single))

    def test_synth_top_skips_testbench(self):
        # Synth top is the non-testbench DUT, i.e. Foo (not Foo_test).
        self.assertEqual(cg._synth_top(self.SRC), "Foo")

    def test_synth_top_test_network_dut(self):
        self.assertEqual(cg._synth_top(TEST_NETWORK_SRC), "Dut")


class TestDiagnostics(unittest.TestCase):
    """_diagnostics de-dup + transform-error fallback regex."""

    def test_dedup_identical_lines(self):
        out = ("[neosyn] Foo.cg:12: mismatched input\n"
               "[neosyn] Foo.cg:12: mismatched input\n"
               "[neosyn] Bar.cg:3: bad thing\n")
        diags = cg._diagnostics(out)
        self.assertEqual(len(diags), 2)
        self.assertEqual(diags[0], {"file": "Foo.cg", "line": 12,
                                    "message": "mismatched input"})
        self.assertEqual(diags[1], {"file": "Bar.cg", "line": 3,
                                    "message": "bad thing"})

    def test_transform_error_fallback(self):
        out = ("[neosyn] Transform error in test.N_c: "
               "IllegalArgumentException — modulo by 3 not supported "
               "(re-run with --verbose)\n")
        diags = cg._diagnostics(out)
        self.assertEqual(len(diags), 1)
        d = diags[0]
        self.assertIsNone(d["file"])
        self.assertIsNone(d["line"])
        self.assertEqual(d["entity"], "test.N_c")
        # Exception prefix and trailing "(re-run with ...)" are stripped.
        self.assertEqual(d["message"], "modulo by 3 not supported")

    def test_hdl_emit_error_fallback(self):
        out = "[neosyn] HDL emit error in Foo.bar: NullPointerException — boom\n"
        diags = cg._diagnostics(out)
        self.assertEqual(len(diags), 1)
        self.assertEqual(diags[0]["entity"], "Foo.bar")
        self.assertEqual(diags[0]["message"], "boom")

    def test_no_diagnostics_clean_output(self):
        self.assertEqual(cg._diagnostics("all good, nothing to see\n"), [])


def _input_schema(tool):
    """`Tool.input_schema` in older `mcp`, `Tool.inputSchema` in newer ones.
    Accept both: pinning one spelling makes the suite fail on a library version
    the server itself is perfectly happy with."""
    for attr in ("inputSchema", "input_schema"):
        if hasattr(tool, attr):
            return getattr(tool, attr)
    raise AttributeError(f"no input-schema attribute on {type(tool).__name__}")


class TestTheShimActuallyRunsTheServer(unittest.TestCase):
    """`python -m <name>.cg_mcp_server` must START THE SERVER, under both names.

    This is the invocation MCP host configs use, and it shipped broken: under
    `-m`, runpy runs the shim file with `__name__ == "__main__"`, and importing
    the real module does NOT fire its own `if __name__ == "__main__"` guard,
    because at import time its `__name__` is the real dotted path. The shim
    imported, rebound sys.modules, and fell off the end. No output, exit 0, and
    two AccelOne turns ran with zero cg tools.

    ⚠️ Why this class exists alongside the import test: that one checks
    IMPORTABILITY and passes cleanly in exactly this broken state --
    `import cg_agent_kit.cg_mcp_server` works fine when `-m` starts nothing.
    Importability does not imply executability, and only running the entry point
    tells them apart.
    """

    INIT = json.dumps({
        "jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                   "clientInfo": {"name": "probe", "version": "1"}},
    })

    def _handshake(self, module, cwd):
        env = dict(os.environ)
        env.pop("PYTHONPATH", None)
        env.setdefault("NEOSYN_CG_DEV", "1")
        return subprocess.run(
            [sys.executable, "-m", module],
            input=self.INIT + "\n", cwd=cwd, env=env,
            capture_output=True, text=True, timeout=120)

    def test_both_module_paths_answer_an_initialize(self):
        with tempfile.TemporaryDirectory() as neutral:
            probe = subprocess.run(
                [sys.executable, "-c", "import mcp, neosyn_fpga_mcp.cg_mcp_server"],
                cwd=neutral, capture_output=True, text=True, timeout=120)
            if probe.returncode != 0:
                self.skipTest("package or `mcp` not installed in this interpreter")
            for module in ("neosyn_fpga_mcp.cg_mcp_server",
                           "cg_agent_kit.cg_mcp_server"):
                r = self._handshake(module, neutral)
                self.assertIn(
                    '"result"', r.stdout,
                    f"`python -m {module}` started no server -- it produced no "
                    f"JSON-RPC result. Import working is NOT enough; the entry "
                    f"point must run.\nstdout={r.stdout[:200]!r}\n"
                    f"stderr={r.stderr.strip()[-300:]}")


class TestBothPackageNamesResolveWhenInstalled(unittest.TestCase):
    """The rename's compatibility claim, CHECKED rather than asserted in a docstring.

    1.1.0 renamed `cg_agent_kit` -> `neosyn_fpga_mcp` and left a shim so that
    `python -m cg_agent_kit.cg_mcp_server` keeps working -- which is exactly how
    the AccelOne MCP host launches it. That promise was verified from the repo
    root, where BOTH names import as plain directories on `sys.path`, and was
    broken everywhere else: a stale editable install mapped only the old name,
    the shim imported a package its finder had never heard of, and the server
    died on start. A model then gets zero tools.

    Two things this has to get right, both learned the hard way:

    * run in a SUBPROCESS from a NEUTRAL cwd with the repo off the path -- the
      repo-root cwd is what masked the fault in the first place;
    * key the requirement on an installed DISTRIBUTION, not on whether an import
      succeeds. In the broken state BOTH imports failed (the shim raises while
      resolving the new name), so an "if either imports, require both" rule
      would have SKIPPED exactly when it mattered. The `.dist-info` was present
      throughout, which is the signal that actually distinguishes "not installed"
      from "installed one-sidedly".
    """

    NAMES = ("neosyn_fpga_mcp", "cg_agent_kit")
    DISTS = ("neosyn-fpga-mcp", "cg-agent-kit")

    def _run(self, code, cwd):
        env = dict(os.environ)
        env.pop("PYTHONPATH", None)
        return subprocess.run([sys.executable, "-c", code], cwd=cwd, env=env,
                              capture_output=True, text=True, timeout=120)

    def test_an_installed_distribution_exposes_BOTH_import_names(self):
        with tempfile.TemporaryDirectory() as neutral:
            probe = self._run(
                "import importlib.metadata as m, json\n"
                "found = []\n"
                "for d in ('neosyn-fpga-mcp','cg-agent-kit'):\n"
                "    try:\n"
                "        m.version(d); found.append(d)\n"
                "    except Exception: pass\n"
                "print(json.dumps(found))", neutral)
            self.assertEqual(probe.returncode, 0, probe.stderr[-300:])
            installed = json.loads(probe.stdout.strip() or "[]")
            if not installed:
                self.skipTest("neither distribution is installed in this interpreter")
            for name in self.NAMES:
                r = self._run(f"import {name}.cg_mcp_server", neutral)
                self.assertEqual(
                    r.returncode, 0,
                    f"{installed} is installed but `import {name}.cg_mcp_server` "
                    f"fails -- a one-sided install. Re-run `pip install -e .` "
                    f"after a rename.\n{r.stderr.strip()[-400:]}")

    def test_the_two_names_are_the_same_module_object(self):
        """Two copies of the module would mean two copies of its state."""
        with tempfile.TemporaryDirectory() as neutral:
            if self._run("import neosyn_fpga_mcp.cg_mcp_server", neutral).returncode != 0:
                self.skipTest("package not installed in this interpreter")
            probe = self._run(
                "import cg_agent_kit.cg_mcp_server as a, "
                "neosyn_fpga_mcp.cg_mcp_server as b; "
                "raise SystemExit(0 if a is b else 1)", neutral)
        self.assertEqual(probe.returncode, 0,
                         f"the shim is a second module object, not an alias: "
                         f"{probe.stderr.strip()[-300:]}")


class TestLintNeverCertifiesWhatItCouldNotRead(unittest.TestCase):
    """F102. lint's `checked` was hard-wired True, so it returned a CLEAN result for a
    filename, the word "hello" and a nonexistent path -- it found nothing to object to
    because it found nothing at all. A model linted a path in the AccelOne trial and
    got a clean bill of health in the same second cg_check rejected it."""

    BAD = ("fpga/src/main/cg/IntakeSum.cg", "hello", "/does/not/exist.cg",
           "this is not\nC-ground at all\njust text", "")

    def test_nothing_readable_is_never_checked_or_ok(self):
        for src in self.BAD:
            with self.subTest(src=src[:30]):
                r = cg.lint(src)
                self.assertFalse(r["checked"], f"lint claimed to check {src!r}")
                self.assertFalse(r["ok"], f"lint certified {src!r} as clean")
                self.assertTrue(r.get("error"), "an unchecked result must say WHY")

    def test_a_real_design_is_still_checked_and_names_what_it_checked(self):
        r = cg.lint((cg._EXAMPLES_DIR / "Counter.cg").read_text())
        self.assertTrue(r["checked"])
        self.assertIn("Counter", r["entities_checked"])


class TestSourceUsageGuard(unittest.TestCase):
    """`source` takes C⏚ TEXT. A path, or an expression that would read one,
    must be REJECTED rather than compiled as if it were source.

    The regression this pins (AccelOne trial, 2026-09-20): passing a path
    compiled the path string and produced `Main.cg:1 missing 'package' at
    'fpga'`. A model read that, concluded the compiler wanted a `Main.cg` entry
    point, and spent its last ten minutes hunting a file that does not exist.
    The diagnostic must therefore name the RECEIVED VALUE and carry NO file
    name, or it invites the same inference."""

    def test_path_rejected_and_names_the_value(self):
        msg = cg._source_usage_error("fpga/src/main/cg/IntSum64.cg")
        self.assertIsNotNone(msg)
        self.assertIn("fpga/src/main/cg/IntSum64.cg", msg)
        self.assertIn("package_dir", msg)
        self.assertNotIn("Main.cg", msg)

    def test_python_expression_rejected(self):
        msg = cg._source_usage_error('open("x/y/IntSum64.cg").read()')
        self.assertIsNotNone(msg)
        self.assertIn("IntSum64.cg", msg)

    def test_bare_word_without_package_rejected(self):
        self.assertIsNotNone(cg._source_usage_error("IntSum64"))

    def test_empty_rejected(self):
        self.assertIsNotNone(cg._source_usage_error("   "))

    def test_real_source_accepted(self):
        src = ("package com.example;\n"
               "task Counter {\n"
               "  out sync u8 o;\n"
               "  void loop() { o.write(1); }\n"
               "}\n")
        self.assertIsNone(cg._source_usage_error(src))

    def test_guard_surfaces_as_a_fileless_diagnostic(self):
        diags = cg._diagnostics("[cg-kit] source looks like a path: 'a/b.cg'. ...")
        self.assertEqual(len(diags), 1)
        self.assertIsNone(diags[0]["file"])
        self.assertIsNone(diags[0]["line"])
        self.assertIn("looks like a path", diags[0]["message"])

    def test_check_rejects_a_path_without_inventing_a_file(self):
        """End to end through check(): no compiler run, no phantom Main.cg."""
        r = cg.check("fpga/src/main/cg/IntSum64.cg")
        self.assertFalse(r["ok"])
        self.assertEqual(len(r["diagnostics"]), 1)
        self.assertIsNone(r["diagnostics"][0]["file"])
        self.assertIn("IntSum64.cg", r["diagnostics"][0]["message"])


class TestClean(unittest.TestCase):
    """_clean noise-stripping + line cap."""

    def test_strips_noise(self):
        noisy = ("[CgLanguageServer] starting\n"
                 "Running simulation: Foo\n"
                 "License: ok\n"
                 "  at java.base/foo.Bar\n"
                 "Caused by: whatever\n"
                 "Real line\n"
                 "\n"
                 "Another real line\n")
        cleaned = cg._clean(noisy)
        self.assertEqual(cleaned, "Real line\nAnother real line")

    def test_line_cap(self):
        many = "\n".join(f"L{i}" for i in range(10))
        capped = cg._clean(many, limit=3)
        lines = capped.splitlines()
        self.assertEqual(lines[:3], ["L0", "L1", "L2"])
        self.assertIn("more lines", lines[3])
        self.assertEqual(len(lines), 4)

    def test_under_cap_no_marker(self):
        out = cg._clean("a\nb\nc", limit=10)
        self.assertEqual(out, "a\nb\nc")
        self.assertNotIn("more lines", out)


class TestFlowAndSimulatorGuards(unittest.TestCase):
    """Bad-flow / bad-simulator guards. These don't need a successful toolchain
    run — they only need the up-front presence/validation checks to fire."""

    @unittest.skipUnless(YOSYS_OK, "yosys not installed")
    def test_synth_bogus_flow(self):
        # yosys-presence check runs first; with yosys present we reach the flow
        # check, which rejects an unknown flow before any synthesis.
        r = cg.synth(_counter_src() if JAR_OK else "task X {}\n", flow="bogus")
        self.assertFalse(r["ok"])
        self.assertIn("unknown flow", r["error"])

    def test_simulate_unknown_simulator(self):
        r = cg.simulate("task X {}\n", simulator="ghdl")
        self.assertFalse(r["ok"])
        self.assertIn("unknown simulator", r["error"])

    def test_simulate_verilator_unavailable(self):
        # verilator is not installed on this host -> graceful unavailable error.
        r = cg.simulate("task X {}\n", simulator="verilator")
        self.assertFalse(r["ok"])
        self.assertEqual(r["simulator"], "verilator")
        self.assertIn("verilator", r["error"])
        if shutil.which("verilator") is None:
            self.assertIn("not installed", r["error"])


class TestExampleLibrary(unittest.TestCase):
    """example() recipe routing — pure (reads examples/ off disk, no process)."""

    def test_list_index(self):
        r = cg.example("")
        self.assertTrue(r["ok"])
        names = {rec["name"] for rec in r["index"]}
        self.assertIn("Counter", names)
        # the index carries kind + tags for lazy browsing
        self.assertTrue(all("kind" in rec and "tags" in rec for rec in r["index"]))

    def test_exact_name(self):
        r = cg.example("Counter")
        self.assertTrue(r["ok"])
        self.assertEqual(r["name"], "Counter")
        self.assertIn("task Counter", r["source"])

    def test_intent_routing_sqrt(self):
        # bare "sqrt" must route to FixedSqrt, NOT RSqrt (whose tags are all
        # 1/sqrt-family). The specificity scoring must not let RSqrt's three
        # *sqrt* tags out-stack FixedSqrt's exact `sqrt` tag.
        r = cg.example("sqrt")
        self.assertTrue(r["ok"])
        self.assertEqual(r["name"], "FixedSqrt", r)

    def test_specificity_one_over_sqrt(self):
        # "1/sqrt" must beat a bare sqrt → RSqrt, with FixedSqrt as a runner-up.
        r = cg.example("1/sqrt")
        self.assertEqual(r["name"], "RSqrt", r)
        self.assertIn("FixedSqrt", [x["name"] for x in r.get("runners_up", [])])

    def test_runners_up_on_ambiguous(self):
        r = cg.example("squared distance")
        self.assertTrue(r["ok"])
        self.assertTrue(r.get("runners_up"), "expected runners-up on an ambiguous query")

    def test_no_match(self):
        r = cg.example("definitely-not-a-recipe-xyz")
        self.assertFalse(r["ok"])
        self.assertIn("available", r)

    def test_suggest_for_error_div_by_var(self):
        # the real compiler message shares a "(no hardware divider/variable-
        # shifter is generated)" tail with the shift message — only the operator
        # token disambiguates, so a '/' error must still route to Recip.
        s = cg.suggest_for_error("the right operand of '/' must be a compile-time "
                                 "constant (no hardware divider/variable-shifter is generated)")
        self.assertTrue(s["ok"])
        self.assertEqual(s["recipe"], "Recip")

    def test_suggest_for_error_variable_shift(self):
        # a '<<' / '>>' error routes to BarrelShift, NOT Recip, despite the
        # shared "divider/variable-shifter" tail.
        for op in ("<<", ">>"):
            s = cg.suggest_for_error(
                "the right operand of '%s' must be a compile-time constant "
                "(no hardware divider/variable-shifter is generated)" % op)
            self.assertTrue(s["ok"], op)
            self.assertEqual(s["recipe"], "BarrelShift", op)

    def test_example_new_dictionary_entries(self):
        # the session-132 additions resolve by intent.
        self.assertEqual(cg.example("barrel shift")["name"], "BarrelShift")
        self.assertEqual(cg.example("register file")["name"], "RegisterFile")
        self.assertEqual(cg.example("sign extend")["name"], "BitFieldDecode")

    def test_suggest_for_error_runtime_loop(self):
        s = cg.suggest_for_error("a data-dependent loop bound cannot unroll (while)")
        self.assertTrue(s["ok"])
        self.assertEqual(s["recipe"], "SeqDiv")

    def test_suggest_for_error_no_match(self):
        self.assertFalse(cg.suggest_for_error("totally unrelated message")["ok"])


# ------------------------------------------- authoring/wiring hints (S166, P1)
# Every message string below is VERBATIM compiler output, captured by running
# the failing program against the real jar — not a paraphrase. If the compiler
# rewords a diagnostic these tests fail, which is the point: a hint table keyed
# on text that no longer appears is worse than no table, because the model
# silently gets nothing. The matching integration tests re-derive the same
# strings from the live compiler.
class TestAuthoringHints(unittest.TestCase):
    def _hint(self, msg):
        s = cg.suggest_for_error(msg)
        self.assertTrue(s["ok"], f"no hint matched: {msg!r}")
        return s

    def test_misplaced_declaration(self):
        # The bare `missing EOF at '<tok>'` is what the OPEN-SOURCE compiler says: it
        # has no file scope at all. A recent Neosyn compiler accepts file-scope
        # declarations and instead complains about their ORDER. Both spellings must
        # reach the same hint, which covers both compilers.
        for msg in ("missing EOF at 'const'", "missing EOF at 'typedef'",
                    "a file-scope declaration must come BEFORE the first `task`"):
            s = self._hint(msg)
            self.assertIsNone(s["recipe"])
            self.assertIsNone(s["source"])
            self.assertIn("file scope", s["hint"])
            self.assertIn("bundle", s["hint"])

    def test_non_ascii_character(self):
        # A schwa in an identifier. The compiler quotes the offending char.
        s = self._hint("no viable alternative at character '\u0259'")
        self.assertIsNone(s["recipe"])
        self.assertIn("ASCII", s["hint"])

    def test_angle_bracket_width(self):
        # `u<8>` instead of `u8` / `uint<W>`.
        s = self._hint("mismatched input '<' expecting ';'")
        self.assertIn("uint<W>", s["hint"])

    def test_unresolved_instantiable(self):
        s = self._hint("Couldn't resolve reference to Instantiable 'MissingSibling'.")
        self.assertIn("package_dir", s["hint"])

    def test_hdl_generation_blocked_by_compile_errors(self):
        # Both spellings: the CLI's and the LSP handler's.
        for msg in ("Error: Cannot generate HDL for Foo.cg: 2 compile error(s) "
                    "\u2014 fix them first (a parse error silently drops the "
                    "design body).",
                    "No IR files generated - check for compilation errors"):
            s = self._hint(msg)
            self.assertIn("cg_check", s["hint"])

    def test_toolchain_fault_is_not_blamed_on_the_source(self):
        # The model must be told NOT to rewrite working C⏚ over a jar fault.
        s = self._hint("java.lang.NoClassDefFoundError: com/neosyn/models/ir/Var")
        self.assertIn("TOOLCHAIN", s["hint"])
        self.assertIn("do not", s["hint"].lower())

    def test_no_switch_statement(self):
        for msg in ("missing '}' at 'case'",
                    "no viable alternative at input 'case'",
                    "switch cannot be resolved"):
            s = self._hint(msg)
            self.assertIn("if / else-if", s["hint"], msg)

    def test_port_cannot_be_an_array(self):
        # The RAW parser text, which jars older than S170 still emit -- the hint
        # must keep firing against those, which is why the regex matches both
        # spellings rather than being retargeted at the new message alone.
        s = self._hint("mismatched input '[' expecting ';'")
        self.assertIn("array dimensions are not accepted here", s["hint"])

    def test_array_dimensions_hint_matches_the_current_message(self):
        # The message the compiler emits SINCE S170 (7316b31). Without this the
        # hint could silently stop firing on current jars while this file still
        # passed against the legacy spelling above.
        s = self._hint("Syntax error: array dimensions are not allowed in this "
                       "declaration. `[...]` is accepted on a state variable")
        self.assertIn("array dimensions are not accepted here", s["hint"])
        self.assertNotIn("only ports may not", s["hint"])

    def test_name_not_in_scope_is_the_last_resort(self):
        s = self._hint("N cannot be resolved")
        self.assertIn("not visible", s["hint"])
        # ...but it must not shadow the more specific instantiable rule, whose
        # message uses different wording and carries the package_dir fix.
        inst = self._hint("Couldn't resolve reference to Instantiable 'Sib'.")
        self.assertIn("package_dir", inst["hint"])
        self.assertNotIn("no globals", inst["hint"])

    def test_cascade_guard_on_missing_eof(self):
        # A real top-level declaration is always error #1. The SAME text later
        # in the run is cascade from an earlier parse failure, and there the
        # "move it inside a task" advice is wrong -- it usually already is.
        msg = "missing EOF at 'xCount'"
        self.assertTrue(cg.suggest_for_error(msg, is_first=True)["ok"])
        self.assertFalse(cg.suggest_for_error(msg, is_first=False)["ok"])

    def test_authoring_rules_win_over_synthesizability_rules(self):
        # ORDER: the SeqDiv rule matches a bare `while`, so a parse error that
        # happens to contain the word must NOT be routed to a divider recipe.
        s = self._hint("missing EOF at 'const' while parsing")
        self.assertIsNone(s["recipe"], "a parse error was routed to a recipe")

    def test_synthesizability_rules_still_carry_a_recipe(self):
        # The family-2 rows must keep returning recipe + source after the
        # None-recipe rows were added above them.
        s = self._hint("the right operand of '/' must be a compile-time constant")
        self.assertEqual(s["recipe"], "Recip")
        self.assertTrue(s["source"], "recipe source went missing")


# ============================================================ INTEGRATION TESTS
@unittest.skipUnless(JAR_OK, "compiler jar not built")
class TestCheck(unittest.TestCase):
    def test_clean_recipe_ok(self):
        r = cg.check(_counter_src())
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["diagnostics"], [])

    def test_parse_error_not_ok(self):
        bad = _counter_src().replace("void loop()", "void loop() @@@", 1)
        r = cg.check(bad)
        self.assertFalse(r["ok"])
        self.assertTrue(r["diagnostics"], "expected diagnostics on a parse error")


@unittest.skipUnless(MCP_OK, "mcp package not installed")
class TestServerBuilds(unittest.TestCase):
    """The server must actually START, and every tool must be reachable on it.

    `mcp` 2.0 renamed FastMCP -> MCPServer and deleted mcp.server.fastmcp, while
    requirements.txt says `mcp>=1.0` — so a fresh install got 2.x and the server
    failed to boot, taking every tool in the file with it. Nothing in the suite
    noticed, because the core functions are import-free. This test is that gap."""

    def test_build_server_registers_every_tool(self):
        import asyncio
        srv = cg.build_server()
        names = sorted(t.name for t in asyncio.run(srv.list_tools()))
        for expected in ("cg_check", "cg_simulate", "cg_generate_verilog",
                         "cg_synth", "cg_scaffold", "cg_capabilities",
                         "cg_example",
                         "cg_suggest_for_error", "cg_fsm", "cg_graph", "cg_docs"):
            self.assertIn(expected, names)


@unittest.skipUnless(JAR_OK, "compiler jar not built")
class TestCapabilities(unittest.TestCase):
    """The kit runs against two different compilers and the right guidance
    differs between them, so it must PROBE rather than assert. Both halves are
    covered here — the commercial jar, and (when present) the real OSS one."""

    def setUp(self):
        self._jar, self._probe = cg.JAR, cg._BYTECODE_PROBE

    def tearDown(self):
        cg.JAR, cg._BYTECODE_PROBE = self._jar, self._probe

    @unittest.skipUnless(BYTECODE_OK, "by its own name: only meaningful on the commercial jar")
    def test_probe_finds_the_bytecode_simulator_on_the_commercial_jar(self):
        cg._BYTECODE_PROBE = None
        r = cg.probe_bytecode(force=True)
        self.assertTrue(r["available"], r)
        self.assertEqual(r["reason"], "ok")

    def test_probe_is_cached(self):
        cg._BYTECODE_PROBE = {"available": False, "reason": "sentinel", "detail": ""}
        self.assertEqual(cg.probe_bytecode()["reason"], "sentinel")

    @unittest.skipUnless(BYTECODE_OK, "asserts the bytecode backend is listed")
    def test_capabilities_reports_what_is_here(self):
        cg._BYTECODE_PROBE = None
        c = cg.capabilities()
        self.assertTrue(c["ok"])
        self.assertTrue(c["jar_present"])
        self.assertIn("bytecode", c["simulators"])
        self.assertIn("bytecode", c["advice"])
        for tool in ("iverilog", "vvp", "verilator", "yosys", "ghdl"):
            self.assertIn(tool, c["tools"])

    def test_missing_jar_is_reported_as_such(self):
        cg.JAR, cg._BYTECODE_PROBE = cg.Path("/nonexistent/cg.jar"), None
        r = cg.probe_bytecode(force=True)
        self.assertFalse(r["available"])
        self.assertEqual(r["reason"], "jar-missing")

    @unittest.skipUnless(OSS_JAR_OK, "no open-source compiler checkout")
    def test_open_source_jar_is_detected_and_explained(self):
        # The control. Against the OSS build the probe must say not-in-jar...
        cg.JAR, cg._BYTECODE_PROBE = OSS_JAR, None
        r = cg.probe_bytecode(force=True)
        self.assertFalse(r["available"], r)
        self.assertEqual(r["reason"], "not-in-jar")
        # ...capabilities must steer to iverilog instead of the missing one...
        c = cg.capabilities()
        self.assertNotIn("bytecode", c["simulators"])
        self.assertIn("iverilog", c["advice"])
        # ...and a cg_simulate call must not read as "your design is wrong".
        r = cg.simulate("package t;\ntask F { in push u8 a; out push u8 y;\n"
                        "  void loop() { y.write(a.read()); } }\n", timeout=60)
        self.assertFalse(r["ok"])
        self.assertFalse(r["available"])
        self.assertEqual(r["reason"], "not-in-jar")
        self.assertIn("not the problem", r["error"])
        self.assertEqual(r.get("diagnostics", []), [],
                         "an absent simulator must not be reported as diagnostics")


class TestScaffoldShape(unittest.TestCase):
    """Pure-shape checks on cg_scaffold — no compiler needed."""

    def test_every_kind_produces_holes_and_a_package(self):
        for kind in cg._SCAFFOLD_KINDS:
            r = cg.scaffold(kind=kind, name="Thing", package="a.b", verify=False)
            self.assertTrue(r["ok"], r)
            self.assertTrue(r["source"].startswith("package a.b;"), kind)
            self.assertIn("Thing", r["source"], kind)
            self.assertTrue(r["holes"], f"{kind} scaffold has nothing to fill in")
            for h in r["holes"]:
                self.assertIn(cg.FILL, r["source"].splitlines()[h["line"] - 1])

    def test_unknown_kind_rejected(self):
        r = cg.scaffold(kind="nonsense", verify=False)
        self.assertFalse(r["ok"])
        self.assertIn("unknown kind", r["error"])

    def test_invalid_names_rejected(self):
        # An entity name reaches the generated source verbatim; rejecting it here
        # beats emitting a file that cannot parse.
        for bad in ("9lives", "has space", "has-dash", ""):
            self.assertFalse(cg.scaffold(name=bad, verify=False)["ok"], bad)
        self.assertFalse(cg.scaffold(package="1.bad", verify=False)["ok"])

    def test_port_spec_parsing(self):
        self.assertEqual(cg._ports(["a:u8", "b:i16"], []), [("a", "u8"), ("b", "i16")])
        self.assertEqual(cg._ports(["a"], []), [("a", "u8")])       # bare name -> u8
        self.assertEqual(cg._ports(None, [("z", "u4")]), [("z", "u4")])

    def test_ports_applied_to_task_and_stream(self):
        for kind in ("task", "stream"):
            r = cg.scaffold(kind=kind, inputs=["sig:u12"], outputs=["res:i20"],
                            verify=False)
            self.assertIn("u12 sig", r["source"], kind)
            self.assertIn("i20 res", r["source"], kind)
            self.assertFalse(r["notes"], kind)

    def test_fixed_kinds_say_ports_were_ignored(self):
        # Silently dropping them would leave the model editing a file that does
        # not have the ports it asked for, with no clue why.
        r = cg.scaffold(kind="fsm", inputs=["z:u3"], verify=False)
        self.assertTrue(r["notes"])
        self.assertIn("not applied", r["notes"][0])


@unittest.skipUnless(JAR_OK, "compiler jar not built")
@unittest.skipUnless(BYTECODE_OK, "scaffold VERIFIES by simulating; needs the bytecode simulator")
class TestScaffoldVerifies(unittest.TestCase):
    """The two invariants the scaffold is only worth shipping WITH.

    1. every kind compiles and its self-test passes as handed over;
    2. every kind's self-test FAILS when the datapath is wrong.

    (2) is the one that matters. A harness that passes no matter what is worse
    than no harness — it is the hollow-fixture shape that hid three shipped
    bugs — and (1) alone cannot tell the two apart."""

    # kind -> (exact text to sabotage, replacement that changes the RESULT)
    SABOTAGE = {
        "task":    ("y.write((u8) v_a);", "y.write((u8) (v_a + 1));"),
        "fsm":     ("found.write(hit);", "found.write(!hit);"),
        "stream":  ("y.write((u8) v_a);", "y.write((u8) (v_a + 1));"),
        "network": ("y.write((u8) (x.read() * 2)); }",
                    "y.write((u8) (x.read() * 3)); }"),
        "generic": ("y.write(x.read() * k);", "y.write(x.read() * (k + 1));"),
    }

    def test_every_kind_is_green_as_delivered(self):
        for kind in cg._SCAFFOLD_KINDS:
            r = cg.scaffold(kind=kind, name="Scaf")
            self.assertTrue(r["ok"], f"{kind}: {r.get('verified')}")
            self.assertTrue(r["verified"]["check"], kind)
            self.assertTrue(r["verified"]["simulate"], kind)

    def test_every_self_test_catches_a_broken_datapath(self):
        for kind, (old, new) in self.SABOTAGE.items():
            src = cg.scaffold(kind=kind, name="Scaf", verify=False)["source"]
            self.assertIn(old, src, f"{kind}: sabotage anchor drifted")
            broken = src.replace(old, new, 1)
            r = cg.simulate(broken, timeout=60)
            self.assertFalse(r["ok"],
                             f"{kind} scaffold PASSES with a broken datapath — "
                             f"its self-test verifies nothing")

    def test_port_variations_compile_and_pass(self):
        # Generated ports are where a template breaks: one input vs several,
        # several outputs, signed types.
        cases = [
            ("task", ["x:u8"], ["y:u8"]),
            ("task", ["a:u16", "b:u16", "c:u16"], ["y:u16"]),
            ("task", ["a:u8"], ["y0:u8", "y1:u16"]),
            ("stream", ["a:u16", "b:u16", "c:u16"], ["y:u32"]),
            ("stream", ["a:u8"], ["y0:u8", "y1:u8"]),
            ("stream", ["a:i32"], ["y:i32"]),
        ]
        for kind, ins, outs in cases:
            r = cg.scaffold(kind=kind, name="Var", inputs=ins, outputs=outs)
            self.assertTrue(r["ok"], f"{kind} {ins}->{outs}: {r.get('verified')}")

    def test_stream_harness_drives_every_input(self):
        # An undriven `in push` port blocks its task forever and the run dies on
        # the cycle cap — which reads as a hang, not an error. The generated
        # harness must therefore feed every input it declares.
        r = cg.scaffold(kind="stream", name="Multi",
                        inputs=["a:u8", "b:u8"], outputs=["y:u8"])
        self.assertTrue(r["ok"], r.get("verified"))
        self.assertIn("dut.reads(driver.a);", r["source"])
        self.assertIn("dut.reads(driver.b);", r["source"])


@unittest.skipUnless(JAR_OK, "compiler jar not built")
class TestAuthoringHintsAgainstTheRealCompiler(unittest.TestCase):
    """The other half of TestAuthoringHints: run each broken program through the
    REAL compiler and require a hint to come back attached.

    The unit tests above pin the hint text to a hard-coded message; these pin
    the message to the compiler. Together they fail loudly if the compiler
    rewords a diagnostic — with only the unit tests, a reworded message would
    quietly stop matching and the model would get no hint at all."""

    def _suggestion(self, source):
        r = cg.check(source)
        self.assertFalse(r["ok"], f"expected this to FAIL to compile: {r}")
        self.assertIn("suggestion", r,
                      f"compiler failed but no hint attached: {r['diagnostics']}")
        return r["suggestion"]

    @unittest.skipUnless(FILE_SCOPE_OK, "file-scope declarations are commercial-only")
    def test_file_scope_const_compiles(self):
        # This used to be the canonical PARSE ERROR here: `const` after `package` is
        # what a model writes when it wants a width parameter. It is now LEGAL, so the
        # test inverts into a regression test for the feature.
        r = cg.check(
            "package t;\n"
            "const u8 WIDTH = 8;\n"
            "task Foo { in push u8 a; out push u8 y;\n"
            "  void loop() { y.write(a.read() + WIDTH); } }\n")
        self.assertTrue(r["ok"], f"file-scope const should compile: {r}")

    def test_declaration_after_entity(self):
        # ...but the ORDER is still enforced: at most one implicit bundle, ahead of
        # everything. A declaration trailing an entity is the error that remains.
        sg = self._suggestion(
            "package t;\n"
            "task Foo { in push u8 a; out push u8 y;\n"
            "  void loop() { y.write(a.read()); } }\n"
            "const u8 WIDTH = 8;\n")
        self.assertIn("file scope", sg["hint"])

    def test_non_ascii_identifier(self):
        # A schwa inside an identifier. NB a schwa in a // comment compiles
        # CLEANLY — the hint says so, because telling a model to purge all
        # non-ASCII would have it rewrite innocent comments.
        sg = self._suggestion(
            "package t;\n"
            "task Foo { in push u8 a; out push u8 y;\n"
            "  void loop() { u8 v\u0259l = a.read(); y.write(v\u0259l); } }\n")
        self.assertIn("ASCII", sg["hint"])

    def test_non_ascii_in_comment_is_clean(self):
        # The control for the test above: this MUST compile.
        r = cg.check(
            "package t;\n"
            "task Foo { in push u8 a; out push u8 y;\n"
            "  // schwa \u0259, em\u2014dash, smart \u201cquotes\u201d\n"
            "  void loop() { y.write(a.read()); } }\n")
        self.assertTrue(r["ok"], r)

    def test_angle_bracket_width(self):
        sg = self._suggestion(
            "package t;\n"
            "task Foo { in push u<8> a; out push u<8> y;\n"
            "  void loop() { y.write(a.read()); } }\n")
        self.assertIn("uint<W>", sg["hint"])

    def test_missing_sibling_entity(self):
        # The package_dir case: instantiating an entity that lives in another
        # file the caller never sent.
        sg = self._suggestion(
            "package t;\n"
            "network Top {\n"
            "  dut = new MissingSibling();\n"
            "  drv = new task { out push u8 a; void loop() { a.write(1); } };\n"
            "  dut.reads(drv.a);\n"
            "}\n")
        self.assertIn("package_dir", sg["hint"])

    def test_switch_statement(self):
        # The C habit that derails the parser for the whole file.
        sg = self._suggestion(
            "package t;\n"
            "task Foo { in push u8 a; out push u8 y;\n"
            "  enum St { A, B }\n"
            "  St s;\n"
            "  void loop() { u8 v = a.read();\n"
            "    switch (s) { case A: y.write(v); break; case B: y.write(v); break; }\n"
            "  } }\n")
        self.assertIn("if / else-if", sg["hint"])

    def test_array_port(self):
        # Array ports became LEGAL (neosyn-studio 8c46041), so on a current jar
        # this source no longer fails at the declaration -- it fails at the USE,
        # `y.write(...)` on a fan-out that must be indexed. Both faults must
        # produce a hint; which one you get depends on the compiler, and pinning
        # either alone breaks the suite on half the compilers the kit supports.
        sg = self._suggestion(
            "package t;\n"
            "task Foo { in push u8 a; out push u8 y[4];\n"
            "  void loop() { y.write(a.read()); } }\n")
        self.assertTrue(
            "array dimensions are not accepted here" in sg["hint"]
            or "an array port is a FAN-OUT" in sg["hint"],
            f"neither array hint fired: {sg['hint']!r}")
        # The old wording claimed "only ports may not". Measured S170: a struct
        # FIELD array and a `typedef` array hit exactly the same fault, so that
        # claim was wrong two-thirds of the time.
        self.assertNotIn("only ports may not", sg["hint"])

    def test_bundle_const_used_unqualified(self):
        sg = self._suggestion(
            "package t;\n"
            "bundle P { const int N = 4; }\n"
            "task Foo { in push u8 a; out push u8 y;\n"
            "  u8 buf[N];\n"
            "  void loop() { y.write(a.read()); } }\n")
        self.assertIn("not visible", sg["hint"])

    def test_the_two_fixes_that_hint_names_actually_work(self):
        # Never ship advice that was not run. Both routes out of the previous
        # test must really compile.
        for src in (
            # qualify through the bundle
            "package t;\n"
            "bundle P { const int N = 4; }\n"
            "task Foo { in push u8 a; out push u8 y;\n"
            "  u8 buf[P.N];\n"
            "  void loop() { y.write(a.read()); } }\n",
            # or declare it in the entity that uses it
            "package t;\n"
            "task Foo { const int N = 4; in push u8 a; out push u8 y;\n"
            "  u8 buf[N];\n"
            "  void loop() { y.write(a.read()); } }\n",
        ):
            self.assertTrue(cg.check(src)["ok"], src)

    def test_cascade_does_not_produce_a_misleading_hint(self):
        # Distilled from real model-written code (a GEMM+ReLU tile): an array
        # PORT on line 2 and a `switch` on line 6. The parser derails and emits
        # `missing EOF at 'n'` far below, which the top-level-declaration rule
        # used to claim -- telling the model to move a field that was already
        # inside the task, while the two real faults went unmentioned.
        r = cg.check(
            "package t;\n"
            "task Foo { in push u8 a; out push u8 y[4];\n"
            "  enum St { A, B }\n"
            "  St s;\n"
            "  void loop() { u8 v = a.read();\n"
            "    switch (s) { case A: y.write(v); break; }\n"
            "    u8 n = 0;\n"
            "  } }\n")
        self.assertFalse(r["ok"])
        self.assertIn("suggestion", r)
        hint = r["suggestion"]["hint"]
        # On compilers that reject array ports the FIRST real fault is the
        # declaration; on current ones that line is legal and `switch` is the
        # only real fault. Either is correct -- what must never happen is the
        # cascade rule claiming a top-level-declaration problem that is not there.
        self.assertTrue(
            "array dimensions are not accepted here" in hint
            or "an array port is a FAN-OUT" in hint
            or "has no `switch`/`case`" in hint,
            f"the hint must point at a REAL fault, got: {hint!r}")
        self.assertNotIn("top-level declarations", hint)

    def test_synth_on_a_file_that_does_not_parse(self):
        # cg_synth must not read as a SYNTHESIS failure when the compile is what
        # failed — otherwise the model "fixes" the datapath of a file that never
        # parsed. Needs no yosys: it fails before yosys is reached.
        r = cg.synth("package t;\n"
                     "task Foo { in push u8 a; out push u8 y;\n"
                     "  void loop() { y.write(a.read() @@ 1); } }\n")
        self.assertFalse(r["ok"])
        self.assertEqual(r["stage"], "generate")
        self.assertIn("cg_check", r["message"])
        self.assertIn("suggestion", r)


@unittest.skipUnless(JAR_OK, "compiler jar not built")
@unittest.skipUnless(BYTECODE_OK, "the bytecode simulator is commercial-only")
class TestSimulateBytecode(unittest.TestCase):
    def test_recipe_passes(self):
        r = cg.simulate(_counter_src())
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["simulator"], "bytecode")
        self.assertFalse(r["timed_out"])


@unittest.skipUnless(JAR_OK and YOSYS_OK, "jar or yosys missing")
class TestSynth(unittest.TestCase):
    def test_generic_counter(self):
        r = cg.synth(_counter_src(), flow="generic")
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["flow"], "generic")
        self.assertIsInstance(r["cells"], int)
        self.assertGreater(r["cells"], 0)

    def test_vendor_flow_ice40(self):
        r = cg.synth(_counter_src(), flow="ice40")
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["flow"], "ice40")
        self.assertIsInstance(r["cells"], int)
        self.assertGreater(r["cells"], 0)

    def test_flows_can_differ(self):
        # Don't hard-code counts (they drift); just confirm both are positive ints
        # and that mapping to a vendor primitive set is allowed to change the count.
        g = cg.synth(_counter_src(), flow="generic")
        i = cg.synth(_counter_src(), flow="ice40")
        self.assertIsInstance(g["cells"], int)
        self.assertIsInstance(i["cells"], int)
        self.assertGreater(g["cells"], 0)
        self.assertGreater(i["cells"], 0)
        # Different flows MAY give different cell counts; assert the comparison is
        # meaningful (both ints) without pinning exact values.
        self.assertEqual(type(g["cells"]), type(i["cells"]))

    def test_bad_top_reports_error(self):
        r = cg.synth(_counter_src(), top="DoesNotExist")
        self.assertFalse(r["ok"], r)
        self.assertTrue(any("ERROR" in p for p in r.get("problems", [])),
                        f"expected an ERROR in problems, got {r.get('problems')}")

    def test_real_datapath_has_no_degenerate_warning(self):
        # SqrDist is driven by input ports → the datapath survives synthesis.
        r = cg.synth((cg._EXAMPLES_DIR / "SqrDist.cg").read_text())
        self.assertTrue(r["ok"], r)
        self.assertGreater(r["arith_ops"], 0, r)
        self.assertEqual(r["latches"], 0, r)
        self.assertEqual(r["warnings"], [], r)

    def test_constant_inputs_flag_degenerate_datapath(self):
        # A design whose arithmetic is over compile-time constants (task-level
        # fields) folds away; the tool must flag the degenerate datapath.
        # Self-contained so it doesn't depend on any recipe being constant-driven
        # (the library recipes are port-driven, so their datapaths survive).
        src = ("package t;\n"
               "task Folds {\n"
               "  out push int<32> d;\n"
               "  int<32> a = 65536; int<32> b = 32768;\n"
               "  const int<32> fxmul(int<32> x, int<32> y) {\n"
               "    return (int<32>)((((int<64>)x) * ((int<64>)y)) >> 16);\n"
               "  }\n"
               "  void loop() { d.write(fxmul(a, b)); }\n"
               "}\n")
        r = cg.synth(src)
        self.assertEqual(r["arith_ops"], 0, r)
        self.assertEqual(r["verdict"], "FOLDED", r)
        self.assertTrue(any("CONSTANT-FOLDED" in w for w in r["warnings"]),
                        f"expected a degenerate-datapath warning, got {r['warnings']}")

    def test_verdict_real_on_port_driven(self):
        r = cg.synth((cg._EXAMPLES_DIR / "SqrDist.cg").read_text())
        self.assertEqual(r["verdict"], "REAL", r)


@unittest.skipUnless(JAR_OK, "compiler jar not built")
class TestGenerateOk(unittest.TestCase):
    def test_clean_design_ok_true(self):
        r = cg.generate(_counter_src())
        self.assertTrue(r["ok"], r)
        self.assertGreater(r["file_count"], 0)
        self.assertEqual(r["diagnostics"], [])

    def test_fatal_diagnostic_forces_ok_false(self):
        # divide-by-variable is rejected by the transformer but some unaffected
        # entities still emit .v; ok must reflect the diagnostic, not just files.
        bad = ("package t;\n"
               "task DivVar { in push u8 a, b; out push u8 q;\n"
               "  void loop() { q.write((u8)(a.read() / b.read())); } }\n")
        r = cg.generate(bad)
        self.assertFalse(r["ok"], r)
        self.assertTrue(r["diagnostics"], "expected a fatal diagnostic")
        # the div-by-variable diagnostic must auto-attach a recipe suggestion
        self.assertIn("suggestion", r, r)
        self.assertEqual(r["suggestion"]["recipe"], "Recip")


@unittest.skipUnless(JAR_OK and IVERILOG_OK, "jar or iverilog/vvp missing")
class TestSimulateIverilog(unittest.TestCase):
    def test_capital_test_network_runs(self):
        # The HDL backend emits a .tb.v only for a network whose name contains
        # "Test"; the generated clock-driven TB runs under vvp. We don't assume a
        # fixed verdict — read the actual result and assert it's a coherent
        # iverilog outcome (ran/passed, or a clear compile/generate stage error).
        r = cg.simulate(TEST_NETWORK_SRC, simulator="iverilog", timeout=15)
        self.assertEqual(r["simulator"], "iverilog")
        if r["ok"]:
            # A clean run carries a top + verdict.
            self.assertIn("verdict", r)
            self.assertEqual(r.get("top"), "TestDut")
        else:
            # A non-ok result must still be a coherent shape: it either reached a
            # verdict (e.g. ran without explicit markers / timed out), or stopped
            # at a named stage, or returned a clear error. Never a blank result.
            self.assertTrue(
                ("verdict" in r) or ("stage" in r) or ("error" in r),
                f"iverilog result is incoherent: {r}")
            if "verdict" in r:
                # When it got far enough to simulate, it identified the top TB.
                self.assertEqual(r.get("top"), "TestDut")

    def test_lowercase_test_network_testbench_depends_on_the_compiler(self):
        # A lowercase `_test` network (Counter_test). Compilers up to 3.2.0 and
        # the open-source build emit NO .tb.v for it -- the capital-"Test" naming
        # requirement. That was fixed in neosyn-studio 58d847e, after which the
        # same design DOES get a testbench and simulates.
        #
        # So this asserts the fork rather than one side of it: pinning either
        # alone makes the suite fail on half the compilers the kit supports, and
        # this test previously encoded the pre-fix side as if it were permanent.
        r = cg.simulate(_counter_src(), simulator="iverilog", timeout=15)
        self.assertEqual(r["simulator"], "iverilog")
        if r["ok"]:
            return  # post-fix compiler: the documented `_test` convention works
        self.assertIn("no generated testbench", r["error"],
                      "pre-fix compilers must fail for the NAMING reason, not another")


class TestDocs(unittest.TestCase):
    def test_index_lists_topics(self):
        r = cg.docs()
        self.assertTrue(r["ok"])
        topics = {t["topic"] for t in r["topics"]}
        self.assertIn("context", topics)
        self.assertIn("riscv", topics)
        for t in r["topics"]:
            self.assertTrue(t["description"])

    def test_riscv_doc_has_content(self):
        r = cg.docs("riscv")
        self.assertTrue(r["ok"])
        self.assertIn("RV32I", r["content"])
        self.assertIn("barrel", r["content"].lower())

    def test_context_doc_loads(self):
        self.assertTrue(cg.docs("context")["ok"])

    def test_unknown_topic(self):
        r = cg.docs("nope")
        self.assertFalse(r["ok"])
        self.assertIn("error", r)
        self.assertIn("riscv", r["topics"])



class TestLint(unittest.TestCase):
    """cg_lint: every rule needs BOTH halves -- it fires on the bad program, and
    it stays silent on the good one. A rule with only the first half is a rule
    that will one day fire on everything."""

    def _rules(self, src):
        return {f["rule"] for f in cg.lint(src)["findings"]}

    GOOD = ("package t;\n"
            "task T {\n"
            "    properties { test: { a: [1,2], y: [1,2] } }\n"
            "    sync { in u8 a; out u8 y; }\n"
            "    void loop() { y.write(a.read()); }\n"
            "}\n")

    def test_good_program_is_silent(self):
        self.assertEqual(self._rules(self.GOOD), set())
        self.assertTrue(cg.lint(self.GOOD)["ok"])

    def test_fixture_checking_no_output(self):
        # Drives the input, compares nothing: passes with a DEAD dut.
        src = self.GOOD.replace("a: [1,2], y: [1,2]", "a: [1,2]")
        self.assertIn("test-checks-no-output", self._rules(src))
        self.assertFalse(cg.lint(src)["ok"])

    def test_ragged_vectors(self):
        src = self.GOOD.replace("y: [1,2]", "y: [1]")
        self.assertIn("test-vectors-ragged", self._rules(src))

    def test_ragged_is_not_flagged_for_push(self):
        # THE control for the rule above: a 4:1 reduction legitimately emits
        # fewer results than it consumes. Flagging this would be wrong.
        src = ("package t;\n"
               "network N {\n"
               "    properties { test: { a: [1,2,3,4], y: [10] } }\n"
               "    in push uint<32> a;\n"
               "    out push uint<64> y;\n"
               "}\n")
        self.assertNotIn("test-vectors-ragged", self._rules(src))

    def test_unknown_port_in_fixture(self):
        src = self.GOOD.replace("y: [1,2]", "yy: [1,2]")
        self.assertIn("test-unknown-port", self._rules(src))

    def test_multi_name_port_declaration(self):
        # `in u32 val, amt;` declares TWO ports -- the corpus caught this.
        src = ("package t;\n"
               "task T {\n"
               "    properties { test: { val: [1], amt: [1], r1: [1], r2: [1] } }\n"
               "    in u32 val, amt;\n"
               "    out u32 r1, r2;\n"
               "}\n")
        self.assertEqual(self._rules(src), set())

    def test_bool_compared_to_int(self):
        src = ("package t;\n"
               "task T {\n"
               "    properties { test: { e: [1], y: [1] } }\n"
               "    sync { in bool e; out u8 y; }\n"
               "    void loop() { bool v = e.read(); if (v == 1) { y.write(1); } }\n"
               "}\n")
        self.assertIn("bool-compared-to-int", self._rules(src))

    def test_int_compared_to_int_is_fine(self):
        # Control for the rule above: only BOOLs are flagged.
        src = ("package t;\n"
               "task T {\n"
               "    properties { test: { e: [1], y: [1] } }\n"
               "    sync { in u8 e; out u8 y; }\n"
               "    void loop() { u8 v = e.read(); if (v == 1) { y.write(1); } }\n"
               "}\n")
        self.assertNotIn("bool-compared-to-int", self._rules(src))

    def test_comments_do_not_trigger_rules(self):
        # Every rule runs on DECOMMENTED source; prose must never fire one.
        src = self.GOOD.replace("void loop()",
                                "// if (flag == 1) and a: [1,2,3] ragged\n    void loop()")
        self.assertEqual(self._rules(src), set())

    def test_corpus_is_clean(self):
        """The false-positive control: 38 validated, simulated examples. Any
        finding here is a lint bug until proven otherwise."""
        # The examples ship INSIDE the package, so locate them through the
        # module rather than relative to this file -- the flat-module layout this
        # test was written against put them beside it.
        files = sorted(cg._EXAMPLES_DIR.glob("*.cg"))
        self.assertGreater(len(files), 20, "corpus missing")
        dirty = {}
        for f in files:
            with open(f, encoding="utf-8") as fh:
                found = cg.lint(fh.read())["findings"]
            if found:
                dirty[os.path.basename(f)] = [x["rule"] for x in found]
        self.assertEqual(dirty, {}, f"lint fired on validated examples: {dirty}")



class TestSimFindings(unittest.TestCase):
    """`_sim_findings` reverse-engineers a verdict out of simulator PROSE, and the
    prose is hostile to that: the trace line has the SAME shape whether the vector
    passed or failed, and each type prints its value differently. Every case below
    was a real false positive in the first version of this code, and every one was
    caught by a control rather than by reading it. Pin them."""

    def test_passing_trace_is_not_a_failure(self):
        # THE trap: `expected 1 -> 0x1` is a MATCH. Same format as a failure;
        # only the values differ. A bare regex match calls every passing vector
        # a failure -- which is what the first version did.
        out = ("Simulation started\n"
               "port y [vector 0] expected 1 -> 0x1\n"
               "port y [vector 1] expected 2 -> 0x2\n"
               "End of simulation")
        diags, unchecked = cg._sim_findings(out)
        self.assertEqual(diags, [], "passing trace lines reported as failures")
        self.assertEqual(unchecked, [])

    def test_real_mismatch_is_reported(self):
        out = "port y [vector 0] expected 9 -> 0x1\n"
        diags, _ = cg._sim_findings(out)
        self.assertEqual(len(diags), 1)
        self.assertIn("expected 9", diags[0]["message"])

    def test_bool_notation(self):
        # bool ports print `expected 0 -> false` / `expected 1 -> true`: the two
        # sides use DIFFERENT notations for the same value.
        out = ("port found [vector 0] expected 0 -> false\n"
               "port found [vector 3] expected 1 -> true\n")
        diags, _ = cg._sim_findings(out)
        self.assertEqual(diags, [], "bool notation reported as a mismatch")

    def test_bool_mismatch_still_caught(self):
        out = "port found [vector 3] expected 1 -> false\n"
        diags, _ = cg._sim_findings(out)
        self.assertEqual(len(diags), 1)

    def test_twos_complement(self):
        # Negative expectations print as raw two's complement, so they never
        # equal their own encoding numerically. Width comes from the literal.
        out = ("port p [vector 1] expected -20 -> 0xffffffffffffffec\n"
               "port p [vector 2] expected -7 -> 0xfffffffffffffff9\n"
               "port q [vector 0] expected -1 -> 0xff\n")
        diags, _ = cg._sim_findings(out)
        self.assertEqual(diags, [], "two's complement reported as a mismatch")

    def test_signed_mismatch_still_caught(self):
        # The control for the rule above: an off-by-one negative must NOT be
        # swallowed by the sign handling.
        out = "port p [vector 1] expected -21 -> 0xffffffffffffffec\n"
        diags, _ = cg._sim_findings(out)
        self.assertEqual(len(diags), 1)
        self.assertIn("expected -21", diags[0]["message"])

    def test_unchecked_ports_are_extracted(self):
        out = 'Simulation completed successfully.\n[neosyn] warning: missing test values for port "y"'
        diags, unchecked = cg._sim_findings(out)
        self.assertEqual(unchecked, ["y"])

    def test_empty_output_is_safe(self):
        self.assertEqual(cg._sim_findings(""), ([], []))
        self.assertEqual(cg._sim_findings(None), ([], []))


@unittest.skipUnless(BYTECODE_OK, "`verified`/`ran` come from a bytecode run")
class TestVerifiedSemantics(unittest.TestCase):
    """`ok` must mean VERIFIED, not merely ran. The simulator reports
    "completed successfully" for a design that checks nothing, and the kit used
    to pass that straight through as ok:True."""

    BASE = ("package t;\ntask T {\n"
            "    properties { test: { a: [1,2], y: [1,2] } }\n"
            "    sync { in u8 a; out u8 y; }\n"
            "    void loop() { y.write(a.read()); }\n}\n")

    def test_correct_design_is_verified(self):
        r = cg.simulate(self.BASE)
        self.assertTrue(r["ok"]); self.assertTrue(r["verified"])
        self.assertEqual(r.get("diagnostics") or [], [])

    def test_no_test_block_is_not_a_pass(self):
        src = self.BASE.replace("    properties { test: { a: [1,2], y: [1,2] } }\n", "")
        r = cg.simulate(src)
        self.assertTrue(r["ran"], "it does still run")
        self.assertFalse(r["verified"]); self.assertFalse(r["ok"])
        self.assertIn("NOT VERIFIED", r["warning"])

    def test_hollow_fixture_is_not_a_pass(self):
        r = cg.simulate(self.BASE.replace(", y: [1,2]", ""))
        self.assertFalse(r["ok"])
        self.assertIn("y", r["warning"])
        self.assertIn("test-checks-no-output", [f["rule"] for f in r.get("lint", [])])

    def test_lint_is_pushed_not_offered(self):
        # The probe (2026-08-20) found cg_lint called ZERO times across four
        # model families. Findings must arrive attached to a result the model
        # already reads.
        bad = self.BASE.replace("void loop() { y.write(a.read()); }",
                                "void loop() { bool v = a.read(); if (v == 1) { y.write(1); } }")
        self.assertIn("bool-compared-to-int", [f["rule"] for f in cg.check(bad).get("lint", [])])

    def test_nothing_attached_when_clean(self):
        # Deliberate: an advisory that appears at random teaches the reader to
        # ignore it. No findings -> no key.
        self.assertNotIn("lint", cg.check(self.BASE))



class TestProbeDerivedHints(unittest.TestCase):
    """Hints added from the 2026-08-20 model probe. Each pins the compiler's
    ACTUAL message to the hint, so a reworded diagnostic fails loudly instead of
    quietly ceasing to match and leaving the model with nothing."""

    PROPS_AFTER_PORTS = ("package t;\ntask T {\n"
                         "    sync { in u8 a; out u8 y; }\n"
                         "    properties { test: { a: [1], y: [1] } }\n"
                         "    void loop() { y.write(a.read()); } }\n")

    def test_properties_position_hint_exists(self):
        """The MAPPING, independent of which compiler is installed.

        This was the probe's #1 signature (6 occurrences, never recovered from) on
        releases up to 2.9.7, where `properties` had to come first. The grammar has
        since been fixed, so the error cannot be produced on a newer compiler — but
        the kit still runs against shipped ones, so the rule stays and must say
        WHICH releases it applies to rather than asserting a rule that was removed."""
        sg = cg.suggest_for_error("mismatched input 'properties' expecting '}'")
        self.assertTrue(sg["ok"])
        self.assertIn("POSITION", sg["hint"])
        self.assertIn("2.9.7", sg["hint"], "must scope the rule to the releases it holds for")
        self.assertIn("properties", sg["source"], "a shape example should be pushed")

    def test_properties_position_against_this_compiler(self):
        """Whichever way THIS compiler behaves, it must be coherent: either it
        rejects the late block and a hint is attached, or it accepts it (grammar
        fixed) and there is nothing to hint about."""
        r = cg.check(self.PROPS_AFTER_PORTS)
        if r["ok"]:
            self.skipTest("this compiler accepts `properties` anywhere (grammar fixed)")
        self.assertIn("mismatched input 'properties'", r["diagnostics"][0]["message"])
        self.assertIn("POSITION", r["suggestion"]["hint"])

    def test_properties_first_compiles(self):
        # The control: same file, block moved up, must compile.
        src = ("package t;\ntask T {\n"
               "    properties { test: { a: [1], y: [1] } }\n"
               "    sync { in u8 a; out u8 y; }\n"
               "    void loop() { y.write(a.read()); } }\n")
        self.assertTrue(cg.check(src)["ok"])

    def test_assignment_at_entity_scope(self):
        src = ("package t;\ntask T {\n    sync { in u8 a; out u8 y; }\n"
               "    u8 s;\n    s = 5;\n"
               "    void loop() { y.write(a.read()); } }\n")
        r = cg.check(src)
        self.assertFalse(r["ok"])
        self.assertIn("setup()", r["suggestion"]["hint"])

    def test_inline_initialiser_compiles(self):
        # The control: the fix the hint recommends must actually work.
        src = ("package t;\ntask T {\n    sync { in u8 a; out u8 y; }\n"
               "    u8 s = 5;\n"
               "    void loop() { y.write(a.read() + s); } }\n")
        self.assertTrue(cg.check(src)["ok"])

    def test_u9_is_legal(self):
        """The probe listed `no viable alternative at input 'u9'` as an INVENTED
        width. It is not -- u9 and uint<9> both compile. Pinned so nobody writes
        a hint teaching a non-problem."""
        for t in ("u9", "uint<9>"):
            src = (f"package t;\ntask T {{ sync {{ in {t} a; out {t} y; }}\n"
                   f"  void loop(){{ y.write(a.read()); }} }}\n")
            self.assertTrue(cg.check(src)["ok"], f"{t} should compile")



@unittest.skipUnless(JAR_OK, "compiler jar not built")
class TestEveryShippedExampleCompiles(unittest.TestCase):
    """`cg_example`'s whole claim is that the shipped entries compile, and the
    website states the count in its own words. So compile ALL of them, on
    whatever jar is present -- COMPILING needs no simulator, so this must never
    be skipped for want of one.

    It exists because it was not there: `Lfsr.cg` used two file-scope `const`s,
    which compile only on the commercial build. The open-source compiler -- the
    one our docs say needs no licence, and the one CI runs -- answered
    `missing EOF at 'const'`. 37 of 38, while we claimed 38, on the free path a
    model is most likely to take. Fixed by moving them into a `bundle`, which
    both compilers accept."""

    def test_all_of_them(self):
        files = sorted(cg._EXAMPLES_DIR.glob("*.cg"))
        self.assertGreater(len(files), 20, "example corpus missing")
        broken = []
        for f in files:
            r = cg.check(f.read_text())
            if not r["ok"]:
                broken.append((f.name, r["diagnostics"][:1]))
        self.assertEqual(broken, [], f"{len(broken)} of {len(files)} shipped "
                                     f"examples do not compile on this jar")


class TestPushedExamplesAreValid(unittest.TestCase):
    """Anything we PUSH at a failing model is code it will copy. If a shape
    example does not compile, we are teaching the exact error we are trying to
    correct -- so every one is compiled and simulated here."""

    def _shape_examples(self):
        out = []
        for entry in cg._FAIL_HINTS:
            if len(entry) > 4 and entry[4]:
                out.append((entry[0].pattern, entry[4]))
        return out

    def test_there_is_at_least_one(self):
        self.assertTrue(self._shape_examples(), "no shape examples wired")

    def test_every_shape_example_compiles(self):
        """COMPILING needs no simulator, so this runs on every jar. Split out of
        the verify test below: skipping that one for want of the bytecode
        simulator was also skipping this, and a pushed example that does not
        PARSE is the worst case -- we would be teaching the error we are
        correcting."""
        for pattern, src in self._shape_examples():
            with self.subTest(rule=pattern[:40]):
                r = cg.check(src)
                self.assertTrue(r["ok"], f"pushed example does not compile: {r}")

    @unittest.skipUnless(BYTECODE_OK, "VERIFIES by simulating; needs the bytecode simulator")
    def test_every_shape_example_verifies(self):
        for pattern, src in self._shape_examples():
            with self.subTest(rule=pattern[:40]):
                sim = cg.simulate(src)
                self.assertTrue(sim["verified"],
                                f"pushed example verifies nothing: {sim.get('warning')}")

    def test_seed_is_pushed_on_a_matched_error(self):
        # Straight through suggest_for_error, so this does not depend on whether
        # the installed compiler still rejects a late `properties` block.
        sg = cg.suggest_for_error("mismatched input 'properties' expecting '}'")
        self.assertTrue(sg["ok"])
        self.assertTrue(sg.get("source"), "the seed was resolved and then dropped")
        self.assertIn("properties", sg["source"])



@unittest.skipUnless(BYTECODE_OK, "these validator warnings are emitted by the commercial compiler")
class TestValidatorWarningsReachTheModel(unittest.TestCase):
    """A program the IDE flags used to come back from cg_check as flatly "ok".

    Two separate holes caused that and both are closed: generate-ir ran only
    syntax/link checks (so the declarative @Check pass never happened on the CLI),
    and validator findings were emitted without a `file:line` prefix (so the kit
    could not turn them into anything structured). Between them, the call meant to
    tell a model its code is wrong was the one telling it the code was fine."""

    BOOL_CMP = ("package t;\ntask T {\n"
                "  properties { test: { a: [1], y: [1] } }\n"
                "  sync { in bool a; out u8 y; }\n"
                "  void loop() { bool v = a.read(); if (v == 1) { y.write(1); } } }\n")
    CLEAN = ("package t;\ntask T {\n"
             "  properties { test: { a: [1,2], y: [1,2] } }\n"
             "  sync { in u8 a; out u8 y; }\n  void loop() { y.write(a.read()); } }\n")

    def test_validator_warning_is_surfaced(self):
        r = cg.check(self.BOOL_CMP)
        self.assertTrue(r["ok"], "it does still compile -- this is a warning, not an error")
        self.assertTrue(r.get("warnings"), "the validator finding must reach the caller")
        self.assertIn("undefined", r["warnings"][0]["message"])

    def test_warning_carries_a_location(self):
        w = cg.check(self.BOOL_CMP)["warnings"][0]
        self.assertTrue(w["file"], "a finding with no file is not actionable")
        self.assertIsInstance(w["line"], int)

    def test_summary_says_so(self):
        # `ok` is the field a model acts on, so a bare ok:True with the objection
        # hidden in a side field would keep the old behaviour in practice.
        self.assertIn("warning", cg.check(self.BOOL_CMP)["summary"].lower())

    def test_clean_design_has_no_warnings(self):
        r = cg.check(self.CLEAN)
        self.assertTrue(r["ok"])
        self.assertNotIn("warnings", r)
        self.assertIn("OK", r["summary"])

    def test_parser_handles_unlocated_and_malformed(self):
        self.assertEqual(cg._warnings(""), [])
        self.assertEqual(cg._warnings(None), [])
        one = cg._warnings("[neosyn] warning: something vague")
        self.assertEqual(len(one), 1)
        self.assertIsNone(one[0]["file"])
        self.assertIsNone(one[0]["line"])

    def test_duplicate_warnings_collapse(self):
        out = ("[neosyn] warning: A.cg:3: same thing\n"
               "[neosyn] warning: A.cg:3: same thing\n"
               "[neosyn] warning: A.cg:9: other thing\n")
        self.assertEqual(len(cg._warnings(out)), 2)


# ==================================================== PUSHED TOOL DISCOVERY
# A drifted model invents tool names (`cg_compile`, `cg_run`) and then loops on
# them. The real names are in the system prompt, which is exactly the thing a
# drifted model stops re-reading -- and the 2026-08-20 probe showed you cannot
# DEPEND on it calling a discovery tool either. So the roster is pushed. These
# tests pin both halves: it arrives where drift is visible, and it does NOT
# arrive on the calls that are going fine.
class TestToolRoster(unittest.TestCase):
    """The roster itself: generated from the registry, and matching on names a
    model actually invents."""

    def test_roster_is_generated_from_the_registry(self):
        names = [t["name"] for t in cg.tool_roster()]
        self.assertEqual(names, [f.__name__ for f in cg._MCP_TOOLS])
        for expected in ("cg_check", "cg_simulate", "cg_generate_verilog",
                         "cg_synth", "cg_scaffold", "cg_capabilities", "cg_example",
                         "cg_lint", "cg_report", "cg_suggest_for_error",
                         "cg_fsm", "cg_graph", "cg_docs"):
            self.assertIn(expected, names)

    def test_roster_follows_the_registry(self):
        """The anti-drift property, asserted instead of asserted-in-a-comment:
        registering a tool adds it to the roster, because there is no second
        list to forget. A hardcoded roster would pass every other test here and
        still go stale the first time a tool is renamed."""
        def cg_fake_tool():
            """Only exists inside this test."""
        registered = cg._tool("a tool that only exists inside this test")(cg_fake_tool)
        try:
            self.assertIn("cg_fake_tool — a tool that only exists inside this test",
                          cg._roster_lines())
            self.assertIn("cg_fake_tool",
                          " ".join(cg.unknown_tool("cg_nope")["available_tools"]))
        finally:
            cg._MCP_TOOLS.remove(registered)
        self.assertNotIn("cg_fake_tool", " ".join(cg._roster_lines()))

    def test_every_tool_has_a_roster_line(self):
        for t in cg.tool_roster():
            self.assertTrue(t["summary"], f"{t['name']} has no roster summary")
            self.assertLess(len(t["summary"]), 100, t["name"])

    def test_every_alias_points_at_a_real_tool(self):
        """The alias table is the one hand-written part, so it is the part that
        could name a tool that does not exist. It cannot: every VALUE is checked
        against the registry here."""
        names = {t["name"] for t in cg.tool_roster()}
        for wrong, real in cg._TOOL_ALIASES.items():
            self.assertIn(real, names, f"alias {wrong} -> {real} names no tool")
            self.assertNotIn(wrong, names, f"alias {wrong} IS a real tool")

    def test_did_you_mean_catches_the_other_toolchain_name(self):
        # The founder's own example, and the reason edit distance alone is not
        # enough: cg_compile -> cg_check is a 5-character edit on 10 characters.
        self.assertEqual(cg.did_you_mean("cg_compile"), "cg_check")
        self.assertEqual(cg.did_you_mean("cg_run"), "cg_simulate")
        self.assertEqual(cg.did_you_mean("cg_synthesize"), "cg_synth")
        self.assertEqual(cg.did_you_mean("diagnose_error"), "cg_suggest_for_error")
        self.assertEqual(cg.did_you_mean("cg_template"), "cg_scaffold")

    def test_did_you_mean_catches_a_typo(self):
        self.assertEqual(cg.did_you_mean("cg_smulate"), "cg_simulate")
        self.assertEqual(cg.did_you_mean("cg_chekc"), "cg_check")
        self.assertEqual(cg.did_you_mean("cg_scafold"), "cg_scaffold")

    def test_did_you_mean_ignores_case_separators_and_host_prefix(self):
        # A host namespaces the tools it exposes; a model echoing the namespaced
        # form back is not confused about WHICH tool it wants.
        for spelling in ("cg_check", "CG_Check", "check", "cg.check", "cgCheck",
                         "mcp__cg__cg_check", "cg-check", "cg_check_source"):
            self.assertEqual(cg.did_you_mean(spelling), "cg_check", spelling)

    def test_did_you_mean_gives_up_rather_than_guessing(self):
        # A wrong "did you mean" is worse than none: it sends the model at a
        # tool that cannot do the job.
        self.assertIsNone(cg.did_you_mean("write_me_a_haiku"))
        self.assertIsNone(cg.did_you_mean(""))
        self.assertIsNone(cg.did_you_mean("cg_check", known=[]))

    def test_unknown_tool_names_every_real_tool(self):
        r = cg.unknown_tool("cg_compile")
        self.assertFalse(r["ok"])
        self.assertEqual(r["did_you_mean"], "cg_check")
        self.assertIn("cg_compile", r["error"])
        listed = {line.split(" — ")[0] for line in r["available_tools"]}
        self.assertEqual(listed, {t["name"] for t in cg.tool_roster()})

    def test_unknown_tool_message_is_self_contained_text(self):
        # The MCP layer can only carry a STRING here (it returns str(exception)
        # as the tool result), so the text has to stand on its own.
        msg = cg.unknown_tool_message("cg_compile")
        self.assertIn("no `cg_compile` tool", msg)
        self.assertIn("Did you mean `cg_check`?", msg)
        for t in cg.tool_roster():
            self.assertIn(t["name"], msg)

    def test_unknown_tool_message_stays_cheap(self):
        # Cost discipline, pinned: the roster is names + one line each, never
        # the argument schemas the host already has.
        self.assertLess(len(cg.unknown_tool_message("cg_compile")), 2500)

    def test_a_discovery_call_is_answered_with_the_list(self):
        """`cg_list_tools` is not a tool -- and calling it works anyway. That is
        the pull affordance for free: no tool slot, no system-prompt tokens, and
        it answers whatever name the model guessed for it."""
        for guess in ("cg_list_tools", "list_tools", "cg_tools", "tools"):
            r = cg.unknown_tool(guess)
            self.assertIn("if you were asking what exists", r["error"], guess)
            self.assertTrue(r["available_tools"])

    def test_a_caller_with_its_own_tool_list_gets_that_list(self):
        """cg_local_client exposes a deliberate 4-tool subset; pushing the MCP
        server's 13 there would name tools its loop cannot dispatch."""
        subset = [{"name": "cg_check", "summary": "type-check"},
                  {"name": "cg_simulate", "summary": "run it"}]
        r = cg.unknown_tool("cg_synth", known=subset)
        self.assertEqual(r["available_tools"], ["cg_check — type-check", "cg_simulate — run it"])
        self.assertIsNone(r["did_you_mean"])
        self.assertEqual(cg.unknown_tool("cg_compile", known=subset)["did_you_mean"],
                         "cg_check")


class TestUnknownToolGuard(unittest.TestCase):
    """The guard that puts the roster in front of an unknown-tool call.

    The stub mirrors what both SDK versions expose on `_tool_manager` (an async
    `call_tool` + `get_tool`), so the wiring is testable with no mcp installed;
    TestRosterThroughTheRealServer runs the same path through the real one."""

    class _Manager:
        def __init__(self, tools=("cg_check",), raises=None):
            self.tools, self.raises, self.calls = set(tools), raises, []

        def get_tool(self, name):
            return object() if name in self.tools else None

        async def call_tool(self, name, arguments, *a, **kw):
            self.calls.append(name)
            if self.raises:
                raise self.raises
            return {"called": name, "arguments": arguments}

    def _guarded(self, **kw):
        mgr = self._Manager(**kw)
        srv = type("_Srv", (), {})()
        srv._tool_manager = mgr
        self.assertTrue(cg.install_unknown_tool_guard(srv))
        return mgr

    def test_unknown_tool_call_answers_with_the_roster(self):
        mgr = self._guarded()
        with self.assertRaises(cg.UnknownToolError) as cm:
            asyncio.run(mgr.call_tool("cg_compile", {}))
        msg = str(cm.exception)
        self.assertIn("Did you mean `cg_check`?", msg)
        for t in cg.tool_roster():
            self.assertIn(t["name"], msg)
        self.assertEqual(mgr.calls, [], "an unknown tool must not reach the SDK")

    def test_a_real_call_passes_straight_through(self):
        mgr = self._guarded()
        self.assertEqual(asyncio.run(mgr.call_tool("cg_check", {"source": "x"})),
                         {"called": "cg_check", "arguments": {"source": "x"}})

    def test_an_sdk_unknown_tool_error_is_upgraded(self):
        # Belt and braces: if a future SDK decides a tool is unknown after we
        # let the call through, the model still gets the roster.
        mgr = self._guarded(raises=ValueError("Unknown tool: cg_check"))
        with self.assertRaises(cg.UnknownToolError) as cm:
            asyncio.run(mgr.call_tool("cg_check", {}))
        self.assertIn("cg_check", str(cm.exception))

    def test_a_genuine_failure_is_not_swallowed(self):
        mgr = self._guarded(raises=ValueError("boom"))
        with self.assertRaisesRegex(ValueError, "boom"):
            asyncio.run(mgr.call_tool("cg_check", {}))

    def test_a_synchronous_tool_manager_is_also_guarded(self):
        # No shipping SDK has a sync call_tool; the branch exists so a future one
        # cannot silently drop the roster, and it is cheap to pin.
        class _Sync:
            def get_tool(self, name):
                return None

            def call_tool(self, name, arguments, *a, **kw):
                return {"called": name}

        srv = type("_Srv", (), {})()
        srv._tool_manager = _Sync()
        self.assertTrue(cg.install_unknown_tool_guard(srv))
        with self.assertRaises(cg.UnknownToolError):
            srv._tool_manager.call_tool("cg_compile", {})

    def test_guard_is_idempotent(self):
        mgr = self._Manager()
        srv = type("_Srv", (), {})()
        srv._tool_manager = mgr
        self.assertTrue(cg.install_unknown_tool_guard(srv))
        self.assertFalse(cg.install_unknown_tool_guard(srv))

    def test_a_server_without_a_tool_manager_still_starts(self):
        # Advice must never break the tool: an SDK that moves its internals
        # costs us the roster, not the server.
        self.assertFalse(cg.install_unknown_tool_guard(object()))


class TestOffTrackPushesTheRoster(unittest.TestCase):
    """Second push point: a real tool told to use a thing that does not exist.
    Same drift as an invented tool name, one level down."""

    def test_unknown_simulator(self):
        r = cg.simulate("task X {}\n", simulator="ghdl")
        self.assertIn("available_tools", r)
        self.assertIn("cg_capabilities", r["tools_note"])

    def test_unknown_scaffold_kind(self):
        self.assertIn("available_tools", cg.scaffold(kind="counter"))

    def test_unknown_generate_target(self):
        self.assertIn("available_tools", cg.generate("task X {}\n", target="systemverilog"))

    def test_unknown_docs_topic(self):
        r = cg.docs("verilog")
        self.assertIn("available_tools", r)
        self.assertIn("riscv", r["topics"], "the topic list must survive the push")

    @unittest.skipUnless(YOSYS_OK, "yosys not installed")
    def test_unknown_synth_flow(self):
        # The yosys-presence check runs first, so this needs yosys to reach the
        # flow guard at all (same gate as TestFlowAndSimulatorGuards).
        self.assertIn("available_tools",
                      cg.synth(_counter_src() if JAR_OK else "task X {}\n", flow="bogus"))


class TestTheCommonCaseIsNotTaxed(unittest.TestCase):
    """The negative half, and the one that keeps this honest: a call that is
    going fine gets NOTHING appended. Pushing the roster onto every result would
    tax the loop that already works, and an advisory that turns up everywhere is
    one the reader learns to skip."""

    GOOD = ("package t;\ntask T {\n"
            "  properties { test: { a: [1,2], y: [1,2] } }\n"
            "  sync { in u8 a; out u8 y; }\n  void loop() { y.write(a.read()); } }\n")

    def setUp(self):
        # The session-start push fires once per PROCESS; consume it so these
        # assertions are about the ordinary path, not about call ordering.
        self._saved = cg._ROSTER_PUSHED
        cg._ROSTER_PUSHED = True

    def tearDown(self):
        cg._ROSTER_PUSHED = self._saved

    def test_a_successful_tool_call_has_no_roster(self):
        for result in (cg.cg_lint(self.GOOD), cg.cg_docs(), cg.cg_example("counter"),
                       cg.cg_suggest_for_error("mismatched input 'properties'")):
            self.assertNotIn("available_tools", result)
            self.assertNotIn("tools_note", result)

    def test_a_lint_finding_has_no_roster(self):
        # The model is holding the right tool and the finding is the answer.
        bad = self.GOOD.replace("y: [1,2] ", "")
        r = cg.cg_lint(bad)
        self.assertTrue(r["findings"], "expected the hollow-fixture finding")
        self.assertNotIn("available_tools", r)

    @unittest.skipUnless(JAR_OK, "compiler jar not built")
    def test_an_ordinary_compile_error_has_no_roster(self):
        r = cg.cg_check(self.GOOD.replace("void loop()", "void loop() @@@", 1))
        self.assertFalse(r["ok"])
        self.assertTrue(r["diagnostics"])
        self.assertNotIn("available_tools", r,
                         "a compile error is not drift -- the diagnostics are the answer")

    @unittest.skipUnless(JAR_OK, "compiler jar not built")
    def test_a_failing_simulation_has_no_roster(self):
        wrong = self.GOOD.replace("y: [1,2]", "y: [9,9]")
        r = cg.cg_simulate(wrong, report_dir="")
        self.assertFalse(r["ok"])
        self.assertNotIn("available_tools", r)


class TestSessionStartPush(unittest.TestCase):
    """Third push point: once, on the first tool call, so the exact names land
    before drift starts rather than after it."""

    def setUp(self):
        self._saved = cg._ROSTER_PUSHED
        cg._ROSTER_PUSHED = False

    def tearDown(self):
        cg._ROSTER_PUSHED = self._saved
        os.environ.pop("CG_TOOL_ROSTER", None)

    def test_first_call_carries_the_roster_and_the_second_does_not(self):
        first = cg.cg_lint("task X {}\n")
        self.assertIn("available_tools", first)
        self.assertIn("once", first["tools_note"])
        self.assertNotIn("available_tools", cg.cg_lint("task X {}\n"))

    def test_it_rides_on_whatever_the_first_call_happens_to_be(self):
        self.assertIn("available_tools", cg.cg_suggest_for_error("no such error"))

    def test_the_push_can_be_switched_off(self):
        # A knob to price the push: it is the only roster push that is optional.
        os.environ["CG_TOOL_ROSTER"] = "off"
        self.assertNotIn("available_tools", cg.cg_lint("task X {}\n"))

    def test_capabilities_is_not_pushed_twice(self):
        # cg_capabilities carries the roster by construction, so the session
        # push must not stack a second copy (or a contradictory note) on it.
        r = cg.cg_capabilities()
        self.assertEqual(len([k for k in r if k == "available_tools"]), 1)
        self.assertNotIn("tools_note", r)

    def test_capabilities_separates_binaries_from_tools(self):
        r = cg.capabilities()
        self.assertIn("iverilog", r["tools"], "`tools` stays the BINARIES probed here")
        self.assertEqual({line.split(" — ")[0] for line in r["available_tools"]},
                         {t["name"] for t in cg.tool_roster()})


class TestNoStaleToolNames(unittest.TestCase):
    """A different root cause for the same symptom, closed off: text the kit
    PUSHES at a model naming a tool that does not exist. Nothing does today --
    this test is what keeps it that way through the next rename."""

    def test_model_facing_text_names_only_real_tools(self):
        real = {t["name"] for t in cg.tool_roster()}
        # Files in the kit share the `cg_` prefix (cg_context.md, cg_riscv.md,
        # cg_local_client.py); they are legitimate mentions, and reading them off
        # disk keeps this allowlist from becoming its own stale list.
        # `_TOOL_ALIASES` keys are the registry of names that are deliberately NOT
        # tools (test_every_alias_points_at_a_real_tool asserts exactly that), so
        # quoting one as a counter-example is fine.
        allowed = real | set(cg._TOOL_ALIASES) | {p.stem for p in cg._HERE.iterdir()}
        texts = [f.__doc__ or "" for f in cg._MCP_TOOLS]
        texts += [entry[2] for entry in cg._FAIL_HINTS]          # pushed on failure
        texts += [p.read_text(errors="replace") for p in sorted(cg._HERE.rglob("*.md"))]
        bad = {tok for t in texts for tok in re.findall(r"\bcg_[a-z_]+", t)
               if tok not in allowed and not tok.startswith("cg_mcp")}
        self.assertEqual(bad, set(),
                         f"model-facing text names tools that do not exist: {sorted(bad)}")


class TestLocalClientUnknownTool(unittest.TestCase):
    """The kit's OTHER model-facing surface. cg_local_client dispatches tool
    calls from a small local model and its unknown-tool branch used to answer
    `{"error": "unknown tool X"}` -- nothing to recover with. It now answers with
    ITS OWN roster: the 4-tool subset it can actually dispatch, read off the
    schemas it sends. Pushing the server's 13 there would name tools this loop
    cannot run, which is a worse failure than the one being fixed."""

    def test_unknown_tool_gets_this_clients_roster(self):
        import cg_local_client as client
        r = client.dispatch("cg_compile", {})
        self.assertFalse(r["ok"])
        self.assertEqual(r["did_you_mean"], "cg_check")
        listed = {line.split(" — ")[0] for line in r["available_tools"]}
        self.assertEqual(listed, set(client.DISPATCH))

    def test_it_never_names_a_tool_it_cannot_run(self):
        import cg_local_client as client
        r = client.dispatch("cg_synth", {})      # a real MCP tool, not wired here
        self.assertNotIn("cg_synth", " ".join(r["available_tools"]))

    def test_a_real_tool_still_dispatches(self):
        # What this proves is that DISPATCH works, so it needs input the tool will
        # accept. It used `task X {}` -- no `package` line, so not C\u23da, which
        # cg_check has always refused; lint certified it only because lint used to
        # certify anything (F102). Now it needs a real, if minimal, design.
        import cg_local_client as client
        src = "package t;\ntask X { out sync u8 y; void loop() { y.write(1); } }\n"
        self.assertTrue(client.dispatch("cg_lint", {"source": src})["ok"])


class TestSystemPromptCoversEveryTool(unittest.TestCase):
    """cg_context.md is the SYSTEM PROMPT this kit ships, and it enumerates the
    tools in prose -- a hand-maintained roster in the one place a model reads
    first. It had drifted: it named 11 of 13, missing `cg_lint` (the tool S168
    shipped to be called FIRST) and `cg_report`. A model cannot call what its own
    system prompt never mentions, so this list is now checked against the
    registry like every other roster in the kit."""

    def test_the_prompt_enumerates_every_registered_tool(self):
        txt = (cg._HERE / "cg_context.md").read_text()
        m = re.search(r"You have compiler tools \(([^)]*)\)", txt, re.S)
        self.assertIsNotNone(m, "the tool enumeration must stay machine-checkable")
        listed = set(re.findall(r"`(cg_\w+)`", m.group(1)))
        self.assertEqual(listed, {t["name"] for t in cg.tool_roster()})


class TestStaticRostersMatchTheRegistry(unittest.TestCase):
    """Every roster written by hand rather than generated: the README table and
    the module docstring. Both HAD drifted -- the README said "Eight tools" for
    thirteen and omitted cg_report, the module docstring listed 11 of 13. That is
    the failure mode the pushed roster is built to be immune to, so the static
    copies are checked against the registry too."""

    def test_the_table_lists_every_registered_tool(self):
        # README.md lives at the REPO root, not inside the package -- they
        # coincided only in the flat-module layout this test came from.
        readme = (pathlib.Path(__file__).parent / "README.md").read_text()
        listed = set(re.findall(r"^\| `(cg_\w+)` \|", readme, re.M))
        self.assertEqual(listed, {t["name"] for t in cg.tool_roster()})

    def test_the_module_docstring_lists_every_tool(self):
        # The developer-facing roster at the top of cg_mcp_server.py. It had
        # drifted too (11 of 13: no cg_report, no cg_docs).
        block = re.search(r"Tools exposed:\n(.*?)\n\n", cg.__doc__, re.S)
        self.assertIsNotNone(block)
        listed = set(re.findall(r"^\s{2}(cg_\w+)", block.group(1), re.M))
        self.assertEqual(listed, {t["name"] for t in cg.tool_roster()})

    def test_the_stated_count_is_the_real_count(self):
        # README.md lives at the REPO root, not inside the package -- they
        # coincided only in the flat-module layout this test came from.
        readme = (pathlib.Path(__file__).parent / "README.md").read_text()
        m = re.search(r"^(\d+) tools\.", readme, re.M)
        self.assertIsNotNone(m, "the tool-count sentence must stay machine-checkable")
        self.assertEqual(int(m.group(1)), len(cg.tool_roster()))


@unittest.skipUnless(MCP_OK, "mcp package not installed")
class TestRosterThroughTheRealServer(unittest.TestCase):
    """The same paths through the actual SDK. Verified against mcp 2.0.0:
    `_tool_manager.call_tool` is where "Unknown tool" is decided, and
    `_handle_call_tool` returns any non-protocol exception to the model as an
    is_error tool result whose text is str(exception) -- so what is raised here
    is exactly what the model reads."""

    def test_registered_tools_are_exactly_the_roster(self):
        srv = cg.build_server()
        self.assertEqual(sorted(t.name for t in asyncio.run(srv.list_tools())),
                         sorted(t["name"] for t in cg.tool_roster()))

    def test_the_wrapper_does_not_disturb_the_tool_schema(self):
        # @_tool wraps every tool, and the MCP layer builds its schema from the
        # signature -- a wrapper that hid it behind (*args, **kwargs) would ship
        # 13 argument-less tools.
        srv = cg.build_server()
        tools = {t.name: t for t in asyncio.run(srv.list_tools())}
        schema = _input_schema(tools["cg_scaffold"])
        self.assertEqual(sorted(schema["properties"]),
                         ["inputs", "kind", "name", "outputs", "package", "verify"])
        self.assertTrue(tools["cg_check"].description.startswith("Parse, scope"))

    def test_an_unknown_tool_call_returns_the_roster(self):
        srv = cg.build_server()
        with self.assertRaises(cg.UnknownToolError) as cm:
            asyncio.run(srv.call_tool("cg_compile", {"source": "x"}))
        self.assertIn("Did you mean `cg_check`?", str(cm.exception))
        for t in cg.tool_roster():
            self.assertIn(t["name"], str(cm.exception))


if __name__ == "__main__":
    unittest.main()
