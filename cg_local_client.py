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

from cg_agent_kit import cg_mcp_server as cg

_CODE = re.compile(r"```(?:cg|c)?\s*\n(.*?)```", re.S)


def extract_code(text: str):
    """Pull the last ```cg ...``` block out of a model's final answer."""
    blocks = _CODE.findall(text or "")
    return blocks[-1].strip() if blocks else None

def resolve_endpoint(style="openai"):
    """Resolve the model endpoint from EITHER env var, in EITHER notation.

    The kit grew two variables pointing at the same server in different dialects
    -- CG_LLM_URL (OpenAI-style `/v1`) here, CG_OLLAMA_URL (native `/api/chat`)
    in the eval and adapt harnesses -- so setting "the" URL configured half the
    kit and silently left the rest on localhost defaults. That cost a session
    real time on 2026-08-20. Accept both, convert between them, and let one
    export configure everything.

    `style` is the dialect the CALLER speaks: 'openai' wants a base ending /v1,
    'native' wants a full /api/chat URL."""
    raw = (os.environ.get("CG_LLM_URL") or os.environ.get("CG_OLLAMA_URL")
           or "http://localhost:11434")
    root = raw.rstrip("/")
    for suffix in ("/api/chat", "/v1/chat/completions", "/v1"):
        if root.endswith(suffix):
            root = root[: -len(suffix)]
            break
    root = root.rstrip("/")
    return root + ("/v1" if style == "openai" else "/api/chat")


BASE = resolve_endpoint("openai")
MODEL = os.environ.get("CG_LLM_MODEL", "qwen3.6:35b-a3b")
HERE = os.path.dirname(os.path.abspath(__file__))
# The docs ship INSIDE the package; HERE is the repo root in a checkout,
# so resolve through the package rather than beside this file.
from cg_agent_kit import cg_mcp_server as _cg
CONTEXT = (_cg._HERE / "cg_context.md").read_text()

TOOLS = [
    {"type": "function", "function": {
        "name": "cg_lint",
        "description": "Static checks for C⏚ that COMPILES but is still wrong -- above "
                       "all a `test:` fixture that drives inputs yet compares no output, "
                       "which passes even against a dead design. Free and instant (no "
                       "compiler); run it on every draft BEFORE cg_check. Returns "
                       "{ok, findings:[{rule,line,severity,message,fix}]}.",
        "parameters": {"type": "object",
                       "properties": {"source": {"type": "string", "description": "the full .cg source"}},
                       "required": ["source"]}}},
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
    "cg_lint": lambda a: cg.lint(a["source"]),
    "cg_check": lambda a: cg.check(a["source"]),
    "cg_simulate": lambda a: cg.simulate(a["source"]),
    "cg_generate_verilog": _gen_names_only,
}


def _roster():
    """This client's OWN roster, read off the tool schemas it actually sends.
    It exposes a deliberate 4-tool subset of the MCP server, so pushing the
    server's 13 would name tools this loop cannot dispatch."""
    return [{"name": t["function"]["name"],
             "summary": t["function"]["description"].split(".")[0].strip()}
            for t in TOOLS if t["function"]["name"] in DISPATCH]


def dispatch(name, args):
    """Run one tool call. A name that is not in DISPATCH gets the ROSTER back,
    not `unknown tool X`: a small model that has invented a name loops on it
    otherwise, and the one thing it needs is the list of real ones."""
    fn = DISPATCH.get(name)
    if fn is None:
        return cg.unknown_tool(name, known=_roster())
    return fn(args)


def _tool_content(result, budget=8000):
    """Serialise a tool result for the model without corrupting it.

    The old `json.dumps(result)[:4000]` truncated the SERIALISED string, so any
    result over the budget reached the model as invalid JSON -- and results grew
    when we started pushing lint findings and a seed example. Trim the big,
    optional payloads FIRST (output, then the pushed source), keeping the small
    actionable ones (diagnostics, hint, warning) intact, and only then serialise."""
    r = dict(result)
    for field in ("output", ):
        if len(json.dumps(r)) <= budget:
            break
        if isinstance(r.get(field), str) and len(r[field]) > 600:
            r[field] = r[field][:600] + " …[truncated]"
    if len(json.dumps(r)) > budget and isinstance(r.get("suggestion"), dict):
        sug = dict(r["suggestion"])
        # A truncated example is a BROKEN example -- drop it whole rather than
        # hand the model code that cannot compile.
        sug.pop("source", None)
        sug["source_omitted"] = "too large for this turn; call cg_example"
        r["suggestion"] = sug
    out = json.dumps(r)
    return out if len(out) <= budget else json.dumps(
        {"ok": r.get("ok"), "diagnostics": (r.get("diagnostics") or [])[:3],
         "note": "result truncated"})


def chat(messages, timeout=900):
    body = {"model": MODEL, "messages": messages, "tools": TOOLS, "stream": False}
    req = urllib.request.Request(BASE + "/chat/completions",
                                 data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.load(resp)["choices"][0]["message"]


# see cg_mcp_server.example(): unrelated queries still score 4-5 on incidental tag
# overlap, so the bar sits well above that. Tunable so an experiment can switch
# seeding OFF (set it very high) without editing code -- seeding and pushed
# findings are separate effects and a measurement must be able to isolate them.
SEED_MIN_SCORE = int(os.environ.get("CG_SEED_MIN_SCORE", "10"))


def _seed_for(task):
    """A VERIFIED base for this task, or None if nothing matches confidently.

    The 2026-08-20 probe showed models that receive a verified base first write
    legal C(g), while the same models from scratch loop on one error. This client
    already seeds cg_context.md, so the LANGUAGE DOCS are not the difference --
    concrete working code is.

    Gated on score because a WRONG seed is worse than none: it is code the model
    will copy. On this corpus an unrelated query still scores 4 on incidental tag
    overlap, so the bar sits well above that."""
    try:
        hit = cg.example(task, k=1)
    except Exception:
        return None
    if not hit.get("ok") or hit.get("score", 0) < SEED_MIN_SCORE:
        return None
    if not hit.get("source"):
        return None
    return (f"Before you start: here is a VERIFIED, simulated C⏚ program from the "
            f"library ({hit['name']}) that is close to this task. Adapt it rather "
            f"than writing from scratch — keep its structure, ports and `test:` "
            f"block shape, and change only what the task requires.\n\n"
            f"```cg\n{hit['source']}```")


def run(task, max_steps=10):
    messages = [{"role": "system", "content": CONTEXT}]
    seed = _seed_for(task)
    if seed:
        messages.append({"role": "system", "content": seed})
        print(f"  [seeded with a verified base]")
    messages.append({"role": "user", "content": task})
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
            result = dispatch(name, args)
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
                             "content": _tool_content(result)})
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
