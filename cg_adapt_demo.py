#!/usr/bin/env python3
"""
cg_adapt_demo.py — seed-and-adapt: hand the model a VERIFIED C⏚ base and have it
adapt it to a new kernel, with the real compiler in the loop.

Why: models can't reliably *synthesize* a hard fixed-point datapath from scratch
(in C⏚ *or* Verilog), but they reliably *adapt* a verified base — preserving the
parts they can't invent (the Q16.16 MAC, the task/network/monitor structure) and
changing only the dataflow. This is the same recipe that works for accelerator
porting generally: start from known-good code, let the compiler gate each step.

Two modes:
  python cg_adapt_demo.py --target weighted_diff      # one adapt, verbose
  python cg_adapt_demo.py --matrix                     # robustness sweep

Config (env): CG_LLM_MODEL, CG_OLLAMA_URL, CG_JAR (see cg_local_client.py).
Verification: cg_mcp_server.simulate (bytecode sim) + an INDEPENDENT Q16.16
reference computed here (the model can't pass by hardcoding a wrong self-check).
"""
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cg_mcp_server as cg
from cg_vs_verilog_eval import complete, extract

CG_CONTEXT = open(os.path.join(HERE, "cg_context.md")).read()
BASE_DOT = open(os.path.join(HERE, "examples", "DotProduct.cg")).read()

Q = 1 << 16
def q(v): return int(round(v * Q))

# Shared Q16.16 input vectors (length 4) used by the targets below.
A = [2.0, 4.0, 6.0, 8.0]
B = [1.0, 2.0, 3.0, 4.0]
W = [1.5, 1.0, 1.0, 1.0]
ALPHA, K = 2.0, 3.0

def _fp_dot(xs, ys):  # reference computed the SAME way the hardware does (>>16 per term)
    return sum((q(x) * q(y)) >> 16 for x, y in zip(xs, ys))

# Each target: a human spec (what to compute) + an independent Q16.16 reference.
TARGETS = {
    "weighted_diff": {
        "desc": "weighted sum of differences:  out = sum_i  w[i] * (a[i] - b[i])",
        "inputs": {"w": W, "a": A, "b": B},
        "ref": lambda: sum((q(w) * (q(a) - q(b))) >> 16 for w, a, b in zip(W, A, B)),
    },
    "sum_of_squares": {
        "desc": "sum of squares:  out = sum_i  a[i] * a[i]",
        "inputs": {"a": A},
        "ref": lambda: _fp_dot(A, A),
    },
    "scaled_dot": {
        "desc": f"scaled dot product:  out = k * sum_i a[i]*b[i]   with k = {K} (Q16.16)",
        "inputs": {"a": A, "b": B, "k": [K]},
        "ref": lambda: (q(K) * _fp_dot(A, B)) >> 16,
    },
    "saxpy_reduce": {
        "desc": f"SAXPY then reduce:  out = sum_i (alpha*x[i] + y[i])  with alpha = {ALPHA}",
        "inputs": {"alpha": [ALPHA], "x": A, "y": B},
        "ref": lambda: sum(((q(ALPHA) * q(x)) >> 16) + q(y) for x, y in zip(A, B)),
    },
    "l2_norm_sq": {
        "desc": "squared Euclidean distance:  out = sum_i (a[i] - b[i])^2   "
                "(this is the r^2 term inside an n-body force calc)",
        "inputs": {"a": A, "b": B},
        "ref": lambda: sum(((q(a) - q(b)) * (q(a) - q(b))) >> 16 for a, b in zip(A, B)),
    },
}


def _fmt_inputs(inputs):
    return "\n".join(f"  {k} = {[q(v) for v in vs]}" for k, vs in inputs.items())


def make_prompt(target, with_base, terse):
    t = TARGETS[target]
    head = (f"Write a complete C⏚program for this kernel: {t['desc']}.\n"
            f"All values are Q16.16 signed fixed-point (value<<16). Inputs:\n"
            f"{_fmt_inputs(t['inputs'])}\n")
    rules = ("Structure it as a task plus a `<Name>_test` network whose inline monitor "
             "reads the output and does `print(\"result = \", r, \"\\n\")`, then sets "
             "finished=true. Use `properties { test: { terminate: \"monitor.finished\" } }`. "
             "Do NOT assert (an external checker verifies the value). Start with a "
             "`package` line. Return ONLY the C⏚code in a ```cg block.\n")
    if terse:
        rules = ("Make a task + a `<Name>_test` network with a monitor that prints "
                 "`result = <value>`. Return ONLY the ```cg code.\n")
    base = ("\n=== A VERIFIED, WORKING C⏚bASE TO ADAPT (keep its fixed-point MAC "
            "and structure; change only the math) ===\n" + BASE_DOT) if with_base else ""
    return head + rules + base


def _entity_for(code):
    return cg._test_entity(code)


def verify(target, code):
    """Simulate (compiler-in-loop) + compare the printed result to the reference."""
    r = cg.simulate(code)
    if not r["ok"]:
        kind = "compile" if r["diagnostics"] else ("timeout" if r.get("timed_out") else "sim")
        detail = (str(r["diagnostics"][:2]) if r["diagnostics"] else r["output"][-300:])
        return False, kind, detail
    m = re.search(r"result\s*=\s*(0x[0-9a-fA-F]+|-?\d+)", r["output"])
    if not m:
        return False, "no_value", r["output"][-200:]
    val = int(m.group(1), 0)
    ref = TARGETS[target]["ref"]()
    if abs(val - ref) <= 16:   # small >>16 rounding slack
        return True, "ok", f"result={val} == ref {ref}"
    return False, "wrong_value", f"got {val}, expected ~{ref}"


def run(target, with_base=True, with_ctx=True, terse=False, max_fix=2, verbose=False):
    system = CG_CONTEXT if with_ctx else None
    msgs = [{"role": "user", "content": make_prompt(target, with_base, terse)}]
    for attempt in range(1, max_fix + 2):
        try:
            reply = complete(system, msgs, timeout=400)
        except Exception as e:
            return {"ok": False, "attempts": attempt, "kind": "llm_error", "detail": str(e)[:80]}
        code = extract(reply)
        ok, kind, detail = verify(target, code)
        if verbose:
            print(f"    attempt {attempt}: {'PASS' if ok else 'FAIL ' + kind}  {detail[:120]}")
        if ok:
            return {"ok": True, "attempts": attempt, "kind": None, "code": code}
        msgs += [{"role": "assistant", "content": reply},
                 {"role": "user", "content": f"That failed ({kind}): {detail}\nReturn corrected C⏚code."}]
    return {"ok": False, "attempts": max_fix + 1, "kind": kind, "detail": detail[:120], "code": code}


def matrix(max_fix=2):
    """Robustness sweep: (1) does the base help? (2) which targets adapt cleanly?
    (3) does a terse prompt still work? One row per condition."""
    print(f"model={os.environ.get('CG_LLM_MODEL','qwen3.6:35b-a3b')}  max_fix={max_fix}")
    print("=" * 78)
    rows = []
    print("-- ablation: target=weighted_diff, vary what the model is given --")
    for label, kw in [("base+ctx", {}), ("base, no ctx", {"with_ctx": False}),
                      ("ctx, no base", {"with_base": False}), ("neither", {"with_base": False, "with_ctx": False})]:
        r = run("weighted_diff", max_fix=max_fix, **kw)
        rows.append((f"weighted_diff [{label}]", r)); _print_row(rows[-1])
    print("-- targets: vary the kernel, base+ctx --")
    for tgt in ("sum_of_squares", "scaled_dot", "saxpy_reduce", "l2_norm_sq"):
        r = run(tgt, max_fix=max_fix); rows.append((f"{tgt} [base+ctx]", r)); _print_row(rows[-1])
    print("-- prompt style: terse vs the detailed default (l2_norm_sq, base+ctx) --")
    r = run("l2_norm_sq", terse=True, max_fix=max_fix); rows.append(("l2_norm_sq [terse]", r)); _print_row(rows[-1])
    print("=" * 78)
    passes = sum(1 for _, r in rows if r["ok"])
    print(f"PASS {passes}/{len(rows)}")
    return rows


def _print_row(row):
    label, r = row
    print(f"  {label:34} {'PASS' if r['ok'] else 'FAIL':5} "
          f"attempts={r['attempts']}  {r.get('kind') or ''}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", choices=list(TARGETS), help="run one adapt, verbose")
    ap.add_argument("--matrix", action="store_true", help="run the robustness sweep")
    ap.add_argument("--no-base", action="store_true")
    ap.add_argument("--no-ctx", action="store_true")
    ap.add_argument("--terse", action="store_true")
    ap.add_argument("--fix", type=int, default=2)
    args = ap.parse_args()
    if args.matrix:
        matrix(max_fix=args.fix)
    else:
        tgt = args.target or "weighted_diff"
        print(f"=== adapt {BASE_DOT.splitlines()[3] if False else 'DotProduct base'} -> {tgt} ===")
        print(f"target: {TARGETS[tgt]['desc']}\nreference (Q16.16): {TARGETS[tgt]['ref']()}")
        r = run(tgt, with_base=not args.no_base, with_ctx=not args.no_ctx,
                terse=args.terse, max_fix=args.fix, verbose=True)
        print(f"\n{'PASS' if r['ok'] else 'FAIL'} in {r['attempts']} attempt(s)")
        if r.get("code"):
            print("\n--- final C⏚code ---\n" + r["code"])
