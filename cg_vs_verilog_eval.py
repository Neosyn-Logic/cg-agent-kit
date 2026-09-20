#!/usr/bin/env python3
"""
cg_vs_verilog_eval.py — measure how well a local model writes C⏚ vs Verilog.

Same set of small registered-output hardware tasks, each written by the model
twice: once in C⏚ (verified by the Neosyn bytecode simulator) and once in
Verilog (verified by iverilog + vvp against a harness testbench). Each target
gets the same write→verify→fix loop with real tool feedback. Reports first-try
and after-loop pass rates per language, plus the failure kinds.

Config (env): CG_LLM_URL or CG_OLLAMA_URL (either dialect), CG_LLM_MODEL,
CG_JAR  (see cg_local_client.py).
Usage: python cg_vs_verilog_eval.py [--fix N] [--trials N]
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import tempfile
import urllib.request
from pathlib import Path

import cg_mcp_server as cg

from cg_local_client import resolve_endpoint  # one resolver, both dialects
NATIVE = resolve_endpoint("native")
MODEL = os.environ.get("CG_LLM_MODEL", "qwen3.6:35b-a3b")
ENV = {**os.environ, "NEOSYN_CG_DEV": os.environ.get("NEOSYN_CG_DEV", "1")}
HERE = os.path.dirname(os.path.abspath(__file__))
# The kit's knowledge pack — given to the model ONLY for C⏚ (it knows Verilog
# natively). This is the comparison: native Verilog vs C⏚-with-the-kit.
CG_CONTEXT = open(os.path.join(HERE, "cg_context.md")).read()

# Each task: a registered output `q` that holds a value per cycle, starting at
# `reset` and advancing by `rule`. `expected` is the held sequence.
TASKS = [
    {"name": "Counter4", "width": 4, "reset": 0,
     "expected": [0, 1, 2, 3, 4, 5, 6, 7],
     "cg": "a 4-bit counter: q starts at 0 and increases by 1 each cycle, wrapping at 16",
     "rule": "q increments by 1 (wrapping at 16)"},
    {"name": "Toggle", "width": 1, "reset": 0,
     "expected": [0, 1, 0, 1, 0, 1],
     "cg": "a 1-bit toggle: q alternates 0,1,0,1 each cycle",
     "rule": "q toggles (inverts)"},
    {"name": "Accum3", "width": 8, "reset": 0,
     "expected": [0, 3, 6, 9, 12, 15, 18, 21],
     "cg": "an accumulator: q starts at 0 and increases by 3 each cycle",
     "rule": "q increases by 3"},
    {"name": "Mod6", "width": 3, "reset": 0,
     "expected": [0, 1, 2, 3, 4, 5, 0, 1],
     "cg": "a counter modulo 6: q counts 0,1,2,3,4,5 then wraps to 0",
     "rule": "q increments by 1, wrapping back to 0 after 5 (i.e. modulo 6)"},
    {"name": "Fib8", "width": 8, "reset": 1,
     "expected": [1, 1, 2, 3, 5, 8, 13, 21],
     "cg": "a Fibonacci generator: q is the current Fibonacci number, the "
           "sequence 1,1,2,3,5,8,13,21 (each q is the sum of the two previous)",
     "rule": "q becomes the next Fibonacci number (q holds 1,1,2,3,5,8,...)"},
]


# ----------------------------------------------------------------- LLM
def complete(system, messages, timeout=300):
    # Ollama native /api/chat with think:false — reliably disables the
    # reasoning pass (the /v1 /no_think prompt token did not), keeping calls
    # fast. think:false is applied to BOTH languages, so the comparison is fair.
    msgs = ([{"role": "system", "content": system}] if system else []) + list(messages)
    body = {"model": MODEL, "messages": msgs, "think": False, "stream": False,
            "options": {"temperature": 0.2}}
    req = urllib.request.Request(NATIVE, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)["message"]["content"] or ""


_BLOCK = re.compile(r"```(?:cg|c|verilog|v|systemverilog)?\s*\n(.*?)```", re.S)


def extract(text):
    blocks = _BLOCK.findall(text or "")
    return blocks[-1].strip() if blocks else (text or "").strip()


# ----------------------------------------------------------------- C⏚ verify
def verify_cg(source):
    r = cg.simulate(source)
    if r["ok"]:
        return True, "ok", None
    if r["diagnostics"]:
        # A test-vector mismatch arrives as a DIAGNOSTIC, not as sim output -- so
        # labelling every diagnostic-bearing result "compile" counted C(g) designs that
        # compiled and simulated and merely computed the WRONG ANSWER as compile
        # failures. Measured 2026-08-24: both deterministic first-try C(g) failures in
        # the task set (Toggle, Fib8) are exactly this, and both were being reported as
        # "compile". That inverts the qualitative reading, because the whole point of the
        # `kind` column is to say HOW each language fails -- it made C(g)'s residue look
        # syntactic when it is a state-update-ordering error, i.e. the SAME timing/state
        # class the writeup attributes to Verilog. The Verilog side never had the problem:
        # its value failures come back through the vvp path and were always "sim".
        vector_failure = any(
            str(d.get("message", "")).startswith("test failure:") for d in r["diagnostics"])
        kind = "sim" if vector_failure else "compile"
        return False, json.dumps(r["diagnostics"][:3]), kind
    if r.get("timed_out"):
        return False, "simulation timed out (often a conditional push output)", "sim"
    return False, r["output"][-500:], "sim"


# ----------------------------------------------------------------- Verilog verify
def _tb(name, width, expected):
    n = len(expected)
    init = "\n".join(f"    expected[{i}] = {v};" for i, v in enumerate(expected))
    return f"""`timescale 1ns/1ps
module tb;
  reg clk = 0, rst_n = 0;
  wire [{width-1}:0] q;
  {name} dut(.clk(clk), .rst_n(rst_n), .q(q));
  always #5 clk = ~clk;
  integer i, errors;
  reg [{width-1}:0] expected [0:{n-1}];
  initial begin
    errors = 0;
{init}
    rst_n = 0;
    @(negedge clk);          // a posedge under reset loads q = reset value
    rst_n = 1;
    for (i = 0; i < {n}; i = i + 1) begin
      if (q !== expected[i]) begin
        $display("MISMATCH i=%0d got=%0d exp=%0d", i, q, expected[i]);
        errors = errors + 1;
      end
      @(negedge clk);        // advance one full cycle
    end
    if (errors == 0) $display("ALL_PASS"); else $display("FAILURES=%0d", errors);
    $finish;
  end
endmodule
"""


def verify_verilog(name, width, expected, source, timeout=20):
    d = Path(tempfile.mkdtemp(prefix="cg_vlog_"))
    try:
        (d / "dut.v").write_text(source)
        (d / "tb.v").write_text(_tb(name, width, expected))
        comp = subprocess.run(["iverilog", "-g2012", "-o", str(d / "sim"),
                               str(d / "dut.v"), str(d / "tb.v")],
                              capture_output=True, text=True, cwd=d)
        if comp.returncode != 0:
            return False, comp.stderr.strip()[-500:], "compile"
        try:
            run = subprocess.run(["vvp", str(d / "sim")], capture_output=True,
                                 text=True, timeout=timeout, cwd=d)
        except subprocess.TimeoutExpired:
            return False, "vvp timed out", "sim"
        out = run.stdout
        if "ALL_PASS" in out:
            return True, "ok", None
        return False, out.strip()[-500:] or "no ALL_PASS", "sim"
    finally:
        shutil.rmtree(d, ignore_errors=True)


# ----------------------------------------------------------------- one run
def prompt_cg(t):
    return ("Write a complete C⏚ program for " + t["cg"] + ". The output is "
            f"`out push u{t['width']} q`. Make `loop()` write q every cycle. "
            f"Include exactly `properties {{ test: {{ q: {t['expected']} }} }}` so "
            "it self-checks. Start with a `package` line. Return ONLY the C⏚ "
            "code in a ```cg code block.")


def prompt_verilog(t):
    return ("Write a Verilog-2001 module with EXACTLY this interface:\n"
            f"  module {t['name']}(input clk, input rst_n, output reg [{t['width']-1}:0] q);\n"
            f"Behavior: while rst_n is low, q = {t['reset']}. On each rising edge "
            f"of clk with rst_n high, {t['rule']}. q holds the current value "
            "(registered output). Return ONLY the module in a ```verilog block.")


def run_one(t, lang, max_fix):
    p = prompt_cg(t) if lang == "cg" else prompt_verilog(t)
    system = CG_CONTEXT if lang == "cg" else None   # the kit's pack, C⏚ only
    messages = [{"role": "user", "content": p}]
    first_ok = None
    for attempt in range(max_fix + 1):
        try:
            reply = complete(system, messages)
        except Exception as e:
            return {"ok": False, "attempts": attempt + 1, "first_try": bool(first_ok),
                    "kind": "llm_error", "detail": str(e)[:120]}
        code = extract(reply)
        if lang == "cg":
            ok, detail, kind = verify_cg(code)
        else:
            ok, detail, kind = verify_verilog(t["name"], t["width"], t["expected"], code)
        if first_ok is None:
            first_ok = ok
        if ok:
            return {"ok": True, "attempts": attempt + 1, "first_try": bool(first_ok),
                    "kind": None}
        messages.append({"role": "assistant", "content": reply})
        messages.append({"role": "user",
                         "content": f"That failed verification ({kind}): {detail}\n"
                                    "Return corrected code in a code block."})
    return {"ok": False, "attempts": max_fix + 1, "first_try": bool(first_ok),
            "kind": kind, "detail": detail[:160]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fix", type=int, default=2, help="max fix iterations")
    ap.add_argument("--trials", type=int, default=1)
    ap.add_argument("--tasks", default="", help="comma substring filter")
    args = ap.parse_args()

    tasks = [t for t in TASKS if not args.tasks
             or any(s.strip().lower() in t["name"].lower()
                    for s in args.tasks.split(","))]
    print(f"model={MODEL}  fix_budget={args.fix}  trials={args.trials}  "
          f"tasks={len(tasks)}\n" + "=" * 74)
    agg = {"cg": {"first": 0, "final": 0, "att": 0, "n": 0, "kinds": {}},
           "verilog": {"first": 0, "final": 0, "att": 0, "n": 0, "kinds": {}}}
    print(f"{'task':10} {'lang':8} {'first':6} {'final':6} {'att':4} kind")
    for t in tasks:
        for lang in ("cg", "verilog"):
            for _ in range(args.trials):
                r = run_one(t, lang, args.fix)
                a = agg[lang]
                a["n"] += 1
                a["first"] += int(r["first_try"])
                a["final"] += int(r["ok"])
                a["att"] += r["attempts"]
                if not r["ok"]:
                    a["kinds"][r["kind"]] = a["kinds"].get(r["kind"], 0) + 1
                print(f"{t['name']:10} {lang:8} "
                      f"{'Y' if r['first_try'] else '·':6} "
                      f"{'Y' if r['ok'] else 'N':6} {r['attempts']:<4} "
                      f"{r.get('kind') or ''}")
    print("=" * 74)
    for lang in ("cg", "verilog"):
        a = agg[lang]
        n = max(a["n"], 1)
        print(f"{lang:8}  first-try {a['first']}/{a['n']} ({100*a['first']//n}%)  "
              f"after-loop {a['final']}/{a['n']} ({100*a['final']//n}%)  "
              f"avg attempts {a['att']/n:.1f}  fails={a['kinds']}")


if __name__ == "__main__":
    main()
