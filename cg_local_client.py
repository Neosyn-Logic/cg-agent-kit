#!/usr/bin/env python3
"""
cg_local_client.py — drive a local OpenAI-compatible model through the C⏚
tools, with no MCP host and no retraining.

This is the kit working end to end against your own GPU: it loads
`cg_context.md` as the system prompt, exposes cg_check / cg_simulate /
cg_generate_verilog as function-calling tools backed by the real Neosyn
compiler (the core functions in cg_mcp_server.py), and runs an agentic loop
so the model writes → checks → simulates → fixes until its C⏚ is correct.

Works with Ollama, vLLM, llama.cpp server, LM Studio, TGI — anything that
speaks /v1/chat/completions with tool calling.

Config (env):
  CG_LLM_URL    base URL    (default http://localhost:11434/v1)
  CG_LLM_MODEL  model name  (default qwen3.6:35b-a3b)
  CG_JAR        compiler jar (see cg_mcp_server.py)

Usage:
  python cg_local_client.py "Write a 4-bit counter that wraps, with a
      self-checking test for the first 6 values, and verify it simulates."
"""
import json
import os
import re
import sys
import urllib.request

import cg_mcp_server as cg

_CODE = re.compile(r"```(?:cg|c)?\s*\n(.*?)```", re.S)


def extract_code(text: str):
    """Pull the last ```cg ...``` block out of a model's final answer."""
    blocks = _CODE.findall(text or "")
    return blocks[-1].strip() if blocks else None

BASE = os.environ.get("CG_LLM_URL", "http://localhost:11434/v1").rstrip("/")
MODEL = os.environ.get("CG_LLM_MODEL", "qwen3.6:35b-a3b")
HERE = os.path.dirname(os.path.abspath(__file__))
CONTEXT = open(os.path.join(HERE, "cg_context.md")).read()

TOOLS = [
    {"type": "function", "function": {
        "name": "cg_check",
        "description": "Parse, scope and type-check C⏚ source without running it. "
                       "Returns {ok, diagnostics:[{file,line,message}], summary}.",
        "parameters": {"type": "object",
                       "properties": {"source": {"type": "string", "description": "the full .cg source"}},
                       "required": ["source"]}}},
    {"type": "function", "function": {
        "name": "cg_simulate",
        "description": "Run the fast bytecode simulator on C⏚ source. Returns "
                       "{ok, timed_out, diagnostics, output}. Iterate until ok is true.",
        "parameters": {"type": "object",
                       "properties": {"source": {"type": "string", "description": "the full .cg source"}},
                       "required": ["source"]}}},
    {"type": "function", "function": {
        "name": "cg_generate_verilog",
        "description": "Generate synthesizable Verilog once the program simulates. "
                       "Returns {ok, file_count, files} (file names only here).",
        "parameters": {"type": "object",
                       "properties": {"source": {"type": "string"}},
                       "required": ["source"]}}},
]


def _gen_names_only(args):
    r = cg.generate(args["source"])
    return {"ok": r["ok"], "file_count": r.get("file_count"),
            "files": list(r.get("files", {}).keys())}


DISPATCH = {
    "cg_check": lambda a: cg.check(a["source"]),
    "cg_simulate": lambda a: cg.simulate(a["source"]),
    "cg_generate_verilog": _gen_names_only,
}


def chat(messages, timeout=900):
    body = {"model": MODEL, "messages": messages, "tools": TOOLS, "stream": False}
    req = urllib.request.Request(BASE + "/chat/completions",
                                 data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.load(resp)["choices"][0]["message"]


def run(task, max_steps=10):
    messages = [{"role": "system", "content": CONTEXT},
                {"role": "user", "content": task}]
    last_sim_ok = False
    tool_calls_made = 0
    for step in range(1, max_steps + 1):
        m = chat(messages)
        messages.append({"role": "assistant",
                         "content": m.get("content") or "",
                         "tool_calls": m.get("tool_calls")})
        tcs = m.get("tool_calls") or []
        if not tcs:
            # The model answered without calling a tool. Don't take its word —
            # auto-verify the code it produced, and if it fails, hand the real
            # compiler output back and ask it to fix. This enforces the
            # write→verify→fix loop even for models that don't self-invoke tools.
            code = extract_code(m.get("content"))
            if not code:
                print(f"\n── step {step}: final answer, no code block ──")
                print((m.get("content") or "")[-600:])
                return {"sim_ok": last_sim_ok, "tool_calls": tool_calls_made, "steps": step}
            sim = cg.simulate(code)
            last_sim_ok = bool(sim["ok"])
            if sim["ok"]:
                outs = [l for l in sim["output"].splitlines() if "port" in l or "===" in l]
                print(f"  step {step}: auto-verify -> SIMULATES ✓  | " + " ".join(outs[:4]))
                return {"sim_ok": True, "tool_calls": tool_calls_made, "steps": step}
            problem = (sim["diagnostics"] or sim["output"])
            print(f"  step {step}: auto-verify -> FAILS  | {str(problem)[:160]}")
            messages.append({"role": "user",
                             "content": "Your program did not pass the compiler. "
                             + ("Diagnostics: " + json.dumps(sim["diagnostics"])
                                if sim["diagnostics"]
                                else "It timed out or asserted (often a `push` output "
                                     "written only on some cycles — write it every cycle). "
                                     "Simulator output: " + sim["output"][:800])
                             + " Return corrected C⏚ in a ```cg block."})
            continue
        for tc in tcs:
            name = tc["function"]["name"]
            try:
                args = json.loads(tc["function"]["arguments"])
            except (json.JSONDecodeError, TypeError):
                args = {"source": tc["function"].get("arguments", "")}
            tool_calls_made += 1
            result = DISPATCH.get(name, lambda a: {"error": f"unknown tool {name}"})(args)
            ok = result.get("ok")
            if name == "cg_simulate":
                last_sim_ok = bool(ok)
            extra = ""
            if result.get("diagnostics"):
                extra = " | first: " + str(result["diagnostics"][0])
            elif name == "cg_simulate" and ok:
                outs = [l for l in result.get("output", "").splitlines() if "port" in l or "===" in l]
                extra = " | " + " ".join(outs[:4])
            print(f"  step {step}: {name} -> ok={ok}{extra}")
            messages.append({"role": "tool", "tool_call_id": tc.get("id", name),
                             "content": json.dumps(result)[:4000]})
    print("\n── hit max_steps without a final answer ──")
    return {"sim_ok": last_sim_ok, "tool_calls": tool_calls_made, "steps": max_steps}


if __name__ == "__main__":
    task = sys.argv[1] if len(sys.argv) > 1 else (
        "Write a C⏚ task for a 4-bit counter that counts up and wraps at 16. "
        "It outputs the count on a push port. Add a `test` property that checks "
        "the first six values. Use the tools to check and simulate it, and fix "
        "any errors until it simulates cleanly.")
    print(f"model={MODEL}  url={BASE}\nTASK: {task}\n" + "=" * 70)
    verdict = run(task)
    print("=" * 70)
    print(f"VERDICT: simulated_ok={verdict['sim_ok']}  "
          f"tool_calls={verdict['tool_calls']}  steps={verdict['steps']}")
    sys.exit(0 if verdict["sim_ok"] else 1)
