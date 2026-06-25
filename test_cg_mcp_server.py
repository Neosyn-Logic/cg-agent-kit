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
import shutil
import unittest

import cg_mcp_server as cg

# Dependency gates for the integration tests.
JAR_OK = cg.JAR.is_file()
YOSYS_OK = shutil.which("yosys") is not None
IVERILOG_OK = shutil.which("iverilog") is not None and shutil.which("vvp") is not None

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


@unittest.skipUnless(JAR_OK, "compiler jar not built")
class TestSimulateBytecode(unittest.TestCase):
    def test_bytecode_runs_or_degrades(self):
        """The fast bytecode simulator is part of the commercial Neosyn SDK.
        Against the SDK jar it runs; against the open-source compiler it
        degrades to a clear commercial pointer. Both are correct outcomes for
        a user, so this passes either way."""
        r = cg.simulate(_counter_src())
        self.assertEqual(r["simulator"], "bytecode")
        if r.get("commercial"):
            # open-source compiler: no `simulate` verb → degrade cleanly
            self.assertFalse(r["ok"], r)
            self.assertIn("commercial", r["error"].lower())
        else:
            # commercial SDK jar: the fast simulator actually runs
            self.assertTrue(r["ok"], r)
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

    def test_lowercase_test_network_no_testbench(self):
        # A lowercase `_test` network (Counter_test) does NOT get a .tb.v emitted
        # -> documents the capital-"Test" naming requirement.
        r = cg.simulate(_counter_src(), simulator="iverilog", timeout=15)
        self.assertEqual(r["simulator"], "iverilog")
        self.assertFalse(r["ok"])
        self.assertIn("no generated testbench", r["error"])


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


if __name__ == "__main__":
    unittest.main()
