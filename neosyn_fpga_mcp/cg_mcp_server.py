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
  cg_capabilities      what this host can actually do (probed, not assumed)
  cg_scaffold          a compiling, self-checking skeleton to fill in
  cg_example           scored lookup into the validated-code dictionary
  cg_suggest_for_error map a compiler error to the fix for it (recipe or edit)
  cg_lint              static checks for code that COMPILES but is wrong
  cg_report            render the FPGA report.html from results already collected
  cg_fsm               a task's compiled state machine (states/transitions)
  cg_graph             a network's compiled graph (instances/ports/edges)
  cg_docs              fetch a markdown knowledge pack on demand

Every roster in this kit -- this list, the README table, the `cg_context.md`
system prompt, and the one the server PUSHES at a model that calls a tool that
does not exist -- is checked against the registry by the test suite. Four
hand-kept lists of the same thing is how a model ends up being told about a tool
that isn't there.

The jar is found via $CG_JAR or the default build path. A dev license is
assumed via $NEOSYN_CG_DEV=1 (set by default here).

The core functions (check/simulate/generate/fsm/graph) have no MCP
dependency, so they can be unit-tested directly:

    import cg_mcp_server as cg
    print(cg.simulate(open("Foo.cg").read()))

Run as a server:  python cg_mcp_server.py   (after `pip install mcp`)
"""
import difflib
import functools
import inspect
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

JAR = Path(os.environ.get(
    "CG_JAR",
    str(Path.home() / "neosyn/neosyn-studio/releng/lsp-server/target/cg-language-server.jar"),
))
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
# Kit-level usage errors (not compiler output). Deliberately carry NO file name:
# the failure mode guarded below is a wrong argument producing a plausible error
# about a plausible file, which a reader then reasons from.
_USAGE_ERR = re.compile(r"^\[cg-kit\]\s+(.*)$", re.M)
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



# `[neosyn] warning: File.cg:12: message` -- a NON-BLOCKING validator finding. These are
# the declarative @Check results the compiler will not fail the build over (idiomatic
# narrowing, `bool == 1`, ...). They were dropped on the floor here, so a design the IDE
# flags came back from cg_check as flatly "ok" -- the call meant to tell a model its code
# is wrong was the one telling it the code was fine.
_WARN = re.compile(r"^\[neosyn\]\s+warning:\s+(?:([\w./-]+\.cg):(\d+):\s*)?(.+)$", re.M)


def _warnings(output: str):
    out, seen = [], set()
    for m in _WARN.finditer(output or ""):
        w = {"file": m.group(1), "line": int(m.group(2)) if m.group(2) else None,
             "message": m.group(3).strip()}
        key = (w["file"], w["line"], w["message"])
        if key not in seen:
            seen.add(key)
            out.append(w)
    return out


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
    for m in _USAGE_ERR.finditer(output):
        msg = m.group(1).strip()
        key = (None, None, msg)
        if msg and key not in seen:
            seen.add(key)
            out.append({"file": None, "line": None, "message": msg})
    return out


def _clean(output: str, limit: int = 120) -> str:
    lines = [ln for ln in output.splitlines() if ln.strip() and not _NOISE.search(ln)]
    if len(lines) > limit:
        lines = lines[:limit] + [f"... ({len(lines) - limit} more lines)"]
    return "\n".join(lines)


def _source_usage_error(source: str) -> str | None:
    """`source` takes C⏚ TEXT. Catch the argument that is a path, or code that
    would read one, BEFORE compiling it.

    Why a guard rather than letting the compiler speak: passing a path compiles
    the path STRING, and the parser reports `Main.cg:1 missing 'package' at
    'fpga'` -- a plausible error naming a plausible file, because `_entity_name`
    falls back to "Main" when it finds no entity. Measured 2026-09-20 in the
    AccelOne trial: a model read exactly that, concluded the compiler wanted a
    `Main.cg` entry point, spent its last ten minutes hunting a file that does
    not exist, and filed all three of its "could not find" answers about the
    phantom. Its real bug went unfixed.

    Only single-line input is judged: real C⏚ needs a `package` line plus an
    entity, so a valid one-liner does not exist.
    """
    s = (source or "").strip()
    if not s:
        return ("source is empty; it takes C⏚ text, not a filename. "
                "For a multi-file project use package_dir.")
    if "\n" in s:
        return None
    looks_like_path = os.path.exists(s) or s.endswith(".cg") or "/" in s
    if looks_like_path or "package" not in s:
        shown = s if len(s) <= 120 else s[:117] + "..."
        # Phrased per case: "looks like not C⏚ source" (the first version) is not English.
        what = ("source looks like a path" if looks_like_path
                else "source does not look like C⏚ source")
        return (f"{what}: {shown!r}. `source` takes C⏚ TEXT, "
                f"not a filename or an expression -- read the file yourself and "
                f"pass its contents. For a multi-file project, pass package_dir "
                f"(the package root) and give source the entry file's text.")
    return None


def _run(subcmd: str, source: str, flags: list | None = None,
         extra_files: dict | None = None, timeout: int = 60):
    """Write `source` (+ any extra_files) into an ISOLATED temp dir — the
    compiler scans sibling .cg files, so it must see only what we give it —
    then run the jar as `<subcmd> <src> <flags...>` (the CLI wants the path
    first). Returns (rc, combined_output, timed_out, src_path)."""
    usage = _source_usage_error(source)
    if usage:
        return 2, f"[cg-kit] {usage}", False, ""
    if not JAR.is_file():
        raise FileNotFoundError(
            f"cg-language-server.jar not found at {JAR}. Set $CG_JAR, or build it: "
            f"cd releng/lsp-server && mvn package -DskipTests")
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
    warns = _warnings(out)
    ok = rc == 0 and not diags
    summary = ("OK — compiles cleanly" if ok else f"{len(diags) or 'unknown'} error(s)")
    if ok and warns:
        # It compiles, but the validator objected. Say so in the summary rather than
        # only in a field: "ok" is the word the model acts on.
        summary = f"compiles, but {len(warns)} validator warning(s) — read `warnings`"
    result = {"ok": ok, "diagnostics": diags, "summary": summary}
    if warns:
        result["warnings"] = warns[:5]
    return _attach_suggestion(_with_lint(result, source))


# ------------------------------------------------- what is available HERE
# The kit runs in two worlds and the right guidance differs between them:
# against the commercial Neosyn distribution the fast bytecode simulator is
# present (and is the headline feature -- never steer a model away from it),
# while the open-source compiler has no `simulate` verb at all. Asserting
# either as a flat fact is wrong in the other environment, so PROBE and phrase
# the answer from what is actually here.
_PROBE_SRC = """package cg.probe;
task Probe {
    properties { test: { inp: [ 1 ], outp: [ 1 ] } }
    in sync u8 inp; out sync u8 outp;
    void loop() { outp.write(inp.read()); }
}
"""
_BYTECODE_PROBE = None


def probe_bytecode(force: bool = False, timeout: int = 60) -> dict:
    """Is the fast bytecode simulator actually runnable HERE?

    Runs one trivial self-checking design and classifies the outcome. Cached
    for the process (pass force=True to re-probe). Returns
    {available, reason, detail} where `reason` is one of:
      ok            -- it ran and self-checked
      jar-missing   -- no compiler jar at $CG_JAR / the default path
      not-in-jar    -- this compiler has no `simulate` verb (open-source build)
      failed        -- present but did not complete; `detail` has the evidence
    """
    global _BYTECODE_PROBE
    if _BYTECODE_PROBE is not None and not force:
        return _BYTECODE_PROBE
    if not JAR.is_file():
        res = {"available": False, "reason": "jar-missing",
               "detail": f"no compiler jar at {JAR} (set $CG_JAR)"}
    else:
        try:
            rc, out, to, _ = _run("simulate", _PROBE_SRC, timeout=timeout)
        except Exception as e:                                  # pragma: no cover
            rc, out, to = 1, f"probe failed to run: {e}", False
        low = out.lower()
        if "unknown command" in low:
            res = {"available": False, "reason": "not-in-jar",
                   "detail": "this compiler has no `simulate` verb -- the fast "
                             "bytecode simulator is part of the commercial "
                             "Neosyn distribution, not the open-source build."}
        elif rc == 0 and not to and "completed successfully" in low:
            res = {"available": True, "reason": "ok", "detail": ""}
        else:
            res = {"available": False, "reason": "failed",
                   "detail": _clean(out, limit=8) or f"exit {rc}, timed_out={to}"}
    _BYTECODE_PROBE = res
    return res


def capabilities() -> dict:
    """What this host can actually do, probed rather than assumed -- so a model
    picks a backend from fact instead of a claim that may not hold here."""
    bc = probe_bytecode()
    tools = {name: shutil.which(name) for name in
             ("iverilog", "vvp", "verilator", "yosys", "ghdl")}
    sims = ["bytecode"] if bc["available"] else []
    if tools["iverilog"] and tools["vvp"]:
        sims.append("iverilog")
    if bc["available"]:
        advice = ("Use the default simulator='bytecode': it is the fast "
                  "cycle-accurate simulator and needs no HDL toolchain. Reach "
                  "for 'iverilog' only as a slower Verilog-level cross-check.")
    elif "iverilog" in sims:
        advice = ("The fast bytecode simulator is not available here "
                  f"({bc['reason']}), so pass simulator='iverilog'. It emits a "
                  "testbench only for a network whose NAME contains 'Test' "
                  "(capital T) on every compiler released so far -- a `test` "
                  "property and the `<Design>_test` convention are both refused "
                  "there, and both work after 3.2.0 -- and needs a driver that "
                  "terminates.")
    else:
        advice = ("No simulator is available here: the bytecode simulator is "
                  f"absent ({bc['reason']}) and iverilog/vvp are not installed. "
                  "cg_check and cg_generate_verilog still work.")
    # `tools` is the BINARIES found on this host; `available_tools` is the roster
    # of tools this SERVER exposes. Two different questions that both live under
    # "what can I do here", so they belong in one answer -- but they are not the
    # same list and are deliberately not merged. The roster is generated from the
    # registry (see `tool_roster`), never restated here.
    return {"ok": True, "jar": str(JAR), "jar_present": JAR.is_file(),
            "bytecode_simulator": bc, "simulators": sims,
            "tools": {k: bool(v) for k, v in tools.items()},
            "available_tools": _roster_lines(),
            "advice": advice}



_MISMATCH_RE = re.compile(
    r'^port\s+(\S+)\s+\[vector\s+(\d+)\]\s+expected\s+(\S+)\s*->\s*(\S+)', re.M)
_MISSING_VALS_RE = re.compile(r'missing test values for port "([^"]+)"')
_CHECKS_RE = re.compile(r"^Checks executed:\s*(\d+)", re.M)


def _checks_executed(out: str):
    """How many asserts the run EVALUATED, or None if this compiler did not report it.

    None is not zero. An older jar says nothing at all, which is unknown; treating
    that as "checked nothing" would call every run on it hollow."""
    m = _CHECKS_RE.search(out or "")
    return int(m.group(1)) if m else None


def _has_test_block(source: str) -> bool:
    """True if the source declares a `test:` fixture at all."""
    return re.search(r"\btest\s*:\s*\{", source or "") is not None


def _sim_findings(out: str) -> tuple:
    """Turn simulator OUTPUT into (diagnostics, unchecked_ports).

    A value mismatch is the most actionable thing the simulator ever produces
    and it was being discarded: it arrives as a plain line followed by a Java
    AssertionError stack trace, so `diagnostics` came back EMPTY and the caller
    saw `ok:False` with nothing to act on. Promote it."""
    diags = []
    for m in _MISMATCH_RE.finditer(out or ""):
        port, idx, exp, got = m.groups()
        # CAREFUL: the simulator prints this line for EVERY vector, passing or
        # failing -- identical format, only the values differ (`expected 1 ->
        # 0x1` is a MATCH; 1 == 0x1). Comparing the two is the whole check; a
        # bare regex match reports every successful trace line as a failure.
        # Bases differ across the arrow, so normalise before comparing.
        def _num(v):
            # bool ports print `expected 0 -> false` / `expected 1 -> true`:
            # the two sides use DIFFERENT notations for the same value, so a
            # string compare calls every boolean vector a failure.
            t = (v or "").strip().lower()
            if t in ("false", "0b0"):
                return 0
            if t in ("true", "0b1"):
                return 1
            try:
                return int(t, 0)
            except (TypeError, ValueError):
                return None
        e, g = _num(exp), _num(got)
        # SIGNEDNESS: the actual value is printed as raw two's complement
        # (`expected -20 -> 0xffffffffffffffec`), so a negative expectation
        # never equals its own encoding numerically. Reinterpret the actual as
        # signed at the width the literal itself declares (4 bits per hex
        # digit) before deciding anything is wrong.
        if (e is not None and g is not None and e != g and e < 0 <= g):
            hx = re.fullmatch(r"0[xX]([0-9a-fA-F]+)", (got or "").strip())
            if hx:
                width = 4 * len(hx.group(1))
                if g >= (1 << (width - 1)):
                    g -= (1 << width)
        same = (e == g) if (e is not None and g is not None) else (exp == got)
        if same:
            continue
        diags.append({"file": None, "line": None,
                      "message": f"test failure: port {port} vector {idx} "
                                 f"expected {exp} but got {got}"})
    unchecked = _MISSING_VALS_RE.findall(out or "")
    return diags, unchecked


def simulate(source: str, extra_files: dict | None = None, timeout: int = 60,
             simulator: str = "bytecode", package_dir: str | None = None) -> dict:
    """Run a simulator on the design. `simulator` selects the backend:

    - 'bytecode' (default) — the fast cycle-accurate simulator. No HDL
      toolchain needed; a `properties { test: {...} }` block self-checks. It
      ships with the commercial Neosyn distribution and is the right default
      WHERE IT EXISTS; the open-source compiler has no `simulate` verb, and
      there this call returns `available: False` with a pointer rather than a
      design error. `capabilities()` reports which of the two you have — this
      docstring deliberately does not assert one, because the kit runs in both.
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
        if "unknown command" in out.lower():
            # This compiler has no `simulate` verb (the open-source build).
            # Say so, and name the backend that DOES work here -- a bare
            # ok:False would read as "your design is wrong".
            return {"ok": False, "simulator": "bytecode", "available": False,
                    "reason": "not-in-jar",
                    "error": "The fast bytecode simulator is not in this "
                             "compiler -- it is part of the commercial Neosyn "
                             "distribution, and this jar is the open-source "
                             "build. Your design was not the problem. Use "
                             "simulator='iverilog' for a Verilog-level check "
                             "(it needs a network whose NAME contains 'Test' on every "
                             "released compiler; a `test` property alone is not "
                             "enough there), "
                             "or see cg_capabilities for what this host has."}
        diags = _diagnostics(out)
        sim_diags, unchecked = _sim_findings(out)
        diags = diags + [d for d in sim_diags if d not in diags]
        # A run that CHECKED NOTHING is not a pass. `ran` and `verified` are
        # deliberately separate ideas: a hollow design DOES run, it just checks
        # nothing, and collapsing the two would tell a model its code failed to
        # execute when it executed fine.
        #
        # The compiler now reports the count itself and FAILS a zero-check run
        # (S170 T6), so "completed successfully" is absent for a hollow design.
        # That verdict is right, but it must not be misread as "did not run" --
        # hence `checks is not None` also counts as having run. When the count
        # is absent (an older jar) fall back to the original heuristics, which
        # is why this cannot simply be replaced by the compiler's answer.
        checks = _checks_executed(out)
        ran = (not to and not diags
               and ("completed successfully" in out.lower() or checks is not None))
        checked_nothing = ((checks == 0) if checks is not None
                           else (bool(unchecked) or not _has_test_block(source)))
        verified = ran and not checked_nothing
        result = {"ok": ran and verified, "ran": ran, "verified": verified,
                  "simulator": "bytecode", "timed_out": to,
                  "diagnostics": diags, "output": _clean(out)}
        sim_warns = _warnings(out)
        if sim_warns:
            result["warnings"] = sim_warns[:5]
        if ran and not verified:
            why = (f"the fixture declares no expected values for "
                   f"{', '.join(sorted(set(unchecked)))}" if unchecked
                   else "this design has no `properties { test: {...} }` block")
            result["warning"] = (
                "NOT VERIFIED: the simulation ran without error, but " + why +
                " -- so it would pass unchanged even if the design did nothing. "
                "Add expected values for every output port before treating this "
                "as evidence of correctness.")
        return _attach_suggestion(_with_lint(result, source))

    if backend in ("iverilog", "icarus", "verilog", "vvp"):
        return _simulate_iverilog(source, extra_files, timeout)
    if backend == "verilator":
        why = ("verilator is not installed on this host"
               if shutil.which("verilator") is None
               else "the verilator backend isn't wired in this kit yet")
        return {"ok": False, "simulator": "verilator",
                "error": f"{why}; use simulator='iverilog' (Verilog-level) or "
                         f"'bytecode' (default)"}
    # An invented backend name is the same drift as an invented TOOL name, so it
    # gets the same answer: the real list, pushed. cg_capabilities is the tool that
    # answers "which of these exist here", which is what the caller actually wanted.
    return _with_roster({"ok": False, "error": f"unknown simulator '{simulator}' — choose "
                         f"'bytecode' or 'iverilog'"},
                        "cg_capabilities reports which simulators this host actually has.")


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
                    "error": "no generated testbench (.tb.v). On compilers up to 3.2.0 and on "
                             "the open-source build, the HDL backend emits one only for a "
                             "network whose name contains 'Test' (capital T, e.g. "
                             "`network TestFoo`) -- a `test` property is NOT enough, and the "
                             "documented `<Design>_test` convention does NOT work either. "
                             "Rename the test network, or use simulator='bytecode' (which "
                             "keys off the `test` property). Fixed in the compiler after "
                             "3.2.0: there a `test` property or a `_test` name both work.",
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
        return _with_roster({"ok": False,
                             "error": "target must be 'verilog' or 'vhdl'"})
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
        return _with_roster({"ok": False, "error": f"unknown flow '{flow}' — choose one "
                             f"of {', '.join(_SYNTH_FLOWS)}"})
    requested_top = top or _synth_top(source)
    top = _dut_of(requested_top, source)
    out_dir = Path(tempfile.mkdtemp(prefix="cg_mcp_synth_"))
    try:
        rc, out, _, _ = _run("generate", source,
                             flags=["--target", "verilog", "--output", str(out_dir)],
                             extra_files=_merge_pkg(source, package_dir, extra_files))
        diags = _diagnostics(out)
        if rc != 0 or diags:
            # The design never compiled, so yosys was never reached. Say so
            # explicitly: without it the model reads a synthesis-tool failure
            # and starts "fixing" synthesizability in a file that doesn't parse.
            return _attach_suggestion({
                "ok": False, "stage": "generate", "diagnostics": diags,
                "message": "cg_synth compiles first and the COMPILE failed — "
                           "yosys never ran. These are compile errors, not "
                           "synthesis errors: fix them with cg_check until it "
                           "reports ok, then re-run cg_synth.",
                "output": _clean(out)})

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
    "handshakes": (_HERE / "cg_handshakes.md",
                "Port protocols (bare / push / stream / confirm), back-pressure, "
                "connecting instances with .reads(), and THE pacing gotcha: feeding a "
                "registered built-in (Multiply/Divide) too fast drops data — use the "
                "feeder/sink pattern or idle() spacing. Read before wiring a network."),
    "arithmetic": (_HERE / "cg_arithmetic.md",
                "What *, /, %, <<, >> synthesize to and when they need a built-in: "
                "full-width multiply + std.math.Multiply, constant division via "
                "reciprocal multiply, std.math.Divide for runtime denominators, barrel "
                "shift for runtime shifts, and what's free vs. the paid Divider core."),
    "fsm":     (_HERE / "cg_fsm.md",
                "Writing a control FSM (sequence/pattern detector, protocol "
                "controller, serial parser): enum state register + next-state logic, "
                "Moore vs Mealy outputs, publishing the state as an integer code, and "
                "the two timing rules that break first drafts — publish the CURRENT "
                "state before transitioning, and inline-init state instead of setup() "
                "(a setup() body adds a reset state that offsets the stream). Seeds "
                "the verified Seq1011 example."),
}


def _doc_sections(text: str) -> list:
    """Split a knowledge doc on its `## ` headings, in order. The text before the
    first one is the "intro". Each section keeps its own `###` subsections."""
    parts = re.split(r"(?m)^(?=## )", text)
    out = []
    for part in parts:
        if not part.strip():
            continue
        first = part.splitlines()[0]
        name = first[3:].strip() if first.startswith("## ") else "intro"
        out.append((name, part))
    return out


def docs(topic: str = "", section: str = "") -> dict:
    """Serve a named markdown knowledge doc. Empty topic -> the index of topics;
    a topic -> its full content; a topic AND a section -> just that `## ` section.

    F88. `context` is ~24,000 characters -- about a quarter of a small model's
    working budget -- and could only be fetched whole. Measured in the AccelOne
    trial: after each compaction the model lost it and fetched ALL of it again,
    three times in one 49-minute turn (13 compactions). Sections run 500-3,900
    characters, so re-reading the one part it needs costs 6-50x less.

    The whole-document default is kept on purpose: the tool's own description
    tells a model to load `context` before writing any C\u23da, and a first read
    of the whole language pack is right. What was wasted was the RE-reads -- so
    every full fetch now also returns `sections`, and a model that has read it
    once knows it can come back for one part."""
    if not topic:
        index = []
        for k, (path, d) in _DOCS.items():
            item = {"topic": k, "description": d}
            try:
                item["sections"] = [n for n, _ in _doc_sections(path.read_text(errors="replace"))]
            except OSError:
                pass
            index.append(item)
        return {"ok": True, "topics": index}
    entry = _DOCS.get(topic.strip().lower())
    if entry is None:
        return _with_roster({"ok": False,
                             "error": f"unknown topic {topic!r}",
                             "topics": list(_DOCS.keys())})
    path, desc = entry
    try:
        text = path.read_text(errors="replace")
    except OSError as e:
        return {"ok": False, "error": str(e)}
    sections = _doc_sections(text)
    names = [n for n, _ in sections]
    if not section:
        return {"ok": True, "topic": topic, "description": desc, "content": text,
                "sections": names,
                "note": "re-read ONE part later with cg_docs(topic, section=<name>) "
                        "instead of fetching this whole document again"}
    want = section.strip().lower()
    exact = [(n, b) for n, b in sections if n.lower() == want]
    partial = [(n, b) for n, b in sections if want in n.lower()]
    hits = exact or partial
    if len(hits) != 1:
        why = "no section matches" if not hits else "more than one section matches"
        return {"ok": False, "topic": topic,
                "error": f"{why} {section!r} in {topic!r}; pick one of the names in "
                         f"`sections`.",
                "sections": names}
    name, body = hits[0]
    return {"ok": True, "topic": topic, "section": name, "content": body,
            "sections": names}


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
    # `score` is the WINNER's score, exposed so a caller can gate on confidence.
    # It was previously visible only for the runners-up, which meant nobody could
    # tell a strong match from noise. Calibrated 2026-08-20 over this corpus:
    # "4-bit counter that wraps" -> 57, "uart receiver" -> 31, while an unrelated
    # query ("write me a haiku") still reaches 4 on tag overlap. Anything at or
    # below ~5 is indistinguishable from noise.
    out = {"ok": True, "name": best, "score": top[0][0], "source": src(best),
           **meta[best],
           "runners_up": [{"name": n, "score": sc} for sc, n in top[1:3]]}
    if k > 1:
        out["also"] = [{"name": n, "source": src(n)} for sc, n in top[1:k]]
    return out


# Failure-driven guidance: map a compiler message to the fix for it. Two
# families, and the ORDER MATTERS — first match wins.
#
#   1. AUTHORING / WIRING — "your file doesn't parse" or "your project isn't
#      wired up". These come FIRST: a design that never parsed cannot have a
#      synthesizability problem, and the family-2 patterns below are broad
#      enough (`\bwhile\b`) to mis-claim a parse error. Most carry no recipe —
#      the fix is a one-line edit, not a design pattern — so `recipe` is None
#      and the hint IS the payload.
#   2. SYNTHESIZABILITY — "this construct has no hardware". These name the
#      recipe that demonstrates the synthesizable shape.
#
# Every family-1 pattern below was reproduced against the real compiler
# (S166); the message text is copied from its output, not paraphrased.
# Disambiguate on the OPERATOR token only in family 2. The compiler's '/' and
# '<<' messages share the tail "(no hardware divider/variable-shifter is
# generated)", so keying on the words "divider" / "variable-shift" would match
# BOTH — only the `right operand of '<op>'` prefix tells them apart.
_FAIL_HINTS = [
    # ---------------------------------------------------------- 1. authoring
    # The #1 error signature in the 2026-08-20 model probe: 6 occurrences, and
    # gpt-oss never once recovered from it -- it retried the same edit four times.
    # ROOT CAUSE, reproduced: `properties` must be the FIRST element of an entity
    # body. After the ports -- the natural place to write it -- it is a parse
    # error. Everything else is position-flexible (a `sync {}` block AFTER
    # `void loop()` compiles fine), so this is the one construct whose position is
    # fixed, and the message says nothing about order, which is precisely why the
    # loop never broke.
    (re.compile(r"mismatched input 'properties'", re.I),
     None,
     "the `properties { test: {...} }` block is in a position this compiler does "
     "not accept. On releases up to 2.9.7 it must be the FIRST thing in the entity "
     "body — before the ports, the state and the functions, immediately after "
     "`task X {` (imports may precede it). Move the WHOLE block up; nothing inside "
     "it needs to change. This is a POSITION rule, not a syntax error in the block "
     "itself, so re-writing its contents will not help. (Newer compilers accept it "
     "anywhere among the members, at most once — if you see this there, you are on "
     "an older release.)",
     True,
     "package com.example;\n"
     "task Gain {\n"
     "    properties {                    // FIRST, right after `task X {`\n"
     "        test: { x: [1, 2, 3], y: [2, 4, 6] }\n"
     "    }\n"
     "    sync { in u8 x; out u8 y; }     // ports come AFTER\n"
     "    void loop() { y.write((u8)(x.read() * 2)); }\n"
     "}\n"),

    # Reproduced both halves: `u8 s; s = 5;` at entity scope fails, `u8 s = 5;`
    # compiles. A bare assignment is a STATEMENT, and statements only live in
    # functions.
    (re.compile(r"no viable alternative at input '='", re.I),
     None,
     "a bare assignment at entity scope is not allowed — statements live inside "
     "functions. Either initialise the state inline where it is declared "
     "(`u8 s = 5;`), which is the idiom for a reset value, or move the assignment "
     "into `setup()` (runs once at reset) or `loop()` (runs every cycle).",
     True),

    # FIRST-DIAGNOSTIC ONLY (the 4th field). A misplaced declaration halts the parse
    # immediately, so it is always error #1. Once the parser has been derailed by
    # something else, `missing EOF` reappears at arbitrary tokens deep in the cascade --
    # and there this advice is actively wrong, because the declaration is usually already
    # inside an entity. Observed on real model-written code: a `switch` on line 32
    # produced `missing EOF at 'xCount'` on line 41.
    #
    # TWO COMPILERS, TWO RULES, so the hint states both rather than asserting one:
    # a recent Neosyn compiler ACCEPTS file-scope declarations (before the first entity)
    # and says so in its own message; the open-source compiler does not and still emits
    # the bare "missing EOF at 'const'".
    (re.compile(r"missing EOF at '(\w+)'|has no top-level declarations|"
                r"file-scope declaration must come BEFORE", re.I),
     None,
     "a declaration is in the wrong place. On a recent Neosyn compiler `const`, "
     "`typedef`, `struct` and `enum` MAY be written at file scope, but only BEFORE the "
     "first `task`/`network`/`bundle` — move it up, just after the imports, and it is "
     "then in scope unqualified for the whole file. On the open-source compiler file "
     "scope is not supported at all (it says only `missing EOF at '<token>'`): put the "
     "declaration inside the task that uses it, or in a `bundle`, whose members are "
     "referenced as `BundleName.member`. If the named token is already inside an entity, "
     "this is not the real error — the parser was derailed earlier, so fix the FIRST "
     "diagnostic and re-check.",
     True),
    # Matches the message the compiler emits SINCE S170 (7316b31) and the raw
    # parser text older jars still produce, so this fires against either.
    #
    # The entry is kept rather than deleted even though the compiler's own
    # message is now good: the hint table is scanned in order and this is what
    # makes an array port outrank a LATER fault. Drop it and a `switch` further
    # down the same file wins instead, which is the misleading-hint case
    # test_cascade_does_not_produce_a_misleading_hint exists to catch.
    #
    # The wording no longer claims "only ports may not" -- measured S170: a
    # struct FIELD array and a `typedef` array hit exactly the same fault.
    #
    # TWO COMPILERS, TWO RULES, as with the file-scope entry above: a Neosyn
    # compiler from 2026-09-09 on ACCEPTS array PORTS (they fan out to one port
    # per element, `W[4]` -> `W_0`..`W_3`), so a model that reached for one was
    # right and must not be talked out of it. Older jars and the open-source
    # compiler still reject them, which is why the raw parser text stays in the
    # pattern. A struct FIELD and a `typedef` are rejected by BOTH.
    (re.compile(r"array dimensions are not allowed in this declaration|"
                r"mismatched input '\[' expecting ';'", re.I),
     None,
     "array dimensions are not accepted here. On a recent Neosyn compiler a PORT "
     "MAY carry them -- `in u8 W[4]` fans out to one port per element, read and "
     "written through a CONSTANT index (`W[0].read()`, `y[1].write(v)`), and test "
     "vectors name the elements (`W_0: [...]`). If the port form was rejected, the "
     "compiler predates that or is the open-source one: declare the ports "
     "individually (`y0`, `y1`, ...) or send the elements one per cycle through a "
     "SINGLE port. A struct FIELD and a `typedef` may never carry dimensions on "
     "either compiler -- dimensions are accepted on a state variable, a local, or "
     "a `const` (`u8 buf[4];` inside the task body is fine)."),
    # The SUCCESSOR fault to the one above. Once a compiler accepts array ports,
    # `y[4]` parses and the next mistake is using the port as a whole -- the
    # compiler then says so precisely. Added 2026-09-20: the message existed with
    # no entry, so a model got a correct compiler diagnostic and NO route out,
    # which is the gap that makes this dictionary narrow rather than empty.
    (re.compile(r"Array port '?\w+'? must be indexed|"
                r"must be indexed to select one element", re.I),
     None,
     "an array port is a FAN-OUT, not a vector: `out u8 y[4]` is four ports, so "
     "every read and write names one element through a CONSTANT index -- "
     "`y[0].write(v)`, not `y.write(v)`, and `W[2].read()`, not `W.read()`. The "
     "index must be a literal or a `const`, never a runtime variable; to select "
     "at runtime, write the branches out (`if (i == 0) y[0].write(v); else ...`). "
     "Test vectors name the elements individually (`y_0: [...]`, `y_1: [...]`)."),
    # F103(a). A braceless loop or branch body: `for (...) v.write(x);`. C⏚ requires
    # braces around EVERY body, and the parser says so only as "missing '{' at '<the
    # next token>'" -- which names the wrong thing. Measured in the AccelOne trial: a
    # model hit it four times in 16 minutes, asked for a suggestion and got nothing
    # (F103(b)), and abandoned a genuine overflow test one brace pair from passing.
    # FIRST diagnostic only: later down a file the same text is usually cascade.
    (re.compile(r"missing '\{' at", re.I),
     None,
     "C\u23da requires BRACES around every loop and branch body, even a single "
     "statement. `for (i = 0; i < N; i++) v.write(x);` is a parse error -- write "
     "`for (i = 0; i < N; i++) { v.write(x); }`. The same holds for `if`, `else` and "
     "`while`. The token the message names is the first statement of the body, not "
     "the fault: the fault is the missing `{` just before it.",
     True,
     'package com.example;\ntask SumBraced {\n    properties { test: { y: [6] } }\n    out sync u8 y;\n    void loop() {\n        u8 acc = 0;\n        for (u3 i = 1; i < 4; i++) {   // braces REQUIRED, even around one statement\n            acc = (u8) (acc + i);\n        }\n        y.write(acc);\n    }\n}\n'),
    (re.compile(r"missing '\}' at 'case'|no viable alternative at input 'case'|"
                r"\bswitch cannot be resolved", re.I),
     None,
     "C⏚ has no `switch`/`case` statement -- reaching for one is a C habit, and "
     "it derails the parser for the rest of the file (every later error is "
     "usually cascade). Write the state machine as an if / else-if chain over "
     "an enum-typed state field: `if (st == IDLE) { ... } else if (st == RUN) "
     "{ ... }`. cg_scaffold(kind=\"fsm\") returns exactly that shape, already "
     "compiling and self-checking."),
    (re.compile(r"no viable alternative at character '(.)'", re.I),
     None,
     "the quoted character is not valid C⏚ at that point. Two common causes, "
     "and the message quotes the character so you can tell them apart: (a) a "
     "NON-ASCII character in code — a smart quote, an em-dash, a Greek/IPA "
     "letter in an identifier; rewrite the line in plain ASCII. (Non-ASCII "
     "inside a // comment is fine and does NOT cause this.) (b) a VERILOG-ISM "
     "or other symbol C⏚ has no operator for — `@` (as in `always @(posedge "
     "clk)`), `#`, `$`, backtick. C⏚ has no explicit clock edges: a task's "
     "`void loop()` IS the clocked process, so delete the construct rather "
     "than translating it."),
    (re.compile(r"mismatched input '<' expecting ';'", re.I),
     None,
     "a width was written with angle brackets on the short type name. C⏚ "
     "spells a fixed width WITHOUT brackets (`u8`, `u16`, `i32`) and a "
     "PARAMETRIC width with them on the long name (`uint<W>`, `int<W>`). "
     "`u<8>` is neither — write `u8`, or `uint<W>` if W is a parameter."),
    (re.compile(r"Couldn't resolve reference to Instantiable '([\w.]+)'", re.I),
     None,
     "the entity being instantiated is not visible to the compiler. A "
     "same-package sibling is a SEPARATE FILE on disk that this call never "
     "sent — pass `package_dir` (the directory holding the sibling .cg files) "
     "so they are compiled together, or inline the entity in `source`. Check "
     "the spelling and that the sibling declares the same `package`."),
    (re.compile(r"Cannot generate HDL for .*: \d+ compile error|"
                r"No IR files generated", re.I),
     None,
     "HDL generation never ran: the design failed to COMPILE, so there was no "
     "IR to translate (a parse error silently drops the design body). These are "
     "compile errors, not synthesis errors — fix them with cg_check until it "
     "reports ok, THEN re-run cg_generate_verilog / cg_synth."),
    (re.compile(r"NoClassDefFoundError|ClassNotFoundException|"
                r"UnsupportedClassVersionError", re.I),
     None,
     "this is a TOOLCHAIN fault, not a fault in your C⏚: the compiler jar "
     "failed to load a class. Your source may be perfectly valid — do not "
     "rewrite it in response to this. Check that $CG_JAR points at a complete "
     "cg-language-server.jar, that it was built against the running JDK "
     "(21+), and rebuild it if it is stale."),
    # Last in family 1: only reached when nothing more specific matched.
    (re.compile(r"\bcannot be resolved\b|"
                r"Couldn't resolve reference to NamedType", re.I),
     None,
     "that name is not visible where it is used. C⏚ has no globals: a `const` "
     "declared in a `bundle` is NOT in scope elsewhere -- qualify it "
     "(`MyParams.N`) or declare it in the entity that uses it. An entity from "
     "another file needs `package_dir`. Also check for a typo, and that the "
     "declaration really precedes the use. If the file ALSO has parse errors "
     "above this one, fix those first: a derailed parser reports names it never "
     "got to declare."),
    # --------------------------------------------------- 2. synthesizability
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
    (re.compile(r"single combinational multiplier|std\.math\.Multiply|wider than one DSP", re.I),
     "MulStream",
     "a wide runtime multiply is a single combinational product spanning more than "
     "one DSP tile; if it misses timing, seed MulStream — the registered "
     "std.math.Multiply built-in fed through a stream handshake. For a multiply-"
     "accumulate over a stream, seed StreamDot instead."),
]


def suggest_for_error(message: str, is_first: bool = True) -> dict:
    """Map a compiler error/diagnostic to its fix. Returns
    {ok, recipe, hint, source} or {ok: False} when nothing matches.

    `recipe`/`source` are None for the authoring/wiring patterns, whose fix is
    a one-line edit rather than a design pattern — there `hint` is the whole
    answer. Callers must not assume a recipe is present.

    `is_first` says whether this message is the FIRST diagnostic of the run.
    Some rules only hold there, because a parse error cascades: the same text
    appearing later is a symptom of an earlier fault, not its own bug. It
    defaults to True so a direct lookup of a single message behaves as asked."""
    if not message:
        return {"ok": False, "matched": False,
                "error": "no message given -- pass the text of the compiler diagnostic "
                         "you want explained."}
    for entry in _FAIL_HINTS:
        rx, name, hint = entry[:3]
        first_only = entry[3] if len(entry) > 3 else False
        if first_only and not is_first:
            continue
        if rx.search(message):
            src = None
            if name:
                try:
                    src = (_EXAMPLES_DIR / f"{name}.cg").read_text()
                except OSError:
                    src = None
            # An authoring rule may carry its own minimal SHAPE example (5th
            # field): there is no recipe to point at, but seeing the correct
            # shape beats being told about it. Kept tiny -- it rides in the
            # model's context on every matching failure.
            elif len(entry) > 4 and entry[4]:
                src = entry[4]
            return {"ok": True, "recipe": name, "hint": hint, "source": src}
    return _no_suggestion(message)


# Parse errors share one piece of advice that is true whatever the token: the
# parser met something it did not expect, and every LATER diagnostic is usually a
# cascade from the first. Recognised by shape, not by a list of tokens.
_PARSE_ERR = re.compile(r"mismatched input|missing '|missing EOF|no viable alternative"
                        r"|extraneous input|expecting", re.I)


def _no_suggestion(message: str) -> dict:
    """F103(b). An unmatched lookup used to answer a bare {"ok": false}: no hint,
    no "nothing matched", nothing to try. Measured in the AccelOne trial, a model hit
    the same parse error four times, asked this tool, got that, and abandoned a
    GENUINE overflow test that was one brace pair from passing. An orchestrator can
    render the bare reply as "Tool failed (no detail returned)" -- honest, but it
    still tells the model nothing to do next. So say what we know and where to look.

    The sentence is in `error` on purpose: that is the one field every orchestrator
    version shows the model, including ones that drop the rest of a failed reply.
    `ok` stays False, so the internal auto-attach (`_attach_suggestion`), which only
    acts on a match, attaches nothing -- this is for a model that ASKED."""
    if _PARSE_ERR.search(message):
        text = ("no recipe matches this message, but it is a PARSE error: the parser "
                "met a token it did not expect. Fix the FIRST diagnostic only -- later "
                "ones are usually a cascade from it -- and re-check. Common causes: a "
                "missing brace around a loop or branch body, a C habit C\u23da does not "
                "have (switch/case, ++ in an expression), or a declaration in the wrong "
                "place. See cg_docs('context') for the syntax C\u23da accepts.")
        topic = "context"
    else:
        text = ("no recipe matches this message. It is not a pattern this kit "
                "recognises, so there is no canned fix -- read the message itself, fix "
                "the FIRST diagnostic, and re-run cg_check. cg_docs('context') covers "
                "the language; cg_example lists verified designs to adapt from.")
        topic = "context"
    return {"ok": False, "matched": False, "error": text, "see_docs": topic}



def _with_lint(result: dict, source: str) -> dict:
    """Attach lint findings to a result the model is ALREADY going to read.

    Probed 2026-08-20 across four model families and eleven runs: `cg_lint` was
    called ZERO times even when listed first with a directive description. A
    model that has just written bad code does not go looking for a linter. So
    the findings are pushed, not offered.

    Two properties matter and are deliberate: attach NOTHING when there are no
    findings (an advisory that appears at random teaches the reader to skip it),
    and cap the count (a long advisory competes with the code for context)."""
    try:
        findings = lint(source).get("findings") or []
    except Exception:
        return result                     # advice must never break the tool
    if findings:
        result = dict(result)
        result["lint"] = findings[:3]
    return result

def _attach_suggestion(result: dict) -> dict:
    """If a result carries diagnostics that match a known failure pattern, attach
    a `suggestion` pointing at the recipe with the synthesizable pattern."""
    diags = result.get("diagnostics") or []
    for i, d in enumerate(diags):
        s = suggest_for_error(d.get("message", "") if isinstance(d, dict) else str(d),
                              is_first=(i == 0))
        if s.get("ok"):
            # `source` was resolved here and then dropped on the floor. It is
            # the seed in seed-and-adapt: the 2026-08-20 probe found models that
            # get a verified base FIRST write legal C(g), while the same models
            # from scratch loop on one error. Pushing the base at the moment of
            # failure turns one into the other, and asks nothing of the model.
            sug = {"recipe": s["recipe"], "hint": s["hint"]}
            if s.get("source"):
                sug["source"] = s["source"]
            result["suggestion"] = sug
            break
    return result


# ------------------------------------------------------------------ scaffold
# Why a scaffold and not "adapt this example": for a small model the ceiling is
# WIRING, not arithmetic. Given an example it must simultaneously infer the file
# skeleton, the port syntax, the test-harness shape AND the datapath. Given a
# skeleton that already compiles, only the datapath is left — the same reason
# draft-completion beats from-scratch generation.
#
# Two invariants make this worth shipping, both enforced by tests:
#   1. every scaffold COMPILES AND SIMULATES GREEN as handed over, so the model
#      starts from a known-good state and any red is its own edit;
#   2. every scaffold's self-test actually FAILS when the datapath is wrong. A
#      harness that passes regardless is worse than none — it is exactly the
#      hollow-fixture trap that hid three shipped bugs.
FILL = ">>> FILL IN"

_SCAFFOLD_KINDS = ("task", "fsm", "stream", "network", "generic")


def _ports(spec, default):
    """Parse ["a:u8", "b:i16"] -> [("a","u8"), ("b","i16")]. A bare name gets u8."""
    out = []
    for item in (spec or default):
        if isinstance(item, (list, tuple)):
            # (name, type); type optional. NB the u8 defaults made an earlier
            # buggy unpack here look correct — hence the explicit test.
            seq = list(item)
            name = str(seq[0]).strip() if seq else ""
            typ = str(seq[1]).strip() if len(seq) > 1 and str(seq[1]).strip() else "u8"
            if name:
                out.append((name, typ))
            continue
        name, _, typ = str(item).partition(":")
        name = name.strip()
        typ = (typ.strip() or "u8")
        if name:
            out.append((name, typ))
    return out or list(default)


def _scaffold_task(name, package, inputs, outputs):
    vec = (1, 2, 3)
    rows = [f"            {n}: [ {', '.join(str(v) for v in vec)} ]," for n, _ in inputs]
    for i, (n, _t) in enumerate(outputs):
        rows.append(f"            {n}: [ {', '.join(str(v) for v in vec)} ]"
                    + ("," if i < len(outputs) - 1 else ""))
    first = inputs[0][0]
    decls = "; ".join([f"in sync {t} {n}" for n, t in inputs]
                      + [f"out sync {t} {n}" for n, t in outputs])
    reads = "\n".join(f"        {t} v_{n} = {n}.read();" for n, t in inputs)
    writes = "\n".join(f"        {n}.write(({t}) v_{first});" for n, t in outputs)
    return f"""package {package};

// {name} -- WHAT IT DOES, in one line.   // {FILL}
//
// SELF-CHECKING. The `test:` block drives every `in sync` port from its vector
// and compares every `out sync` port against its own, one element per cycle and
// index-aligned (an `out sync` write lands in the SAME cycle as the reads). A
// mismatch is reported as `port <name> [vector i] expected X -> Y`.
//
// This scaffold starts GREEN with a pass-through body: run cg_simulate now and
// it passes, so any failure after this point is your edit. Change the body and
// the vectors TOGETHER, and keep every vector the same length.
task {name} {{
    properties {{
        test: {{
{chr(10).join(rows)}
        }}
    }}

    {decls};

    void loop() {{
{reads}
{writes}   // {FILL}: the datapath
    }}
}}
"""


def _scaffold_fsm(name, package):
    return f"""package {package};

// {name} -- a control FSM: pulses `found` on two consecutive 1s.   // {FILL}
//
// The idiomatic C(g) state machine: an ENUM state register + explicit
// next-state logic in loop().
//
// TIMING RULE, the one that bites: a port reflects the register as it was at
// the START of the cycle, so publish the outputs for the CURRENT state BEFORE
// transitioning. Driving an output from a just-computed NEXT state reads back
// one cycle late. `found` here is Mealy (current state AND the input bit),
// `scode` is Moore (the state alone).
//
// The state field needs no setup(): it defaults to the first enum member.
task {name} {{
    properties {{
        test: {{
            din:   [ 1, 0, 1, 1, 0, 1 ],
            found: [ 0, 0, 0, 1, 0, 0 ],
            scode: [ 0, 1, 0, 1, 1, 0 ]
        }}
    }}

    sync {{
        in  bool din;     // one bit per cycle
        out bool found;   // pulses on the cycle the pattern completes
        out u2   scode;   // the current state, observable
    }}

    enum St {{ S0, S1 }}   // {FILL}: name the states after what they MEAN

    St st;   // defaults to S0

    void loop() {{
        bool b = din.read();

        // --- outputs for the CURRENT state (published BEFORE the transition) ---
        bool hit = (st == S1) && b;   // {FILL}: the output condition
        found.write(hit);
        scode.write((u2) st);

        // --- next-state logic ---   // {FILL}
        if (st == S0) {{
            if (b) {{ st = S1; }} else {{ st = S0; }}
        }} else {{
            if (b) {{ st = S1; }} else {{ st = S0; }}
        }}
    }}
}}
"""


def _scaffold_stream(name, package, inputs, outputs):
    vec = (1, 2, 3)
    first = inputs[0][0]
    in_decls = "\n".join(f"    in push {t} {n};" for n, t in inputs)
    out_decls = "\n".join(f"    out push {t} {n};" for n, t in outputs)
    reads = "\n".join(f"        {t} v_{n} = {n}.read();" for n, t in inputs)
    writes = "\n".join(f"        {n}.write(({t}) v_{first});" for n, t in outputs)
    # The harness MUST drive every input and check every output: an unconnected
    # push input blocks its consumer forever and the run dies on the cycle cap.
    drv_decls = "\n".join(f"        out push {t} {n};" for n, t in inputs)
    drv_writes = "\n".join(
        "            " + " ".join(f"{n}.write({v});" for n, _ in inputs)
        for v in vec)
    mon_decls = "\n".join(f"        in push {t} {n};" for n, t in outputs)
    mon_asserts = "\n".join(
        "            " + " ".join(f"assert({n}.read() == {v});" for n, _ in outputs)
        for v in vec)
    wire_in = "\n".join(f"    dut.reads(driver.{n});" for n, _ in inputs)
    wire_out = "\n".join(f"    monitor.reads(dut.{n});" for n, _ in outputs)
    return f"""package {package};

// {name} -- a streaming stage with handshaking ports.   // {FILL}
//
// A `push` port carries a handshake: `read()` BLOCKS until a token arrives and
// `write()` blocks until the consumer can take one. The stage therefore
// self-synchronizes with its neighbours and back-pressures automatically -- you
// never hand-write a ready/valid FSM.
//
// Pick this shape for a DATAFLOW stage. For a cycle-by-cycle function use the
// `sync` + vector shape instead (cg_scaffold kind="task"), whose test block
// value-checks every cycle.
//
// NB every `in push` port must be driven by something. An unconnected one
// blocks this task forever and the run ends on the cycle cap, not an error.
task {name} {{
{in_decls}
{out_decls}

    void loop() {{
{reads}
{writes}   // {FILL}: the datapath
    }}
}}

// The harness: a driver feeds the DUT, a monitor checks what comes back.
// `terminate:` names the flag that ENDS the run. Without it the sim runs to its
// cycle cap and the checker cannot prove it ever executed.
network {name}_test {{
    properties {{ test: {{ terminate: "monitor.finished" }} }}

    dut = new {name}();

    driver = new task {{
{drv_decls}
        void setup() {{   // {FILL}: stimulus
{drv_writes}
        }}
    }};

    monitor = new task {{
{mon_decls}
        bool finished;
        void setup() {{   // {FILL}: expected values
{mon_asserts}
            print("{name}: OK\\n");
            finished = true;
        }}
    }};

{wire_in}
{wire_out}
}}
"""


def _scaffold_network(name, package):
    return f"""package {package};

// {name} -- a two-stage pipeline: Stage1 -> Stage2.   // {FILL}
//
// A network is WIRING ONLY: it instantiates tasks and connects them; all
// behaviour lives in the tasks. `b.reads(a.port)` means "b's input is fed by
// a's output". The push handshake makes the stages self-synchronize, so a
// slower stage back-pressures a faster one with no extra logic.
//
// A single output feeding TWO consumers is a correct broadcast -- both receive
// every token. You do not need a replicator for that.
task Stage1 {{
    in push u8 x;
    out push u8 y;
    void loop() {{ y.write((u8) (x.read() + 1)); }}   // {FILL}
}}

task Stage2 {{
    in push u8 x;
    out push u8 y;
    void loop() {{ y.write((u8) (x.read() * 2)); }}   // {FILL}
}}

network {name} {{
    properties {{ test: {{ terminate: "monitor.finished" }} }}

    s1 = new Stage1();
    s2 = new Stage2();

    driver = new task {{
        out push u8 x;
        void setup() {{ x.write(1); x.write(2); }}
    }};

    monitor = new task {{
        in push u8 y;
        bool finished;
        void setup() {{
            assert(y.read() == 4);    // (1+1)*2
            assert(y.read() == 6);    // (2+1)*2
            print("{name}: OK\\n");
            finished = true;
        }}
    }};

    s1.reads(driver.x);
    s2.reads(s1.y);          // {FILL}: the pipeline order
    monitor.reads(s2.y);
}}
"""


def _scaffold_generic(name, package):
    return f"""package {package};

// {name} -- a PARAMETERIZED entity.   // {FILL}
//
// C(g) generics are `const` parameters + `new {name}({{...}})`. Each
// instantiation is monomorphized into a DISTINCT module with the values baked
// in at elaboration, so parameterization costs nothing at runtime.
//
// Two rules that catch everyone:
//   * every parameter MUST have a default -- the validator rejects an
//     uninitialized const;
//   * a parametric width is `uint<W>` / `int<W>`, never `u<W>`. (`u8` and
//     friends are the FIXED-width spellings and take no brackets.)
// A width may be an expression over the parameters, as `uint<2 * w>` is here.
task {name} {{
    const int k = 3;      // {FILL}: the parameters
    const int w = 8;

    in  push uint<w>     x;
    out push uint<2 * w> y;

    void loop() {{ y.write(x.read() * k); }}   // {FILL}: the datapath
}}

network {name}_test {{
    properties {{ test: {{ terminate: "monitor.finished" }} }}

    dut = new {name}({{k: 5, w: 16}});   // {FILL}: specialize here

    driver = new task {{
        out push uint<16> v;
        void setup() {{ v.write(2); v.write(7); }}
    }};

    monitor = new task {{
        in push uint<32> r;
        bool finished;
        void setup() {{
            assert(r.read() == 10);   // 2*5
            assert(r.read() == 35);   // 7*5
            print("{name}: OK\\n");
            finished = true;
        }}
    }};

    dut.reads(driver.v);
    monitor.reads(dut.y);
}}
"""


def scaffold(kind: str = "task", name: str = "Foo", package: str = "com.example",
             inputs: list | None = None, outputs: list | None = None,
             verify: bool = True) -> dict:
    """Return a COMPILING, SELF-CHECKING C(g) skeleton to fill in.

    See _SCAFFOLD_KINDS for the shapes. `inputs`/`outputs` are "name:type"
    strings and apply to kind="task" and kind="stream"; the other kinds are
    fixed pattern demonstrations and say so in `notes` if ports were passed."""
    kind = (kind or "task").lower()
    if kind not in _SCAFFOLD_KINDS:
        return _with_roster({"ok": False, "error": f"unknown kind '{kind}' -- choose one "
                             f"of {', '.join(_SCAFFOLD_KINDS)}"})
    if not re.match(r"^[A-Za-z_]\w*$", name or ""):
        return {"ok": False, "error": f"'{name}' is not a valid C(g) entity name "
                f"(letters, digits and _, not starting with a digit)"}
    if not re.match(r"^[A-Za-z_]\w*(\.[A-Za-z_]\w*)*$", package or ""):
        return {"ok": False, "error": f"'{package}' is not a valid package name"}

    ins = _ports(inputs, [("a", "u8"), ("b", "u8")])
    outs = _ports(outputs, [("y", "u8")])
    notes = []
    if kind in ("fsm", "network", "generic") and (inputs or outputs):
        notes.append(f"kind='{kind}' is a fixed pattern demonstration -- the "
                     f"inputs/outputs you passed were not applied; edit the "
                     f"ports in the returned source directly.")

    if kind == "task":
        src = _scaffold_task(name, package, ins, outs)
    elif kind == "fsm":
        src = _scaffold_fsm(name, package)
    elif kind == "stream":
        src = _scaffold_stream(name, package, ins, outs)
    elif kind == "network":
        src = _scaffold_network(name, package)
    else:
        src = _scaffold_generic(name, package)

    holes = [{"line": i, "text": ln.strip()}
             for i, ln in enumerate(src.splitlines(), 1) if FILL in ln]
    result = {"ok": True, "kind": kind, "name": name, "source": src,
              "holes": holes, "notes": notes}

    if verify:
        chk = check(src)
        sim = simulate(src, timeout=60) if chk["ok"] else {"ok": False, "output": "(not run)"}
        result["verified"] = {"check": chk["ok"], "simulate": sim["ok"]}
        if not (chk["ok"] and sim["ok"]):
            # A red scaffold is a bug in this kit, not in the caller's design.
            # Say so loudly rather than handing over a broken skeleton silently.
            result["ok"] = False
            result["verified"]["diagnostics"] = (chk.get("diagnostics")
                                                 or sim.get("diagnostics") or [])
            result["verified"]["output"] = sim.get("output") or ""
            result["message"] = ("This scaffold did NOT verify clean, which is a "
                                 "bug in cg_scaffold itself -- your request was "
                                 "fine. Report it; meanwhile use cg_example.")
            return result

    result["message"] = (
        f"A complete, COMPILING {kind} skeleton for {package}.{name}"
        + (" -- verified: it compiles and its self-test passes as handed to you."
           if verify else ".")
        + f" Fill in the {len(holes)} '{FILL}' marker(s) (line numbers in "
          f"'holes'), then call cg_simulate to check your edit. Any failure "
          f"from here is your change, not the skeleton.")
    return result


# -------------------------------------------------------------------- lint
# ---------------------------------------------------------------------------
# cg_lint -- fast static checks for C(g) code that COMPILES CLEANLY AND IS STILL
# WRONG. That is the whole point: `cg_check` already reports what the compiler
# rejects, so a lint that duplicates it adds nothing. Every rule below encodes a
# failure mode that got past the compiler in real work on this codebase.
#
# Precision over recall. Each rule is deliberately narrow, and the 38 validated
# examples in examples/ are the false-positive control: they must ALL lint clean
# (TestLint.test_corpus_is_clean). A rule that cannot be made precise is not shipped.

_LINT_SEVERITY = ("error", "warning")


def _lint_decomment(src: str) -> str:
    """Blank out // and /* */ comments, preserving every offset and line break so
    line numbers computed on the result still refer to the original source."""
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '"' or c == "'":                       # skip string literals whole
            q, i = c, i + 1
            while i < n and src[i] != q:
                i += 2 if src[i] == "\\" else 1
            i += 1
        elif src.startswith("//", i):
            while i < n and src[i] != "\n":
                out[i] = " "
                i += 1
        elif src.startswith("/*", i):
            while i < n and not src.startswith("*/", i):
                if src[i] != "\n":
                    out[i] = " "
                i += 1
            for j in range(i, min(i + 2, n)):
                out[j] = " "
            i += 2
        else:
            i += 1
    return "".join(out)


def _lint_line(src: str, pos: int) -> int:
    return src.count("\n", 0, pos) + 1


def _lint_entities(src: str):
    """Yield (kind, name, body_start, body_end) for each task/network/bundle."""
    for m in re.finditer(r"\b(task|network|bundle)\s+([A-Za-z_]\w*)[^{]*\{", src):
        start = m.end() - 1
        depth, i, n = 0, start, len(src)
        while i < n:
            if src[i] == "{":
                depth += 1
            elif src[i] == "}":
                depth -= 1
                if depth == 0:
                    yield m.group(1), m.group(2), start + 1, i
                    break
            i += 1


def _lint_topdecls(body: str, base: int):
    """Yield (text, abs_pos) for each `;`-terminated declaration at ENTITY scope
    (brace depth 0) -- i.e. ports and state, never anything inside a function."""
    depth, buf, buf_start = 0, [], 0
    for i, c in enumerate(body):
        if c == "{":
            if depth == 0:
                buf, buf_start = [], i + 1
            depth += 1
            continue
        if c == "}":
            depth -= 1
            buf, buf_start = [], i + 1
            continue
        if depth == 0:
            if c == ";":
                yield "".join(buf), base + buf_start
                buf, buf_start = [], i + 1
            else:
                if not buf:
                    buf_start = i
                buf.append(c)


_LINT_PORT_RE = re.compile(
    r"^\s*(in|out)\b((?:\s+(?:sync|push|stream|ready|bare))*)\s+(.+?)\s*$", re.S)


def _lint_ports(body: str, base: int) -> dict:
    """Declared ports -> {name: {"dir", "kind", "line"}}.

    Handles both spellings: a bare `in sync u8 a;` and a grouped
    `sync { in bool din; out u8 crc; }` (the group's contents sit one brace
    deeper, so they are scanned separately)."""
    ports = {}

    def take(text, pos):
        m = _LINT_PORT_RE.match(text)
        if not m:
            return
        # ONE declaration can declare SEVERAL ports, with or without repeating
        # the type: `in u32 val, amt;` and `in push u5 we, u32 wdata;` are both
        # legal. Split on commas and take each part's trailing identifier.
        for part in m.group(3).split(","):
            nm = re.search(r"([A-Za-z_]\w*)\s*$", part)
            if nm:
                ports[nm.group(1)] = {"dir": m.group(1),
                                      "kind": (m.group(2) or "").strip() or "sync",
                                      "line": _lint_line(body, pos - base) if base <= pos else 1}
        return

    for text, pos in _lint_topdecls(body, base):
        take(text, pos)

    # grouped form: `sync { ... }` / `push { ... }` at entity scope
    for gm in re.finditer(r"\b(sync|push|stream|bare)\s*\{", body):
        depth, i, n = 0, gm.end() - 1, len(body)
        while i < n:
            if body[i] == "{":
                depth += 1
            elif body[i] == "}":
                depth -= 1
                if depth == 0:
                    inner = body[gm.end():i]
                    for part in inner.split(";"):
                        if part.strip():
                            take(part, base + gm.end())
                    break
            i += 1
    return ports


def _lint_test_block(body: str, base: int):
    """The `test:` fixture -> (rows, abs_pos) where rows = [(key, n_values, line)].
    Returns (None, None) when the entity declares no test property."""
    tm = re.search(r"\btest\s*:\s*\{", body)
    if not tm:
        return None, None
    depth, i, n = 0, tm.end() - 1, len(body)
    end = None
    while i < n:
        if body[i] == "{":
            depth += 1
        elif body[i] == "}":
            depth -= 1
            if depth == 0:
                end = i
                break
        i += 1
    if end is None:
        return None, None
    inner = body[tm.end():end]
    rows = []
    for rm in re.finditer(r"([A-Za-z_]\w*)\s*:\s*\[([^\]]*)\]", inner):
        vals = [v for v in rm.group(2).split(",") if v.strip()]
        rows.append((rm.group(1), len(vals),
                     _lint_line(body, tm.end() + rm.start())))
    return rows, base + tm.start()


def lint(source: str) -> dict:
    """Static checks for C(g) that compiles but is wrong. See _LINT_* above.

    F102. `checked` used to be hard-wired True, so lint CERTIFIED anything it could
    not read: a filename, the word "hello", a path that does not exist -- each came
    back {"ok": true, "checked": true, "findings": []}. It found nothing to object to
    because it found nothing at all. That is the worst possible output for a tool
    whose purpose is to be run "before you claim a design is verified": measured in
    the AccelOne trial, a model linted a PATH and got a clean bill of health in the
    same second that cg_check correctly rejected it.

    So: the same `source`-takes-text guard as the compiling tools (lint never calls
    `_run`, which is why the F87 guard did not reach it -- "a guard on one of four is
    its own trap", and this was the fifth), and `checked` now means an entity was
    actually examined.
    """
    usage = _source_usage_error(source)
    if usage:
        return {"ok": False, "checked": False, "findings": [], "error": usage}
    src = _lint_decomment(source or "")
    entities = list(_lint_entities(src))
    if not entities:
        return {"ok": False, "checked": False, "findings": [],
                "error": "no task, network or bundle was found in `source`, so NOTHING "
                         "was linted -- this is not a clean result. Pass the C\u23da text "
                         "of a design (the `package` line plus at least one entity)."}
    findings = []

    def add(rule, line, severity, message, fix):
        findings.append({"rule": rule, "line": line, "severity": severity,
                         "message": message, "fix": fix})

    for kind, name, bstart, bend in entities:
        body = src[bstart:bend]
        ports = _lint_ports(body, bstart)
        outs = {p for p, d in ports.items() if d["dir"] == "out"}
        rows, tpos = _lint_test_block(body, bstart)

        if rows is not None:
            tline = _lint_line(src, tpos)
            keys = [k for k, _c, _l in rows]

            # (1) A fixture that drives inputs and checks NO output passes with a
            # DEAD dut -- the exact hollow-gate failure that hid 25 broken tests.
            if keys and outs and not (set(keys) & outs):
                add("test-checks-no-output", tline, "error",
                    f"{kind} {name}: the test fixture drives {sorted(keys)} but "
                    f"checks no output port, so it PASSES even if the design does "
                    f"nothing at all.",
                    f"add a vector for an out port ({', '.join(sorted(outs))}) -- "
                    f"that is what turns the fixture into a check.")

            # (2) Ragged vectors: the short row silently stops checking early.
            # ONLY meaningful when every fixture port is `sync`, i.e. sampled once
            # per cycle, so the rows are index-aligned. With push/stream ports the
            # rates legitimately differ -- a 4:1 reduction emits 2 results for 8
            # inputs, and flagging that would be plain wrong.
            all_sync = all(ports.get(k, {}).get("kind", "sync") == "sync"
                           for k in keys if k in ports)
            lens = {c for _k, c, _l in rows}
            if all_sync and len(lens) > 1:
                worst = min(rows, key=lambda r: r[1])
                add("test-vectors-ragged", worst[2], "error",
                    f"{kind} {name}: test vectors have different lengths "
                    f"({sorted(lens)}); '{worst[0]}' is the shortest at {worst[1]}.",
                    "make every row the same length -- cycles past the shortest "
                    "row are not driven or not compared.")

            # (3) A fixture key that is not a port is silently not a check.
            for k, _c, l in rows:
                if ports and k not in ports:
                    add("test-unknown-port", l, "error",
                        f"{kind} {name}: test vector '{k}' does not match any "
                        f"declared port.",
                        f"declared ports are {sorted(ports)} -- fix the spelling.")

        # (4) bool compared against an integer literal: a deliberate validation
        # ERROR in the compiler, and the single most common thing a model writes.
        bools = {m.group(1) for m in re.finditer(
            r"\bbool\s+([A-Za-z_]\w*)", body)}
        for bm in re.finditer(r"\b([A-Za-z_]\w*)\s*(==|!=)\s*([01])\b", body):
            if bm.group(1) in bools:
                add("bool-compared-to-int", _lint_line(src, bstart + bm.start()),
                    "error",
                    f"{kind} {name}: '{bm.group(1)}' is a bool compared against "
                    f"the integer {bm.group(3)} -- the compiler rejects this.",
                    f"compare against a bool: `{bm.group(1)}` or "
                    f"`!{bm.group(1)}` (and `^`/`!=` between two bools is fine).")

    return {"ok": not any(f["severity"] == "error" for f in findings),
            "findings": findings, "checked": True,
            "entities_checked": [n for _k, n, _s, _e in entities]}


# --------------------------------------------------------- the tool roster
# THE PROBLEM. A model that has drifted starts calling tools that do not exist
# (`cg_compile`, `cg_run`, `cg_list_tools`) and then loops on the failure. The
# real names are in the system prompt — and a model confused enough to invent
# one is exactly the model that will not go back and re-read the system prompt.
#
# WHY NOT A `cg_list_tools` TOOL. That is the obvious answer and it is the wrong
# one. The 2026-08-20 probe measured three of four model families calling
# `cg_lint` / `cg_suggest_for_error` ZERO times, with `cg_lint` listed FIRST and
# a description telling them to run it first. You cannot DEPEND on a lost model
# calling a discovery tool, so the roster is PUSHED at the moments drift is
# visible — the same move that turned lint findings from offered into pushed.
# (A model that guesses `cg_list_tools` anyway still gets the list: an unknown
# tool IS answered with the roster, so the pull affordance exists for free,
# costing no tool slot and no system-prompt tokens.)
#
# WHERE IT IS PUSHED, and deliberately where it is NOT:
#   * an unknown-tool call — the caller has just proved it is working from a
#     tool list that is not ours. Highest-value moment there is.
#   * a real tool told to use a thing that does not exist (simulator= / kind= /
#     flow= / target= / topic=) — the same drift, one level down.
#   * once, on the first tool call of the process (session start), so the names
#     arrive before drift rather than after it.
#   * inside cg_capabilities, which is already the "what can I do here" answer.
#   * NOT on a successful call, and NOT on an ordinary compile / simulate
#     failure. Those are the common case, and there the model is on-track and
#     iterating with the right tool: appending ~250 tokens of roster to every
#     result would tax the loop that already works, and an advisory that turns
#     up everywhere is one the reader learns to skip.
#
# The roster is GENERATED FROM THE REGISTRY: `@_tool` is the only way a function
# becomes an MCP tool and it carries the one-line summary with it, so a tool
# cannot exist without a roster line and a roster line cannot outlive its tool.
# A hand-maintained list would eventually name a tool that is not there, which
# is worse than no roster at all.

_MCP_TOOLS: list = []

_ROSTER_NOTE = ("These are the ONLY tools this server exposes. Call one by its exact "
                "name — a name that is not on this list will fail again the same way.")


def _tool(summary: str):
    """Register a module-level function as an MCP tool AND as its roster line.

    `summary` is mandatory, so it is impossible to add a tool and forget the
    roster. The returned wrapper carries the once-per-session roster push and
    keeps the wrapped function's signature, annotations and docstring — which is
    what the MCP layer builds the tool schema and description from (verified
    against mcp 2.0.0: `inspect.signature` follows `__wrapped__`)."""
    def register(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            result = fn(*args, **kwargs)
            return _roster_on_first_call(result) if isinstance(result, dict) else result
        wrapper._cg_summary = summary
        _MCP_TOOLS.append(wrapper)
        return wrapper
    return register


def tool_roster() -> list:
    """[{name, summary}] for every registered tool — straight from the registry."""
    return [{"name": f.__name__, "summary": getattr(f, "_cg_summary", "")}
            for f in _MCP_TOOLS]


def _known_entries(known=None) -> list:
    """Normalise a caller-supplied tool list (names or {name, summary} dicts) to
    entries. `known` exists for the OTHER model-facing surface in this kit:
    cg_local_client exposes a deliberate 4-tool subset, and its roster must be
    ITS list, not this one."""
    if known is None:
        return tool_roster()
    return [{"name": k, "summary": ""} if isinstance(k, str) else dict(k) for k in known]


def _roster_lines(known=None) -> list:
    """The roster as compact `name — summary` lines. This is what gets pushed;
    argument schemas are deliberately left out (the host already has them, and
    the point here is the NAMES). Summaries are capped, because a caller-supplied
    list may carry full tool descriptions and the whole roster has to stay cheap
    enough to push without thinking about it."""
    out = []
    for e in _known_entries(known):
        summary = " ".join((e.get("summary") or "").split())
        if len(summary) > 96:
            summary = summary[:95].rsplit(" ", 1)[0] + "…"
        out.append(f"{e['name']} — {summary}" if summary else e["name"])
    return out


# A model rarely invents a name at random — it reaches for the name the tool
# would have in some other toolchain. Fuzzy matching alone does not catch that:
# `cg_compile` -> `cg_check` is a 5-character edit on a 10-character name, well
# past any sane cutoff. So the semantic guesses are written down. This is not a
# second roster and it cannot go stale into a lie: every VALUE is asserted
# against the registry by TestToolRoster.test_every_alias_points_at_a_real_tool.
_TOOL_ALIASES = {
    "cg_compile": "cg_check", "cg_build": "cg_check", "cg_parse": "cg_check",
    "cg_validate": "cg_check", "cg_verify": "cg_check", "cg_typecheck": "cg_check",
    "cg_type_check": "cg_check", "cg_compile_check": "cg_check",
    "cg_analyze": "cg_lint", "cg_analyse": "cg_lint", "cg_style": "cg_lint",
    "cg_run": "cg_simulate", "cg_test": "cg_simulate", "cg_sim": "cg_simulate",
    "cg_execute": "cg_simulate", "cg_run_test": "cg_simulate", "cg_run_tests": "cg_simulate",
    "cg_generate": "cg_generate_verilog", "cg_verilog": "cg_generate_verilog",
    "cg_emit": "cg_generate_verilog", "cg_codegen": "cg_generate_verilog",
    "cg_generate_hdl": "cg_generate_verilog", "cg_generate_vhdl": "cg_generate_verilog",
    "cg_vhdl": "cg_generate_verilog", "cg_compile_verilog": "cg_generate_verilog",
    "cg_synthesize": "cg_synth", "cg_synthesise": "cg_synth", "cg_yosys": "cg_synth",
    "cg_template": "cg_scaffold", "cg_skeleton": "cg_scaffold", "cg_new": "cg_scaffold",
    "cg_init": "cg_scaffold", "cg_create": "cg_scaffold", "cg_boilerplate": "cg_scaffold",
    "cg_examples": "cg_example", "cg_recipe": "cg_example", "cg_recipes": "cg_example",
    "cg_get_example": "cg_example", "cg_library": "cg_example", "cg_search": "cg_example",
    "cg_help": "cg_docs", "cg_doc": "cg_docs", "cg_documentation": "cg_docs",
    "cg_manual": "cg_docs", "cg_reference": "cg_docs", "cg_context": "cg_docs",
    "cg_language": "cg_docs", "cg_guide": "cg_docs",
    "cg_diagnose": "cg_suggest_for_error", "diagnose_error": "cg_suggest_for_error",
    "cg_fix": "cg_suggest_for_error", "cg_error": "cg_suggest_for_error",
    "cg_explain_error": "cg_suggest_for_error", "cg_suggest": "cg_suggest_for_error",
    "cg_states": "cg_fsm", "cg_state_machine": "cg_fsm",
    "cg_network": "cg_graph", "cg_wiring": "cg_graph", "cg_netlist": "cg_graph",
    "cg_info": "cg_capabilities", "cg_status": "cg_capabilities",
    "cg_env": "cg_capabilities", "cg_version": "cg_capabilities",
}

# A call that is ASKING for the list — `cg_list_tools`, `list_tools`, `cg_tools`
# — gets the list, which is what the unknown-tool answer already is. Phrase it
# as an answer rather than a "did you mean", because there is nothing to correct.
_DISCOVERY_RE = re.compile(r"list.*tool|tool.*list|^tools?$|^help$|discover|manifest",
                           re.I)


def _norm_tool(name: str) -> str:
    """Fold a tool name to its comparable core. Case, separators and the host's
    namespace prefix all vary — `mcp__cg__cg_check`, `cg.check`, `cgCheck` — and
    none of that is the model being wrong about WHICH tool it wants."""
    n = re.sub(r"[^a-z0-9]", "", (name or "").lower())
    for prefix in ("mcp", "neosyn", "cg"):
        while n.startswith(prefix) and len(n) > len(prefix):
            n = n[len(prefix):]
    return n


def did_you_mean(name: str, known=None) -> str | None:
    """The tool the caller most likely meant, or None.

    Four legs, most confident first: the same name modulo case / separators /
    host prefix (`mcp__cg__cg_check`), a known synonym from another toolchain
    (`cg_compile`), a real name CONTAINED in the invented one
    (`cg_check_source`), then difflib's closest match — a similarity ratio, i.e.
    edit distance normalised by length. The synonym leg is the one that earns
    its keep; pure edit distance misses precisely the confident wrong guesses."""
    names = [e["name"] for e in _known_entries(known)]
    if not name or not names:
        return None
    n = _norm_tool(name)
    index = {_norm_tool(r): r for r in names}
    if n in index:
        return index[n]
    target = {_norm_tool(k): v for k, v in _TOOL_ALIASES.items()}.get(n)
    if target in names:
        return target
    contained = [r for k, r in index.items() if k and (k in n or n in k)]
    if contained:
        return max(contained, key=lambda r: len(_norm_tool(r)))
    close = difflib.get_close_matches(n, list(index), n=1, cutoff=0.6)
    return index[close[0]] if close else None


def unknown_tool(name: str, known=None) -> dict:
    """The answer to a call for a tool that does not exist: the real roster plus
    the closest match. THE highest-value push point in the kit — the caller has
    just proved it is working from a tool list that is not ours, so this is the
    one moment where spending the tokens is unarguable."""
    guess = did_you_mean(name, known)
    if guess:
        head = f"There is no `{name}` tool. Did you mean `{guess}`?"
    elif _DISCOVERY_RE.search(_norm_tool(name)):
        # Match on the NORMALISED name: the guess arrives as `cg_list_tools`,
        # `list_tools`, `cg.tools`, ... and they are all the same question.
        head = (f"There is no `{name}` tool — but if you were asking what exists, "
                f"this is the answer.")
    else:
        head = f"There is no `{name}` tool."
    return {"ok": False, "error": head, "did_you_mean": guess,
            "available_tools": _roster_lines(known), "tools_note": _ROSTER_NOTE}


def unknown_tool_message(name: str, known=None) -> str:
    """`unknown_tool` as plain text, for the paths that can only carry a string
    (the MCP layer turns a raised exception into the tool result's text)."""
    r = unknown_tool(name, known)
    return "\n".join([r["error"], ""] + [f"  {line}" for line in r["available_tools"]]
                     + ["", r["tools_note"]])


def _with_roster(result: dict, note: str = "") -> dict:
    """Attach the roster to a failure that says the CALLER is off-track: it named
    a simulator / kind / flow / target / topic that does not exist. That is the
    same drift as an invented tool name, one level down — something in the
    caller's head does not match this server. Ordinary compile and simulation
    failures never come here: there the model is holding the right tool and the
    diagnostics are the answer."""
    out = dict(result)
    out["available_tools"] = _roster_lines()
    out["tools_note"] = f"{note} {_ROSTER_NOTE}".strip() if note else _ROSTER_NOTE
    return out


_ROSTER_PUSHED = False


def _roster_on_first_call(result: dict) -> dict:
    """Push the roster ONCE per process, on whatever the first tool call happens
    to be, so the exact names are in the transcript before drift starts.

    The limit, stated rather than glossed: an MCP host normally spawns one server
    process per session (stdio), which makes this once per session — but under a
    long-lived HTTP server it is once per PROCESS, so only the first session gets
    it. That is also the deployment where a per-call tax would hurt most, so the
    trade stands. `CG_TOOL_ROSTER=off` drops this push; the unknown-tool answer
    is never optional and is not affected."""
    global _ROSTER_PUSHED
    if _ROSTER_PUSHED or not isinstance(result, dict):
        return result
    if os.environ.get("CG_TOOL_ROSTER", "").strip().lower() in ("off", "0", "no", "false"):
        return result
    _ROSTER_PUSHED = True
    if "available_tools" in result:      # cg_capabilities already carries it
        return result
    out = dict(result)
    out["available_tools"] = _roster_lines()
    out["tools_note"] = ("Pushed once at the start of this session so you have the exact "
                         "names; it will not be repeated. " + _ROSTER_NOTE)
    return out


class UnknownToolError(Exception):
    """A call for a tool that does not exist. Its `str()` IS what the model
    reads: the MCP layer returns `str(exception)` as the tool result's text."""


def install_unknown_tool_guard(server) -> bool:
    """Make a call for a tool that does not exist answer with the roster instead
    of a bare "Unknown tool: X". Returns whether the guard could be installed.

    The MCP layer DOES let the server see unknown-tool calls — verified against
    mcp 2.0.0 rather than assumed. `MCPServer.call_tool` delegates to
    `_tool_manager.call_tool`, which is where `ToolError("Unknown tool: X")` is
    raised, and `_handle_call_tool` catches any non-protocol exception and
    returns it to the model as an is_error tool result whose text is
    `str(exception)`. So wrapping the manager puts our text in front of the model
    verbatim, with no change to the wire format and no SDK hook required. mcp 1.x
    FastMCP has the same `_tool_manager.call_tool` shape.

    Defensive by construction: if the manager is not where we expect, the server
    still starts and simply keeps the SDK's bare message."""
    manager = (getattr(server, "_tool_manager", None)
               or getattr(server, "tool_manager", None))
    original = getattr(manager, "call_tool", None)
    if original is None or getattr(original, "_cg_guarded", False):
        return False
    registered = {e["name"] for e in tool_roster()}

    def _is_known(name) -> bool:
        get = getattr(manager, "get_tool", None)
        if callable(get):
            try:
                return get(name) is not None
            except Exception:               # noqa: BLE001 — can't tell; let the SDK decide
                return True
        return name in registered

    if inspect.iscoroutinefunction(original):
        @functools.wraps(original)
        async def guarded(name, *args, **kwargs):
            if not _is_known(name):
                raise UnknownToolError(unknown_tool_message(name))
            try:
                return await original(name, *args, **kwargs)
            except Exception as e:          # noqa: BLE001
                # Belt and braces: whatever the SDK version decides is unknown,
                # the model gets the roster rather than three bare words.
                if "unknown tool" in str(e).lower():
                    raise UnknownToolError(unknown_tool_message(name)) from e
                raise
    else:                                   # no shipping SDK is sync here — future-proofing
        @functools.wraps(original)
        def guarded(name, *args, **kwargs):
            if not _is_known(name):
                raise UnknownToolError(unknown_tool_message(name))
            try:
                return original(name, *args, **kwargs)
            except Exception as e:          # noqa: BLE001
                if "unknown tool" in str(e).lower():
                    raise UnknownToolError(unknown_tool_message(name)) from e
                raise

    guarded._cg_guarded = True
    manager.call_tool = guarded
    return True


# -------------------------------------------------------------- MCP wrapper
# The tools, at MODULE scope so `@_tool` can register them into `_MCP_TOOLS`
# before any server exists — the roster is then available with no `mcp` package
# installed, and every tool is directly callable from the tests. build_server()
# hands this same list to the MCP layer.
@_tool("parse/scope/type-check a draft; returns diagnostics. Fix these first.")
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

@_tool("run the design and self-check its `test:` vectors — the correctness gate.")
def cg_simulate(source: str, extra_files: dict | None = None,
                timeout: int = 60, simulator: str = "bytecode",
                package_dir: str | None = None,
                report_dir: str | None = "fpga/build") -> dict:
    """Simulate C⏚ source. Returns {ok, simulator, timed_out, diagnostics,
    output}. `output` holds port values and print() lines; a
    `properties { test: {...} }` block self-checks and fails the run on
    mismatch. This is the ground-truth correctness check — iterate until
    ok is true.

    `simulator` picks the backend. 'bytecode' (default) is the fast
    cycle-accurate simulator — no HDL toolchain, and a
    `properties { test: {...} }` block self-checks. It ships with the
    commercial Neosyn distribution; the open-source compiler has no
    `simulate` verb and the call then returns `available: False` with a
    pointer, NOT a design error. 'iverilog' generates Verilog + a
    testbench and runs Icarus Verilog — a slower cross-check that needs a
    network whose NAME contains "Test" (capital T) on every released
    compiler -- a `test` property or a `_test` name also work after 3.2.0.
    Call cg_capabilities
    to see which backends this host actually has; do not assume.
    """
    r = simulate(source, extra_files, timeout, simulator, package_dir)
    if report_dir:
        accumulate_report(report_dir, "sim", r)
    return r

@_tool("emit synthesizable Verilog (or VHDL) once the design simulates.")
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

@_tool("what this host actually has (jar, simulators, yosys) — probed, not assumed.")
def cg_capabilities() -> dict:
    """What this host can actually do — PROBED, not assumed. Call it before
    deciding how to verify a design, instead of assuming a backend exists.

    Returns {jar, jar_present, bytecode_simulator:{available,reason,detail},
    simulators:[...], tools:{iverilog,vvp,verilator,yosys,ghdl}, advice}.

    The fast bytecode simulator ships with the commercial Neosyn
    distribution and is absent from the open-source compiler, so any flat
    claim about it is wrong in one of the two environments. `advice` is
    written from what was actually found here."""
    return capabilities()

@_tool("a compiling, self-checking skeleton to fill in; START HERE from a blank file.")
def cg_scaffold(kind: str = "task", name: str = "Foo",
                package: str = "com.example",
                inputs: list | None = None, outputs: list | None = None,
                verify: bool = True) -> dict:
    """START HERE when writing new C⏚ from a blank file. Returns a COMPLETE,
    COMPILING, SELF-CHECKING skeleton with the datapath left as marked holes
    — you fill in the holes instead of inferring the file skeleton, the port
    syntax and the test-harness shape at the same time.

    It is verified before you get it: the returned source compiles AND its
    self-test passes as handed over (`verified`). So it starts GREEN — any
    failure after your edit is your edit, which makes cg_simulate a real
    signal instead of a guess.

    kind:
      task     a `sync` task whose `test:` block VALUE-CHECKS every output
               cycle by cycle. The default, and the strongest: prefer it
               whenever the design is a cycle-by-cycle function.
      fsm      an enum-state control machine (+ the publish-before-transition
               timing rule, the one that bites).
      stream   a `push`-handshake dataflow stage + driver/monitor harness.
      network  a two-stage pipeline, showing wiring and back-pressure.
      generic  a parameterized entity: const params + new Foo({k: 5, w: 16}).

    `inputs`/`outputs` are "name:type" strings (e.g. ["a:u8","b:i16"]) and
    apply to kind="task" and kind="stream"; a bare "a" defaults to u8. The
    other kinds are fixed pattern demonstrations — edit their ports in the
    returned source.

    `holes` gives the line number of every ">>> FILL IN" marker. Workflow:
    cg_scaffold → fill the holes → cg_check → cg_simulate →
    cg_generate_verilog → cg_synth. (cg_example is the complement: reach for
    it when a VALIDATED implementation of a known kernel already exists.)"""
    return scaffold(kind=kind, name=name, package=package, inputs=inputs,
                    outputs=outputs, verify=verify)

@_tool("a VERIFIED implementation to seed-and-adapt, from the validated dictionary.")
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

@_tool("static checks for C⏚ that compiles and is still wrong; no jar, instant.")
def cg_lint(source: str) -> dict:
    """Fast static checks for C⏚ that COMPILES CLEANLY AND IS STILL WRONG.
    Returns {ok, findings:[{rule, line, severity, message, fix}]}; ok is
    False if any finding is an error.

    This does NOT replace `cg_check` -- it catches what the compiler
    ACCEPTS. Chiefly: a `test:` fixture that drives inputs but compares no
    output (it passes even with a dead design -- the single most expensive
    failure mode in this codebase), ragged vectors in a sync fixture, a
    fixture key that matches no port, and a bool compared against 0/1.

    No jar, no simulator, no timeout -- run it on every draft before
    `cg_check`, and again before you claim a design is verified."""
    return lint(source)

@_tool("map a compiler error to its fix (a hint, and a recipe where there is one).")
def cg_suggest_for_error(message: str) -> dict:
    """Map a compiler error/diagnostic to the fix for it. Returns
    {ok, recipe, hint, source}.

    Two kinds of answer:
    - AUTHORING/WIRING errors (the file doesn't parse, a sibling entity
      isn't visible, the jar failed to load) → `recipe` and `source` are
      None and `hint` carries the whole fix, which is a one-line edit.
      Apply the hint literally; do NOT redesign the datapath.
    - SYNTHESIZABILITY errors (the construct has no hardware) → `recipe`
      names a validated example and `source` is its full C⏚, to adapt.
      div/shift-by-a-variable → Recip; a data-dependent loop bound → SeqDiv.

    cg_check/cg_simulate/cg_generate_verilog/cg_synth already auto-attach
    this as a `suggestion` when a diagnostic matches; call this directly to
    look one up."""
    return suggest_for_error(message)

@_tool("yosys-synthesize the Verilog: REAL/FOLDED/SUSPECT verdict + cell count.")
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

@_tool("render report.html from the synth/sim results already collected.")
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

@_tool("the compiled state machine of a task (states + transitions).")
def cg_fsm(source: str, task: str | None = None,
           extra_files: dict | None = None) -> dict:
    """Show a task's compiled state machine (states + transitions). Useful
    to confirm an FSM has the intended number of states."""
    return fsm(source, task, extra_files)

@_tool("the compiled graph of a network (instances, ports, connections).")
def cg_graph(source: str, network: str | None = None,
             extra_files: dict | None = None) -> dict:
    """Show a network's compiled graph (instances, ports with widths and
    interfaces, connections). Useful to confirm wiring."""
    return graph(source, network, extra_files)

@_tool("fetch a knowledge pack: context, handshakes, arithmetic, fsm, riscv.")
def cg_docs(topic: str = "", section: str = "") -> dict:
    """Fetch a markdown knowledge doc. No topic → an index of available
    topics, their descriptions and their SECTIONS; a topic → its full content
    plus its section names; a topic and a `section` → just that section.
    Re-reading one section is far cheaper than the whole doc -- after your
    context is compacted, fetch the section you need, not the whole topic.
    Topics:
    'context' (the core C⏚ language pack — load before writing any Cg);
    'handshakes' (port protocols push/stream/confirm, back-pressure, and the
    pacing gotcha when feeding a registered built-in — read before wiring a
    network); 'arithmetic' (what *, /, %, <<, >> synthesize to and when they
    need a std.math built-in or a barrel shifter — read before writing
    math); and 'riscv' (the worked RV32I CPU reference: the loadable
    single-cycle core and the reusable patterns for CPU-shaped hardware in
    Cg — barrel shifter, signed/unsigned widening, sub-word load/store,
    count-prefixed boot-stream program loading, and the lossless-capture /
    address-filtered testbench patterns — read when building or extending a
    processor, instruction decoder, datapath, or stack machine)."""
    return docs(topic, section)


def build_server():
    # `mcp` 2.0 renamed FastMCP -> MCPServer and moved it out of
    # mcp.server.fastmcp, which no longer exists there. requirements.txt says
    # `mcp>=1.0`, so a fresh install today gets 2.x and the old import made the
    # server fail to START — every tool in this file unreachable. The decorator
    # and run() APIs are identical across the two, so one shim covers both.
    try:
        from mcp.server.mcpserver import MCPServer as _Server   # mcp >= 2.0
    except ImportError:                                          # pragma: no cover
        from mcp.server.fastmcp import FastMCP as _Server        # mcp 1.x

    mcp = _Server("cg")
    # Registration reads the registry, so the tools the server EXPOSES and the
    # roster it PUSHES are the same list by construction and cannot drift apart.
    # The tool functions themselves are module-level (above), which also makes
    # them callable from the tests without an MCP host installed.
    for fn in _MCP_TOOLS:
        mcp.tool()(fn)
    install_unknown_tool_guard(mcp)
    return mcp


def main():
    build_server().run()


if __name__ == "__main__":
    main()
