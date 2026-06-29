#!/usr/bin/env python3
"""
C⏚ (Cg) MCP server — the Neosyn compiler as tools for any LLM host.

Gives an MCP-capable model (Claude Desktop/Code, Cursor, Cline, …) the
ability to write → check → simulate → generate Verilog for C⏚ and
self-correct against the *real* compiler, with no model retraining. The
language knowledge lives in `cg_context.md` (load it as a system prompt);
this server is the ground-truth verification loop that makes the model's
C⏚ actually correct.

Tools exposed:
  cg_check             parse/scope/type-check; returns diagnostics
  cg_simulate          run the fast bytecode simulator; returns its output
  cg_generate_verilog  emit synthesizable Verilog (also vhdl)
  cg_synth             yosys-synthesize the Verilog; verdict + cell count + warnings
  cg_example           scored lookup into the validated-code dictionary
  cg_suggest_for_error map a compiler error to the recipe with the fix pattern
  cg_fsm               a task's compiled state machine (states/transitions)
  cg_graph             a network's compiled graph (instances/ports/edges)

The jar is the open-source C⏚ Verilog compiler (github.com/Neosyn-Logic/
cg-compiler), found via $CG_JAR or the default build path. It needs no
license. The fast bytecode simulator is part of the commercial Neosyn
distribution; without it, cg_simulate falls back to the 'iverilog' backend
(generate Verilog + run Icarus Verilog).

The core functions (check/simulate/generate/fsm/graph) have no MCP
dependency, so they can be unit-tested directly:

    import cg_mcp_server as cg
    print(cg.simulate(open("Foo.cg").read()))

Run as a server:  python cg_mcp_server.py   (after `pip install mcp`)
"""
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

# Point $CG_JAR at your built open-source compiler jar
# (github.com/Neosyn-Logic/cg-compiler -> releng/lsp-server/target/).
JAR = Path(os.environ.get(
    "CG_JAR",
    str(Path.home() / "cg-compiler/releng/lsp-server/target/cg-language-server.jar"),
))
# NEOSYN_CG_DEV is harmless for the open jar (no license gate); kept so the
# same env also works against the commercial SDK jar.
ENV = {**os.environ, "NEOSYN_CG_DEV": os.environ.get("NEOSYN_CG_DEV", "1")}

# Compiler diagnostics look like:  [neosyn] Foo.cg:12: mismatched input ...
_DIAG = re.compile(r"^\[neosyn\]\s+([^:]*\.cg):(\d+):\s*(.*)$", re.M)
# Transform / HDL-emit errors aren't in file:line form — e.g.
#   [neosyn] Transform error in test.N_c: IllegalArgumentException — modulo by 3 ...
# Surface their message too so the model sees *why* it failed (self-repair),
# not a blank "unknown error".
_XFORM_ERR = re.compile(
    r"^\[neosyn\]\s+(?:Transform|HDL emit) error in (\S+?):\s*(.*)$", re.M)
# Noise lines to strip from human-facing output.
_NOISE = re.compile(r"^\[(CgLanguageServer|CLI)\]|^Running simulation:|License:|"
                    r"^\s*at (java|com)\.|^Caused by:|UnixException|AccessDenied")


def _entity_name(source: str) -> str:
    """Top entity name → the temp file is named <Entity>.cg (the CLI keys off it)."""
    m = re.search(r"^\s*(?:network|task|bundle)\s+(\w+)", source, re.M)
    return m.group(1) if m else "Main"


def _test_entity(source: str) -> str | None:
    """Which entity to simulate when a file holds several. The CLI auto-picks the
    first/top entity — and for the common `task Foo` + `network Foo_test` layout
    that's the bare task, whose monitor never runs (output looks empty / `[null]`).
    Prefer a network carrying a `test` property, else a `*_test` network, else
    None (let the CLI auto-pick — single-entity files are unaffected)."""
    for m in re.finditer(r"\bnetwork\s+(\w+)\s*\{", source):
        if re.search(r"properties\s*\{[^}]*\btest\b", source[m.end():m.end() + 800]):
            return m.group(1)
    m = re.search(r"\bnetwork\s+(\w+_test)\b", source)
    return m.group(1) if m else None


def _is_testbench(name: str | None, source: str) -> bool:
    """True if `name` is a simulation harness (a *_test network or one carrying a
    `test` property). Synthesizing one folds its constant driver to 0 cells — it
    is never the synthesizable DUT."""
    if not name:
        return False
    return name.endswith("_test") or name == _test_entity(source)


def _dut_of(top: str, source: str) -> str:
    """Retarget a testbench `top` to the real DUT it wraps: the `_test`-stripped
    name if it exists as a task/network, else the first non-testbench entity.
    Synthesizing a `*_test` harness is never what's wanted (it constant-folds)."""
    if not _is_testbench(top, source):
        return top
    if top.endswith("_test"):
        base = top[: -len("_test")]
        if re.search(rf"^\s*(?:task|network)\s+{re.escape(base)}\b", source, re.M):
            return base
    return _synth_top(source)


def _diagnostics(output: str):
    out = []
    seen = set()
    for m in _DIAG.finditer(output):
        d = {"file": m.group(1), "line": int(m.group(2)), "message": m.group(3).strip()}
        key = (d["file"], d["line"], d["message"])
        if key not in seen:
            seen.add(key)
            out.append(d)
    # Fallback: capture transform / HDL-emit error messages (no file:line) so the
    # model still sees the cause instead of a blank error.
    for m in _XFORM_ERR.finditer(output):
        msg = m.group(2).strip()
        # strip a leading "SomeException — " and a trailing "(re-run with ...)"
        msg = re.sub(r"^[A-Za-z_]+(?:Exception|Error)\s*[—-]\s*", "", msg)
        msg = re.sub(r"\s*\(re-run with[^)]*\)\s*$", "", msg)
        key = (None, None, msg)
        if msg and key not in seen:
            seen.add(key)
            out.append({"file": None, "line": None, "entity": m.group(1), "message": msg})
    return out


def _clean(output: str, limit: int = 120) -> str:
    lines = [ln for ln in output.splitlines() if ln.strip() and not _NOISE.search(ln)]
    if len(lines) > limit:
        lines = lines[:limit] + [f"... ({len(lines) - limit} more lines)"]
    return "\n".join(lines)


def _run(subcmd: str, source: str, flags: list | None = None,
         extra_files: dict | None = None, timeout: int = 60):
    """Write `source` (+ any extra_files) into an ISOLATED temp dir — the
    compiler scans sibling .cg files, so it must see only what we give it —
    then run the jar as `<subcmd> <src> <flags...>` (the CLI wants the path
    first). Returns (rc, combined_output, timed_out, src_path)."""
    if not JAR.is_file():
        raise FileNotFoundError(
            f"cg-language-server.jar not found at {JAR}. Build the open-source "
            f"compiler (github.com/Neosyn-Logic/cg-compiler): "
            f"`cd releng && mvn install -DskipTests && cd lsp-server && mvn package`, "
            f"then set $CG_JAR to the built jar.")
    work = Path(tempfile.mkdtemp(prefix="cg_mcp_"))
    try:
        src = work / f"{_entity_name(source)}.cg"
        src.write_text(source)
        for name, content in (extra_files or {}).items():
            p = work / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content)
        cmd = ["java", "-jar", str(JAR), subcmd, str(src)] + (flags or [])
        try:
            p = subprocess.run(cmd, env=ENV, timeout=timeout,
                               capture_output=True, text=True, errors="replace")
            return p.returncode, (p.stdout or "") + (p.stderr or ""), False, src.name
        except subprocess.TimeoutExpired as e:
            so = e.stdout or ""
            se = e.stderr or ""
            if isinstance(so, bytes):
                so = so.decode("utf-8", "replace")
            if isinstance(se, bytes):
                se = se.decode("utf-8", "replace")
            return 124, so + se, True, src.name
    finally:
        shutil.rmtree(work, ignore_errors=True)


def _package_files(package_dir: str | None) -> dict:
    """Read every *.cg in a same-package project directory as {filename: content}
    so a multi-file design resolves through the tools the way it does in the IDE
    (the compiler scans siblings, but the temp-dir run only sees what we hand it).
    `package_dir` is resolved under $PROJECT_ROOT (set by the MCP host) when
    relative. Best-effort: a missing/unreadable dir yields {} — i.e. the old
    single-source behaviour, no regression."""
    if not package_dir:
        return {}
    try:
        base = Path(os.environ.get("PROJECT_ROOT", ".")).resolve()
        d = Path(package_dir)
        d = (base / d if not d.is_absolute() else d).resolve()
        if not d.is_dir():
            return {}
        return {p.name: p.read_text() for p in sorted(d.glob("*.cg"))}
    except OSError:
        return {}


def _merge_pkg(source: str, package_dir: str | None, extra_files: dict | None) -> dict:
    """Merge same-package siblings (from package_dir) under any explicit
    extra_files, dropping the source's own entity file so it isn't defined twice."""
    pkg = _package_files(package_dir)
    if pkg:
        pkg.pop(f"{_entity_name(source)}.cg", None)
    return {**pkg, **(extra_files or {})}


# ----------------------------------------------------------------- core tools
def check(source: str, extra_files: dict | None = None,
          package_dir: str | None = None) -> dict:
    """Validate C⏚ (parse + scope + type-check via IR generation), no run."""
    rc, out, _, _ = _run("generate-ir", source,
                         extra_files=_merge_pkg(source, package_dir, extra_files))
    diags = _diagnostics(out)
    return _attach_suggestion({
        "ok": rc == 0 and not diags, "diagnostics": diags,
        "summary": "OK — compiles cleanly" if (rc == 0 and not diags)
                   else f"{len(diags) or 'unknown'} error(s)"})


def simulate(source: str, extra_files: dict | None = None, timeout: int = 60,
             simulator: str = "bytecode", package_dir: str | None = None) -> dict:
    """Run a simulator on the design. `simulator` selects the backend:

    - 'bytecode' (default) — the compiler's fast bytecode simulator. No HDL
      toolchain needed; a `properties { test: {...} }` block self-checks.
    - 'iverilog' — generate Verilog + testbench and run Icarus Verilog (`vvp`).
      A Verilog-level cross-check; needs a `network <Name>_test` so a testbench
      is emitted.
    - 'verilator' — accepted for forward-compat; reported unavailable unless the
      `verilator` binary is installed.

    The model reads `output` to confirm behaviour, or `diagnostics`/`stage` to
    fix a compile error."""
    extra_files = _merge_pkg(source, package_dir, extra_files)
    backend = (simulator or "bytecode").lower()
    if backend in ("bytecode", "fast", "cg"):
        ent = _test_entity(source)
        flags = ["--entity", ent] if ent else None
        rc, out, to, _ = _run("simulate", source, flags=flags, extra_files=extra_files, timeout=timeout)
        # The open-source compiler has no `simulate` verb — the fast bytecode
        # simulator is part of the commercial Neosyn distribution. Degrade with
        # a clear pointer rather than surfacing a raw "Unknown command".
        if "unknown command" in out.lower():
            return {"ok": False, "simulator": "bytecode", "commercial": True,
                    "error": "The fast bytecode simulator is part of the commercial "
                             "Neosyn SDK and is not in the open-source compiler. Use "
                             "simulator='iverilog' for a Verilog-level check, or get "
                             "the SDK at https://neosyn.io."}
        diags = _diagnostics(out)
        passed = (rc == 0 and not to and not diags
                  and "completed successfully" in out.lower())
        return _attach_suggestion({
            "ok": passed, "simulator": "bytecode", "timed_out": to,
            "diagnostics": diags, "output": _clean(out)})
    if backend in ("iverilog", "icarus", "verilog", "vvp"):
        return _simulate_iverilog(source, extra_files, timeout)
    if backend == "verilator":
        why = ("verilator is not installed on this host"
               if shutil.which("verilator") is None
               else "the verilator backend isn't wired in this kit yet")
        return {"ok": False, "simulator": "verilator",
                "error": f"{why}; use simulator='iverilog' (Verilog-level) or "
                         f"'bytecode' (default)"}
    return {"ok": False, "error": f"unknown simulator '{simulator}' — choose "
            f"'bytecode' or 'iverilog'"}


def _verilog_lib_dirs(out_dir: Path) -> list:
    """Every dir holding generated .v, for iverilog -y/-I auto-resolution."""
    dirs = []
    for sub in ("verilog-gen", "testbench"):
        base = out_dir / sub
        if base.is_dir():
            dirs += [d for d in base.rglob("*") if d.is_dir()]
            dirs.append(base)
    return dirs


# Verdict markers a generated/standard testbench prints.
_VSIM_FAIL = ("Assertion failed", "TEST FAILED", "FAILED", "Mismatch", "mismatch", "oops")
_VSIM_PASS = ("PASSED", "assertion passed", "TEST PASSED", "checksum OK")


def _simulate_iverilog(source: str, extra_files: dict | None, timeout: int) -> dict:
    """Generate Verilog + testbench and run it under Icarus Verilog (vvp).
    Mirrors the cg-ip-cores run_pipeline vsim invocation
    (`iverilog -g2012 -Y .v -y <dirs> <tb> ; vvp`)."""
    if shutil.which("iverilog") is None:
        return {"ok": False, "simulator": "iverilog",
                "error": "iverilog not found; install Icarus Verilog or use simulator='bytecode'"}
    work = Path(tempfile.mkdtemp(prefix="cg_mcp_vsim_"))
    try:
        rc, out, _, _ = _run("generate", source,
                             flags=["--target", "verilog", "--output", str(work)],
                             extra_files=extra_files)
        diags = _diagnostics(out)
        if rc != 0 or diags:
            return {"ok": False, "simulator": "iverilog", "stage": "generate",
                    "diagnostics": diags, "output": _clean(out)}

        # Pick the canonical clock-gen testbench: a `<Name>.tb.v` with a
        # `module <Name>_tb` + `always #` clock. Prefer the test entity's tb.
        test_ent = _test_entity(source)
        tb_root = work / "testbench"
        chosen = None
        for tb in (sorted(tb_root.rglob("*.tb.v")) if tb_root.is_dir() else []):
            txt = tb.read_text(errors="replace")
            if "always #" not in txt or not re.search(r"module\s+\w+_tb\b", txt):
                continue
            if test_ent and tb.name[:-5] == test_ent:
                chosen = tb
                break
            if chosen is None:
                chosen = tb
        if chosen is None:
            return {"ok": False, "simulator": "iverilog",
                    "error": "no generated testbench (.tb.v): the HDL backend emits one "
                             "only for a network whose name contains 'Test' (capital T, "
                             "e.g. `network TestFoo`). Rename the test network, or use "
                             "simulator='bytecode' (which keys off the `test` property).",
                    "output": _clean(out)}

        vvp = work / "sim.vvp"
        cmd = ["iverilog", "-g2012", "-Y", ".v", "-o", str(vvp)]
        for d in _verilog_lib_dirs(work):
            cmd += ["-y", str(d), "-I", str(d)]
        cmd.append(str(chosen))
        cp = subprocess.run(cmd, env=ENV, capture_output=True, text=True, errors="replace")
        if cp.returncode != 0:
            return {"ok": False, "simulator": "iverilog", "stage": "compile",
                    "top": chosen.name[:-5],
                    "output": _clean((cp.stdout or "") + (cp.stderr or ""))}
        try:
            vp = subprocess.run(["vvp", str(vvp)], cwd=str(work), env=ENV,
                                timeout=timeout, capture_output=True, text=True, errors="replace")
            vout, vto = (vp.stdout or "") + (vp.stderr or ""), False
        except subprocess.TimeoutExpired as e:
            so = e.stdout or ""
            se = e.stderr or ""
            vout = (so if isinstance(so, str) else so.decode("utf-8", "replace")) + \
                   (se if isinstance(se, str) else se.decode("utf-8", "replace"))
            vto = True
        failed = any(m in vout for m in _VSIM_FAIL)
        passed = any(m in vout for m in _VSIM_PASS)
        verdict = ("FAIL" if failed else "PASS" if passed
                   else "ran (no explicit pass/fail markers)")
        return {"ok": (not vto) and (not failed), "simulator": "iverilog",
                "top": chosen.name[:-5], "verdict": verdict, "timed_out": vto,
                "output": _clean(vout)}
    finally:
        shutil.rmtree(work, ignore_errors=True)


def generate(source: str, target: str = "verilog",
             extra_files: dict | None = None,
             output_dir: str | None = None,
             package_dir: str | None = None) -> dict:
    """Emit HDL. Returns the generated files {relative_path: content}.

    If `output_dir` is given the files are WRITTEN THERE AND KEPT (so the
    host can see them on disk, run yosys, commit, etc.); a relative path is
    resolved under $PROJECT_ROOT (the MCP host sets it). If omitted, the old
    behaviour holds — generate into a temp dir, return the contents, delete
    the temp dir."""
    if target not in ("verilog", "vhdl"):
        return {"ok": False, "error": "target must be 'verilog' or 'vhdl'"}
    extra_files = _merge_pkg(source, package_dir, extra_files)
    persist = output_dir is not None
    if persist:
        base = Path(os.environ.get("PROJECT_ROOT", ".")).resolve()
        dest = Path(output_dir)
        dest = (base / dest if not dest.is_absolute() else dest).resolve()
        if not (dest == base or str(dest).startswith(str(base) + os.sep)):
            return {"ok": False, "error": f"output_dir escapes the project root: {output_dir}"}
        dest.mkdir(parents=True, exist_ok=True)
        out_dir = dest
    else:
        out_dir = Path(tempfile.mkdtemp(prefix="cg_mcp_out_"))
    try:
        rc, out, _, _ = _run("generate", source,
                             flags=["--target", target, "--output", str(out_dir)],
                             extra_files=extra_files)
        diags = _diagnostics(out)
        ext = ".v" if target == "verilog" else ".vhd"
        rel = [str(f.relative_to(out_dir)) for f in sorted(out_dir.rglob(f"*{ext}"))]
        # ok must reflect BOTH the exit code AND a clean diagnostics list: a
        # transform error (e.g. divide-by-variable) can still emit some .v files
        # for the unaffected entities, so `bool(rel)` alone wrongly reported
        # ok:True on a design with a fatal diagnostic. The kit runs in an isolated
        # temp dir holding only the caller's source, so every diagnostic pertains
        # to it — none can be an unrelated-file false positive.
        result = {"ok": rc == 0 and bool(rel) and not diags, "diagnostics": diags,
                  "file_count": len(rel)}
        if persist:
            # Files are kept on disk for the host, so return PATHS + the top module —
            # NOT the full HDL bodies. Returning every .v's contents floods the model's
            # context (20k+ tokens on a multi-module design) and triggers overshoot/
            # thrash; the model can `read` any file it actually needs.
            written = [str(out_dir / p) for p in rel]
            top = _synth_top(source)
            result["output_dir"] = str(out_dir)
            result["written"] = written
            result["top_module"] = top
            # A loud, unmissable location note. A non-fatal diagnostic on ONE entity
            # still emits .v for the clean ones (ok is False but the files exist) —
            # without this the model distrusts the result and starts searching the tree.
            note = (f"Generated {len(rel)} Verilog file(s) on disk under {out_dir} "
                    f"(top module {top}.v). Exact paths are in 'written' — read them "
                    f"from there; do NOT search the project tree for them.")
            if diags:
                bad = sorted({d.get("file") for d in diags if d.get("file")})
                note += (f" NOTE: {len(diags)} non-fatal diagnostic(s)"
                         + (f" in {', '.join(bad)}" if bad else "")
                         + " — that entity may not be synthesizable, but the other "
                           "files were still written.")
            result["message"] = note
        else:
            # Temp dir is deleted on return — the contents are the only way the
            # non-persist caller (eval / local client) sees the output.
            result["files"] = {p: (out_dir / p).read_text(errors="replace") for p in rel}
            result["message"] = ("Verilog was generated in a temp dir and NOT kept "
                                  "(no output_dir given) — the contents are in 'files'. "
                                  "To persist .v on disk, call again with output_dir "
                                  "(e.g. 'fpga/build/verilog'); do not search the tree.")
        return _attach_suggestion(result)
    finally:
        if not persist:
            shutil.rmtree(out_dir, ignore_errors=True)


def _synth_top(source: str) -> str:
    """Pick the module to synthesize: the first NON-testbench task/network — a
    `*_test` network or one carrying a `test` property is a simulation harness
    ($display/$stop, not synthesizable), so skip it. Falls back to the first
    entity of any kind."""
    test = _test_entity(source)
    for m in re.finditer(r"^\s*(?:network|task)\s+(\w+)", source, re.M):
        name = m.group(1)
        if name != test and not name.endswith("_test"):
            return name
    return _entity_name(source)


# yosys synthesis flows: a generic mapping or a vendor FPGA family. `synth`
# (generic) checks synthesizability portably; the vendor flows map to that
# family's primitives (LUTs/BRAM/DSP), which is what the model wants when
# targeting a real part.
_SYNTH_FLOWS = {
    "generic": "synth",
    "ice40": "synth_ice40",
    "ecp5": "synth_ecp5",
    "xilinx": "synth_xilinx",
    "gowin": "synth_gowin",
    "intel": "synth_intel",
}


def synth(source: str, top: str | None = None, extra_files: dict | None = None,
          timeout: int = 180, flow: str = "generic",
          package_dir: str | None = None) -> dict:
    """Synthesize the generated Verilog with yosys to confirm it maps to real
    hardware (the strongest correctness signal short of a board). Generates
    Verilog, runs `hierarchy -check -top <top>; <synth flow> -top <top>; stat`,
    and reports {ok, top, flow, cells, stat, problems, output}.

    `top` defaults to the first non-testbench task/network (the synthesizable
    DUT). Pass it explicitly when a file holds several designs. `flow` selects
    the yosys synthesis flow: 'generic' (default, portable check) or a vendor
    FPGA family — 'ice40', 'ecp5', 'xilinx', 'gowin', 'intel' — to map to that
    part's primitives. Override the yosys binary with $YOSYS. Testbench
    `*.tb.v` files are never read (they aren't synthesizable). v1 targets
    self-contained designs — a design split across packages with `` `include``
    may need a manual yosys include path."""
    yosys = os.environ.get("YOSYS", "yosys")
    if shutil.which(yosys) is None:
        return {"ok": False, "error": f"yosys not found (set $YOSYS); install via "
                f"`apt install yosys` or `brew install yosys`"}
    flow = (flow or "generic").lower()
    synth_cmd = _SYNTH_FLOWS.get(flow)
    if synth_cmd is None:
        return {"ok": False, "error": f"unknown flow '{flow}' — choose one of "
                f"{', '.join(_SYNTH_FLOWS)}"}
    requested_top = top or _synth_top(source)
    top = _dut_of(requested_top, source)
    out_dir = Path(tempfile.mkdtemp(prefix="cg_mcp_synth_"))
    try:
        rc, out, _, _ = _run("generate", source,
                             flags=["--target", "verilog", "--output", str(out_dir)],
                             extra_files=_merge_pkg(source, package_dir, extra_files))
        diags = _diagnostics(out)
        if rc != 0 or diags:
            return {"ok": False, "stage": "generate", "diagnostics": diags,
                    "output": _clean(out)}

        # Read every generated module EXCEPT testbenches (*.tb.v) and any file
        # that another file `` `include``s (reading it again would re-define it).
        all_v = [p for p in sorted(out_dir.rglob("*.v")) if not p.name.endswith(".tb.v")]
        included = set()
        for p in all_v:
            for inc in re.findall(r'`include\s+"([^"]+)"', p.read_text(errors="replace")):
                included.add(Path(inc).name)
        read_files = [p for p in all_v if p.name not in included]
        if not read_files:
            return {"ok": False, "stage": "generate", "error": "no synthesizable .v emitted",
                    "diagnostics": diags, "output": _clean(out)}

        # Two stats: a COARSE one after proc/opt (still has word-level $mul/$add/
        # $sub/$dlatch — the arithmetic the design actually uses, and any inferred
        # latch) and the FINAL gate-level one after synth (the cell count). `synth`
        # techmaps arithmetic into gates, so the degenerate-datapath / latch checks
        # MUST read the coarse stat — by the final stat the operators are gone.
        coarse_stat = out_dir / "_coarse_stat.txt"
        final_stat = out_dir / "_final_stat.txt"
        script = "".join(f"read_verilog {p}\n" for p in read_files)
        script += (f"hierarchy -check -top {top}\n"
                   f"proc\n"
                   f"opt\n"
                   f"tee -o {coarse_stat} stat\n"
                   f"{synth_cmd} -top {top}\n"
                   f"tee -o {final_stat} stat\n")
        script_path = out_dir / "synth.ys"
        script_path.write_text(script)
        try:
            yp = subprocess.run([yosys, "-s", str(script_path)],
                                cwd=str(out_dir), env=ENV, timeout=timeout,
                                capture_output=True, text=True, errors="replace")
            yout = (yp.stdout or "") + (yp.stderr or "")
            yrc = yp.returncode
            ytimed = False
        except subprocess.TimeoutExpired as e:
            yout = ((e.stdout or "") if isinstance(e.stdout, str)
                    else (e.stdout or b"").decode("utf-8", "replace"))
            yout += ((e.stderr or "") if isinstance(e.stderr, str)
                     else (e.stderr or b"").decode("utf-8", "replace"))
            yrc, ytimed = 124, True

        problems = [ln.strip() for ln in yout.splitlines()
                    if re.search(r"\b(ERROR|Warning)\b", ln)]

        def _read(p):
            try:
                return p.read_text(errors="replace")
            except OSError:
                return ""

        def _cell_counts(stat_text):
            # stat lines look like `     $mul    2` / `     $_DFF_P_   17`
            counts = {}
            for ln in stat_text.splitlines():
                m = re.match(r"\s+(\$\S+)\s+(\d+)\s*$", ln)
                if m:
                    counts[m.group(1)] = counts.get(m.group(1), 0) + int(m.group(2))
            return counts

        coarse_txt = _read(coarse_stat) or yout
        final_txt = _read(final_stat) or yout
        # Final (gate-level) cell count.
        cells = None
        m = re.search(r"Number of cells:\s*(\d+)", final_txt)
        if m:
            cells = int(m.group(1))
        stat = "\n".join(final_txt.splitlines()[:40]) if final_txt else ""

        # Degenerate-datapath / latch detection from the COARSE (pre-techmap) stat.
        # Datapath cells include comparators ($ge/$lt/…) — a bit-serial divider's
        # datapath is mostly compares + subtracts, so they must count as "real".
        coarse = _cell_counts(coarse_txt)
        ARITH = ("$mul", "$add", "$sub", "$div", "$mod", "$macc", "$alu",
                 "$shl", "$shr", "$sshl", "$sshr", "$mux",
                 "$ge", "$gt", "$le", "$lt", "$eq", "$ne")
        arith = sum(v for k, v in coarse.items() if k in ARITH)
        LATCH = ("$dlatch", "$_DLATCH_", "$dlatchsr", "$_DLATCHSR_")
        latches = sum(v for k, v in coarse.items() if k in LATCH)
        warnings = []
        if top != requested_top:
            warnings.append(
                f"requested top '{requested_top}' is a testbench (its constant driver "
                f"folds to 0 cells) — synthesized the DUT '{top}' instead. Synthesize "
                f"the port-driven task, not its '*_test' network.")
        if arith == 0:
            warnings.append(
                "degenerate datapath: 0 arithmetic/mux operators after opt — the "
                "design likely CONSTANT-FOLDED (its inputs are compile-time "
                "constants). Drive it with `in push` ports from a test network so "
                "the real datapath survives synthesis.")
        if latches > 0:
            warnings.append(
                "inferred latch(es): a data-dependent loop bound or an incomplete "
                "if/assignment produced level-sensitive latches instead of a clocked "
                "FSM. Make every branch assign the variable, or use a constant loop "
                "bound so it unrolls.")

        # One-word classification so a model can't confabulate success:
        #   ERROR   — yosys failed / timed out
        #   SUSPECT — latches inferred (data-dependent loop / missing reset)
        #   FOLDED  — 0 datapath cells (inputs weren't on ports; dead hardware)
        #   REAL    — a genuine datapath
        if yrc != 0 or ytimed:
            verdict = "ERROR"
        elif latches > 0:
            verdict = "SUSPECT"
        elif arith == 0:
            verdict = "FOLDED"
        else:
            verdict = "REAL"

        return {"ok": yrc == 0 and not ytimed, "verdict": verdict, "top": top,
                "flow": flow, "timed_out": ytimed, "cells": cells,
                "arith_ops": arith, "latches": latches, "warnings": warnings,
                "stat": stat, "problems": problems[:40],
                "output": _clean(yout, limit=80)}
    finally:
        shutil.rmtree(out_dir, ignore_errors=True)


def _esc(s) -> str:
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


_VERDICT_COLOR = {"REAL": "#1f7a44", "FOLDED": "#b00020",
                  "SUSPECT": "#b07d00", "ERROR": "#b00020"}


def _schematics(verilog_files: list, names: list, dest: Path, timeout: int) -> dict:
    """Best-effort datapath SVGs via `yosys ... prep -top <k>; show -format svg`.
    Needs yosys + graphviz `dot`; silently returns {} (or skips a kernel) on any
    failure so it can never break the report."""
    yosys = os.environ.get("YOSYS", "yosys")
    if shutil.which(yosys) is None or shutil.which("dot") is None or not verilog_files:
        return {}
    reads = "".join(f"read_verilog {f}\n" for f in verilog_files if f.endswith(".v"))
    out = {}
    for name in names:
        svg = dest / f"schematic_{name}.svg"
        sp = dest / f"_show_{name}.ys"
        sp.write_text(reads + f"prep -top {name}\nshow -format svg -prefix {dest}/schematic_{name}\n")
        try:
            subprocess.run([yosys, "-s", str(sp)], cwd=str(dest), env=ENV,
                           timeout=timeout, capture_output=True, text=True)
            if svg.exists() and svg.stat().st_size > 0:
                out[name] = svg.read_text(errors="replace")
        except Exception:  # noqa: BLE001
            pass
        finally:
            # drop the yosys script + the .dot / partial .svg intermediates; the
            # SVG is embedded inline in the HTML, so nothing here needs keeping.
            for junk in (sp, dest / f"schematic_{name}.dot",
                         dest / f"schematic_{name}.svg.new",
                         dest / f"schematic_{name}.svg"):
                try:
                    junk.unlink()
                except OSError:
                    pass
    return out


def _render_report_html(title: str, sim: dict | None, kernels: list,
                        verilog_files: list, schematics: dict) -> str:
    rows = ""
    for k in kernels:
        col = _VERDICT_COLOR.get(k.get("verdict"), "#555")
        rows += (f"<tr><td class='k'>{_esc(k['kernel'])}</td>"
                 f"<td><span class='badge' style='background:{col}'>{_esc(k.get('verdict','?'))}</span></td>"
                 f"<td class='n'>{k.get('cells','—')}</td>"
                 f"<td class='n'>{k.get('arith_ops','—')}</td>"
                 f"<td class='n'>{k.get('latches','—')}</td></tr>\n")
    sim_html = ""
    if sim is not None:
        ok = sim.get("ok")
        sim_html = (f"<h2>Simulation (correctness)</h2>"
                    f"<p class='{'pass' if ok else 'fail'}'>{'PASS' if ok else 'FAIL'}</p>"
                    f"<pre>{_esc((sim.get('output') or '').strip())}</pre>")
    sch_html = ""
    for name, svg in (schematics or {}).items():
        sch_html += f"<h3>{_esc(name)}</h3><div class='sch'>{svg}</div>\n"
    vlist = "".join(f"<li>{_esc(p)}</li>" for p in verilog_files)
    return f"""<!doctype html><html><head><meta charset="utf-8"><title>{_esc(title)}</title><style>
body{{font-family:-apple-system,Segoe UI,Roboto,sans-serif;margin:2rem;color:#23232f;background:#fafafc}}
h1{{color:#33336e}} h2{{color:#33336e;border-bottom:2px solid #e6e6f0;padding-bottom:.2rem;margin-top:2rem}}
table{{border-collapse:collapse;width:100%;margin:1rem 0}}
th,td{{padding:.5rem .8rem;text-align:left;border-bottom:1px solid #eee}}
th{{background:#33336e;color:#fff}} td.n{{text-align:right;font-variant-numeric:tabular-nums}} td.k{{font-weight:600}}
.badge{{color:#fff;padding:.15rem .6rem;border-radius:1rem;font-size:.85rem;font-weight:600}}
.pass{{color:#1f7a44;font-weight:700}} .fail{{color:#b00020;font-weight:700}}
pre{{background:#f4f4f8;padding:1rem;border-radius:.4rem;overflow:auto;font-size:.85rem}}
.sch svg{{max-width:100%;height:auto;background:#fff;border:1px solid #e6e6f0;border-radius:.4rem;padding:.5rem}}
ul{{columns:2;font-size:.85rem;color:#555}}
</style></head><body>
<h1>{_esc(title)}</h1>
<h2>Synthesis (yosys)</h2>
<table><tr><th>Kernel</th><th>Verdict</th><th>Cells</th><th>Arith ops</th><th>Latches</th></tr>
{rows}</table>
{sim_html}
{('<h2>Datapath schematics</h2>' + sch_html) if sch_html else ''}
<h2>Generated Verilog ({len(verilog_files)} files)</h2><ul>{vlist}</ul>
</body></html>"""


def _resolve_under_root(p: str) -> Path | None:
    """Resolve a relative dir under PROJECT_ROOT; None if it escapes the root."""
    base = Path(os.environ.get("PROJECT_ROOT", ".")).resolve()
    d = Path(p)
    d = (base / d if not d.is_absolute() else d).resolve()
    return d if (d == base or str(d).startswith(str(base) + os.sep)) else None


def accumulate_report(report_dir: str, kind: str, result: dict) -> None:
    """Persist one tool's result as a report fragment under <report_dir>/.report
    and re-render <report_dir>/report.html (no schematics — fast). Called by the
    cg_synth / cg_simulate tools when given report_dir, so the report builds up
    as a BYPRODUCT of the calls already made — no second synth pass. Best-effort:
    never raises into the tool."""
    try:
        rd = _resolve_under_root(report_dir)
        if rd is None:
            return
        frag = rd / ".report"
        frag.mkdir(parents=True, exist_ok=True)
        if kind == "synth":
            key = result.get("top") or "kernel"
            (frag / f"synth_{key}.json").write_text(json.dumps({
                "kernel": key, "verdict": result.get("verdict"),
                "cells": result.get("cells"), "arith_ops": result.get("arith_ops"),
                "latches": result.get("latches"), "ok": result.get("ok")}))
        elif kind == "sim":
            (frag / "sim.json").write_text(json.dumps({
                "ok": result.get("ok"), "output": result.get("output", "")}))
        render_report_from_dir(report_dir, schematics=False)
    except Exception:  # noqa: BLE001
        pass


def render_report_from_dir(report_dir: str, schematics: bool = False) -> dict:
    """(Re)render <report_dir>/report.html from the fragments accumulated by
    cg_synth / cg_simulate + the Verilog already on disk under <report_dir>/
    verilog. Does NO synthesis — just aggregation + rendering (schematics, if
    asked, are diagram-only via `yosys show`, not a synth pass). This is the
    thin renderer behind cg_report."""
    rd = _resolve_under_root(report_dir)
    if rd is None:
        return {"ok": False, "error": f"report_dir escapes the project root: {report_dir}"}
    frag = rd / ".report"
    kernels = []
    if frag.exists():
        for f in sorted(frag.glob("synth_*.json")):
            try:
                kernels.append(json.loads(f.read_text()))
            except (OSError, ValueError):
                pass
    sim = None
    if (frag / "sim.json").exists():
        try:
            sim = json.loads((frag / "sim.json").read_text())
        except (OSError, ValueError):
            sim = None
    vdir = rd / "verilog"
    verilog_files = [str(p) for p in sorted(vdir.rglob("*.v"))] if vdir.exists() else []
    sch = (_schematics(verilog_files, [k.get("kernel") for k in kernels], rd, 180)
           if schematics and verilog_files else {})
    (rd / "report.html").write_text(
        _render_report_html("FPGA synthesis report", sim, kernels, verilog_files, sch))
    real = sum(1 for k in kernels if k.get("verdict") == "REAL")
    sim_ok = (sim is None) or bool(sim.get("ok"))
    return {"ok": bool(kernels) and real == len(kernels) and sim_ok,
            "report": str(rd / "report.html"), "verilog_dir": str(vdir),
            "kernels": kernels, "sim_ok": sim_ok,
            "message": (f"Report at {rd / 'report.html'} — {len(kernels)} kernels, "
                        f"{real} REAL, simulation "
                        f"{'PASS' if sim_ok else ('FAIL' if sim is not None else 'n/a')}. "
                        f"Open it in a browser.")}


def fsm(source: str, task: str | None = None, extra_files: dict | None = None) -> dict:
    """The compiled FSM (states + transitions) of a task — same FSM the
    Verilog backend emits."""
    rc, out, _, _ = _run("fsm", source, flags=(["--task", task] if task else []),
                         extra_files=extra_files)
    return {"ok": rc == 0, "diagnostics": _diagnostics(out), "fsm": _clean(out)}


def graph(source: str, network: str | None = None, extra_files: dict | None = None) -> dict:
    """The compiled graph (instances + ports + connections) of a network."""
    rc, out, _, _ = _run("graph", source, flags=(["--task", network] if network else []),
                         extra_files=extra_files)
    return {"ok": rc == 0, "diagnostics": _diagnostics(out), "graph": _clean(out)}


# --------------------------------------------------------- knowledge docs
# Markdown knowledge packs the model can fetch on demand. Each topic maps to a
# file next to this server; the model reads `context` for the language and
# `riscv` for the worked CPU patterns. Files are read fresh each call so edits
# land without a server restart.
_HERE = Path(__file__).resolve().parent
_DOCS = {
    "context": (_HERE / "cg_context.md",
                "Core C⏚ language knowledge pack: mental model, types, ports, "
                "structs/enums/generics, stdlib, and first-draft gotchas."),
    "riscv":   (_HERE / "cg_riscv.md",
                "The C⏚ RV32I reference CPU: the loadable single-cycle core, its "
                "demo programs, and the reusable patterns for building CPU-shaped "
                "hardware in Cg (barrel shifter, signed/unsigned widening, sub-word "
                "load/store, boot-stream program loading, testbench capture)."),
}


def docs(topic: str = "") -> dict:
    """Serve a named markdown knowledge doc. Empty topic -> the index of
    available topics + descriptions; a topic -> its full markdown content."""
    if not topic:
        return {"ok": True,
                "topics": [{"topic": k, "description": d} for k, (_, d) in _DOCS.items()]}
    entry = _DOCS.get(topic.strip().lower())
    if entry is None:
        return {"ok": False,
                "error": f"unknown topic {topic!r}",
                "topics": list(_DOCS.keys())}
    path, desc = entry
    try:
        return {"ok": True, "topic": topic, "description": desc,
                "content": path.read_text(errors="replace")}
    except OSError as e:
        return {"ok": False, "error": str(e)}


# ------------------------------------------------ validated-code dictionary
# A curated dictionary of validated code with deterministic, scored lazy access
# (NOT RAG): every entry under examples/ compiles + simulates + synthesizes, and
# the metadata lives in manifest.json. `kind` splits general-purpose PRIMITIVES
# (the customer-reusable library) from application EXAMPLES (illustrative
# composition). Serving is specificity-weighted scoring with runners-up so the
# model self-corrects on ambiguous queries. See examples/RECIPES.md + SERVING
# notes. Source: the validated-code dictionary staged 2026-06-09.
_EXAMPLES_DIR = Path(__file__).resolve().parent / "examples"
_MANIFEST = Path(__file__).resolve().parent / "manifest.json"


def _load_meta() -> dict:
    """name -> manifest entry. Read fresh each call so edits to manifest.json
    take effect without a server restart (the dictionary is small)."""
    try:
        import json
        entries = json.loads(_MANIFEST.read_text())["entries"]
        return {e["name"]: e for e in entries}
    except (OSError, ValueError, KeyError):
        return {}


def _norm(s: str) -> str:
    return re.sub(r"[-_/]", " ", s.lower())


def _words(s: str) -> set:
    return set(re.findall(r"[a-z0-9]+", _norm(s)))


# Stopwords filtered ONLY from the weak use_when overlap, so a common word like
# "a" in "general a/b division" can't make a garbage query score a spurious match.
# Tags are curated (no stopwords) so tag matching is unaffected.
_STOP = {"a", "an", "the", "of", "by", "to", "for", "and", "or", "is", "in",
         "on", "with", "not", "per", "via", "its", "as", "at", "no"}


def _score(query: str, name: str, entry: dict) -> int:
    """Specificity-weighted: exact name >> name word-boundary >> full-tag-phrase
    (longer/more-specific tags win, so '1/sqrt' beats a bare 'sqrt') >> partial
    tag overlap >> weak use_when overlap. Partial overlap is counted ONCE over
    the distinct overlapping query words (not summed per tag) so an entry with
    several tags that all share one query word (RSqrt's rsqrt/1-sqrt/one-over-sqrt
    on a bare 'sqrt') can't out-stack an entry whose exact tag IS that word."""
    q = _norm(query)
    qw = _words(query)
    s = 0
    if q == name.lower():
        s += 1000
    if re.search(r"\b" + re.escape(name.lower()) + r"\b", q):
        s += 40
    all_tag_words = set()
    for t in entry.get("tags", []):
        tw = _words(t)
        all_tag_words |= tw
        if tw and tw <= qw:
            s += 6 + len("".join(tw))      # full tag phrase present -> specificity bonus
    # partial overlap (distinct words once); stopwords filtered so a query's "a"
    # can't partial-match a tag like "a/b". Full-tag matches above are unfiltered,
    # so an actual "a/b" query still hits Divide's "a/b" tag.
    s += 3 * len((all_tag_words & qw) - _STOP)
    s += len((qw - _STOP) & (_words(entry.get("use_when", "")) - _STOP))
    return s


def example(pattern: str = "", k: int = 1) -> dict:
    """Lazy, scored access to the validated-code dictionary. No pattern → a
    compact index (name + kind + use_when + tags). A pattern → the single best
    matching source plus its metadata and 1-2 runners-up (so the model can
    self-correct on an ambiguous query). `k>1` also returns the next sources for
    a task that implies composition."""
    meta = _load_meta()
    if not meta:
        return {"ok": False, "error": "manifest.json missing or unreadable"}

    def src(name: str) -> str:
        return (_EXAMPLES_DIR / f"{name}.cg").read_text()

    if not pattern.strip():
        return {"ok": True, "index": [
            {"name": n, "kind": meta[n].get("kind", ""),
             "use_when": meta[n].get("use_when", ""), "tags": meta[n].get("tags", [])}
            for n in meta]}

    scored = sorted(((_score(pattern, n, meta[n]), n) for n in meta), reverse=True)
    top = [(sc, n) for sc, n in scored if sc > 0]
    if not top:
        return {"ok": False, "error": f"no recipe matches '{pattern}'",
                "available": list(meta)}
    best = top[0][1]
    out = {"ok": True, "name": best, "source": src(best), **meta[best],
           "runners_up": [{"name": n, "score": sc} for sc, n in top[1:3]]}
    if k > 1:
        out["also"] = [{"name": n, "source": src(n)} for sc, n in top[1:k]]
    return out


# Failure-driven guidance: map a compiler message to the recipe that shows the
# synthesizable pattern for what was just rejected. div/shift-by-variable ->
# Recip (bit-serial long division); a data-dependent / runtime loop bound ->
# SeqDiv (sequential FSM divider).
# Disambiguate on the OPERATOR token only. The compiler's '/' and '<<' messages
# share the tail "(no hardware divider/variable-shifter is generated)", so
# keying on the words "divider" / "variable-shift" would match BOTH — only the
# `right operand of '<op>'` prefix tells them apart.
_FAIL_HINTS = [
    (re.compile(r"right operand of '/'|right operand of '%'|\bmodulo\b", re.I),
     "Recip",
     "division or modulo by a runtime value isn't synthesizable — seed the Recip "
     "bit-serial divider (literal shifts, constant-bound loop)."),
    (re.compile(r"right operand of '<<'|right operand of '>>'|shift by a (variable|runtime)", re.I),
     "BarrelShift",
     "a shift by a runtime amount isn't directly synthesizable — seed BarrelShift, "
     "a mux tree of literal power-of-two shifts gated by the shift-amount bits."),
    (re.compile(r"\bwhile\b|data-dependent|runtime loop bound|loop bound", re.I),
     "SeqDiv",
     "a data-dependent loop bound can't unroll — seed SeqDiv, a sequential FSM "
     "that reuses one stage over N cycles (a streaming-accumulator shape)."),
]


def suggest_for_error(message: str) -> dict:
    """Map a compiler error/diagnostic to the recipe that demonstrates the
    synthesizable pattern for it. Returns {ok, recipe, hint, source} or
    {ok: False} when nothing matches."""
    if not message:
        return {"ok": False}
    for rx, name, hint in _FAIL_HINTS:
        if rx.search(message):
            try:
                src = (_EXAMPLES_DIR / f"{name}.cg").read_text()
            except OSError:
                src = None
            return {"ok": True, "recipe": name, "hint": hint, "source": src}
    return {"ok": False}


def _attach_suggestion(result: dict) -> dict:
    """If a result carries diagnostics that match a known failure pattern, attach
    a `suggestion` pointing at the recipe with the synthesizable pattern."""
    diags = result.get("diagnostics") or []
    for d in diags:
        s = suggest_for_error(d.get("message", "") if isinstance(d, dict) else str(d))
        if s.get("ok"):
            result["suggestion"] = {"recipe": s["recipe"], "hint": s["hint"]}
            break
    return result


# -------------------------------------------------------------- MCP wrapper
def build_server():
    from mcp.server.fastmcp import FastMCP

    mcp = FastMCP("cg")

    @mcp.tool()
    def cg_check(source: str, extra_files: dict | None = None,
                 package_dir: str | None = None) -> dict:
        """Parse, scope, and type-check C⏚ source without running it. Returns
        {ok, diagnostics:[{file,line,message}], summary}. Call this first on
        any draft; fix every diagnostic before simulating. `extra_files` maps
        filename → content for imported bundles/tasks (e.g. {"Defs.cg": "..."}).
        For a MULTI-FILE project, pass `package_dir` (the folder holding your
        .cg files, e.g. "fpga/src/main/cg", relative to the project root): the
        tool then reads every sibling .cg there, so tasks defined in other files
        of the same package resolve — just like the IDE. A task you only got from
        `cg_example` is text; it must be saved to a file in that dir to resolve."""
        return check(source, extra_files, package_dir)

    @mcp.tool()
    def cg_simulate(source: str, extra_files: dict | None = None,
                    timeout: int = 60, simulator: str = "bytecode",
                    package_dir: str | None = None,
                    report_dir: str | None = "fpga/build") -> dict:
        """Simulate C⏚ source. Returns {ok, simulator, timed_out, diagnostics,
        output}. `output` holds port values and print() lines; a
        `properties { test: {...} }` block self-checks and fails the run on
        mismatch. This is the ground-truth correctness check — iterate until
        ok is true.

        `simulator` picks the backend: 'bytecode' (default — the compiler's
        fast simulator, no HDL toolchain) or 'iverilog' (generate Verilog +
        testbench and run Icarus Verilog, a Verilog-level cross-check; needs a
        `network <Name>_test`). 'verilator' is accepted but reported
        unavailable unless installed.

        For a MULTI-FILE project, pass `package_dir` (the folder with your .cg
        files, e.g. "fpga/src/main/cg") so every sibling task in the same package
        resolves — a `cg_example` you pulled must be saved to a file in that dir,
        not just referenced.

        `report_dir` DEFAULTS to "fpga/build" — this run's PASS/FAIL + output is
        recorded into that dir's accumulating report.html (see cg_report). Pass
        report_dir="" to disable."""
        r = simulate(source, extra_files, timeout, simulator, package_dir)
        if report_dir:
            accumulate_report(report_dir, "sim", r)
        return r

    @mcp.tool()
    def cg_generate_verilog(source: str, target: str = "verilog",
                            extra_files: dict | None = None,
                            output_dir: str | None = None,
                            package_dir: str | None = None) -> dict:
        """Generate synthesizable HDL from C⏚. target is 'verilog' (default)
        or 'vhdl'. Returns {ok, file_count, files:{path:content}}. Use after
        cg_simulate passes, to hand off RTL.

        Pass `output_dir` (e.g. "fpga/build/verilog", relative to the project
        root) to WRITE the files to disk and KEEP them — the result then also
        carries {output_dir, written:[paths]}. Without it the files are only
        returned inline and the temp dir is cleaned. Prefer `output_dir` when
        the host needs the .v on disk (to inspect or run yosys).

        For a MULTI-FILE project, pass `package_dir` (the folder with your .cg
        files) so sibling tasks in the same package resolve during generation."""
        return generate(source, target, extra_files, output_dir, package_dir)

    @mcp.tool()
    def cg_example(pattern: str = "", k: int = 1) -> dict:
        """Get a VERIFIED C⏚ base to seed-and-adapt from (don't synthesize hard
        kernels from scratch — adapt a known-good one). This is a curated
        dictionary of validated code with scored lazy lookup, NOT free-form
        search. No pattern → a compact index (name + kind + use_when + tags). A
        pattern → the single best-matching source plus its metadata and 1-2
        `runners_up` so you can self-correct on an ambiguous query. `k>1` also
        returns the next sources when the task implies composition.

        Matching is specificity-weighted (exact name ≫ name word ≫ full tag
        phrase ≫ partial overlap), so e.g. "1/sqrt" → RSqrt while a bare "sqrt"
        → FixedSqrt. `kind` distinguishes general PRIMITIVES (the reusable
        library: Recip, Divide, SeqDiv, FixedSqrt, RSqrt, SqrDist, DotProduct,
        Fir, Integ, Distance, Counter) from application EXAMPLES (Force,
        GalaxyForce). Every entry passes simulate + generate + iverilog + yosys.
        Workflow: cg_example → edit only the dataflow → cg_check → cg_simulate →
        cg_generate_verilog → cg_synth."""
        return example(pattern, k)

    @mcp.tool()
    def cg_suggest_for_error(message: str) -> dict:
        """Map a compiler error/diagnostic to the recipe that demonstrates the
        synthesizable pattern for what was rejected. Returns {ok, recipe, hint,
        source}. div/shift-by-a-variable → Recip (bit-serial long division);
        a data-dependent/runtime loop bound → SeqDiv (sequential FSM divider).
        cg_check/cg_simulate/cg_generate_verilog already auto-attach this as a
        `suggestion` when a diagnostic matches; call this directly to look one up."""
        return suggest_for_error(message)

    @mcp.tool()
    def cg_synth(source: str, top: str | None = None,
                 extra_files: dict | None = None, timeout: int = 180,
                 flow: str = "generic", package_dir: str | None = None,
                 report_dir: str | None = "fpga/build") -> dict:
        """Synthesize the generated Verilog with yosys — the strongest signal
        that a design maps to real hardware (catches non-synthesizable
        constructs that simulate/iverilog accept). Returns {ok, verdict, top,
        flow, cells, arith_ops, latches, warnings, stat, problems, output}.
        `verdict` is the one-word classification so you can't confabulate
        success: REAL (a genuine datapath), FOLDED (0 datapath cells — inputs
        weren't on ports, dead hardware), SUSPECT (latches inferred — a
        data-dependent loop / missing reset), or ERROR (yosys failed). `cells`
        is the gate count; `problems` lists any ERROR/Warning lines.

        `warnings` flags the two silent failure modes: a DEGENERATE datapath
        (`arith_ops == 0` → the design constant-folded; drive it with input
        ports) and inferred LATCHES (`latches > 0` → a data-dependent loop bound
        or incomplete assignment; expected a clocked FSM). A clean synth has
        `ok: true`, a sensible `cells`, `arith_ops > 0`, and empty `warnings`.

        NOT a correctness oracle: a REAL verdict means real (synthesizable)
        hardware, NOT *correct* hardware — it can't tell a good sequential FSM
        from a buggy one. `cg_simulate` (the asserting test network) is the
        correctness check; run it FIRST, then cg_synth to confirm the hardware
        is real, not folded or latched.

        `top` defaults to the first non-testbench task/network (the DUT); pass
        it when a file holds several designs. `flow` selects the synthesis
        flow: 'generic' (default, portable check) or a vendor FPGA family —
        'ice40', 'ecp5', 'xilinx', 'gowin', 'intel' — to map to that part's
        primitives. Override the yosys binary with the $YOSYS env var. Run
        after cg_simulate passes. A constant-bound `for` synthesizes (it's
        unrolled); a data-dependent loop becomes an FSM (also fine).

        `report_dir` DEFAULTS to "fpga/build", so each synth automatically records
        THIS kernel's verdict + cell counts as a row in <report_dir>/report.html —
        synthesizing the kernels builds the whole report as a byproduct, no
        separate step (see cg_report). Pass report_dir="" to disable."""
        r = synth(source, top, extra_files, timeout, flow, package_dir)
        if report_dir:
            accumulate_report(report_dir, "synth", r)
        return r

    @mcp.tool()
    def cg_report(report_dir: str = "fpga/build", schematics: bool = True) -> dict:
        """Finalize the FPGA report: (re)render <report_dir>/report.html — a
        self-contained HTML with the synthesis table (REAL/FOLDED/SUSPECT verdict
        + cell/arith/latch counts), the simulation PASS/FAIL + output, the
        generated-Verilog file list, and (best-effort) datapath schematic SVGs.

        This does NO synthesis — the rows are built incrementally by passing the
        SAME `report_dir` to cg_synth (per kernel) and cg_simulate as you run
        them; cg_report just aggregates those fragments + the Verilog under
        <report_dir>/verilog and renders. Workflow:
          cg_generate_verilog(output_dir="<report_dir>/verilog", package_dir=...)
          cg_simulate(..., report_dir="<report_dir>")
          cg_synth(..., report_dir="<report_dir>")   # once per kernel
          cg_report(report_dir="<report_dir>")        # finalize + schematics
        Returns {ok, report (the .html path), kernels, sim_ok, message}. Set
        `schematics=False` to skip the SVGs (faster)."""
        return render_report_from_dir(report_dir, schematics)

    @mcp.tool()
    def cg_fsm(source: str, task: str | None = None,
               extra_files: dict | None = None) -> dict:
        """Show a task's compiled state machine (states + transitions). Useful
        to confirm an FSM has the intended number of states."""
        return fsm(source, task, extra_files)

    @mcp.tool()
    def cg_graph(source: str, network: str | None = None,
                 extra_files: dict | None = None) -> dict:
        """Show a network's compiled graph (instances, ports with widths and
        interfaces, connections). Useful to confirm wiring."""
        return graph(source, network, extra_files)

    @mcp.tool()
    def cg_docs(topic: str = "") -> dict:
        """Fetch a markdown knowledge doc. No topic → an index of available
        topics with descriptions; a topic → its full content. Topics:
        'context' (the core C⏚ language pack — load before writing any Cg) and
        'riscv' (the worked RV32I CPU reference: the loadable single-cycle core
        and the reusable patterns for CPU-shaped hardware in Cg — barrel
        shifter, signed/unsigned widening, sub-word load/store, count-prefixed
        boot-stream program loading, and the lossless-capture / address-filtered
        testbench patterns). Read 'riscv' when building or extending a
        processor, instruction decoder, datapath, or stack machine."""
        return docs(topic)

    return mcp


def main():
    build_server().run()


if __name__ == "__main__":
    main()
