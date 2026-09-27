# neosyn-fpga-mcp

<!-- mcp-name: io.neosyn/neosyn-fpga-mcp -->

**An MCP server that hands the C⏚ FPGA toolchain to an AI agent.** The model
writes hardware; the server compiles, simulates and synthesis-checks it against
the real compiler, and hands back structured diagnostics the model can act on.

That is the difference worth caring about. An LLM asked for Verilog will
confidently emit something that does not build, does not synthesize, or silently
folds away to nothing. Here every step is judged by the same compiler a human
uses.

Two parts work together:

1. **`cg_context.md`** — a knowledge pack. Load it as the system prompt and the
   model can write plausible C⏚: the mental model, types, ports,
   structs/enums/generics, the standard library, and the gotchas that sink first
   drafts.
2. **the MCP server** — the compiler as tools, so the model verifies its own
   output instead of recalling it.

Knowledge gives a good first draft; the compiler in the loop makes it right.
Both are model-agnostic — any stdio-MCP host (Claude Desktop, Claude Code,
Cursor, Cline) works, and the context pack works with any LLM at all.

**Why not fine-tune?** C⏚ is a niche language with little public code, and it
gains features every release. A fine-tuned model is expensive and goes stale.
In-context knowledge plus a verification loop costs nothing to retrain, tracks
the language as the compiler evolves, and converges by *running* code rather
than recalling it.

## Install

```bash
pip install neosyn-fpga-mcp
```

Then point it at a C⏚ compiler jar:

```bash
export CG_JAR=/path/to/cg-language-server.jar
```

Two ways to get that jar:

- **Open source** — a prebuilt jar from
  [cg-compiler releases](https://github.com/Neosyn-Logic/cg-compiler/releases/latest),
  or build it from source.
- **Commercial** — the jar inside an installed
  [Neosyn C⏚ extension](https://neosyn.io/download), which adds the fast
  bytecode simulator and VHDL output.
  It needs your licence file: set `NEOSYN_CG_LICENSE` to it, or keep it at the
  default path the extension uses. Without one, every tool reports the licence
  problem instead of running.

`cg_capabilities` reports which one you have and what it can do, probed rather
than assumed.

## Requirements

- **Python 3.10+**
- **Java 17 or newer** on `PATH` — the jar's bytecode targets 17.
- **Optional:** `yosys` on `PATH` for `cg_synth` (override with `$YOSYS`);
  `iverilog` for `cg_simulate(simulator='iverilog')`. Neither is needed for
  `cg_check`, `cg_generate_verilog`, or the bytecode simulator.

Smoke-test the verification core without an MCP client:

```bash
python3 - <<'EOF'
from neosyn_fpga_mcp import cg_mcp_server as cg
print(cg.simulate("package d;\ntask T { properties { test: { v:[1,2,3] } }\n"
                  "  out push u8 v; u8 c; void setup(){c=0;}\n"
                  "  void loop(){c=c+1; v.write(c);} }"))
EOF
```

## Connect it to an MCP host

Add a server entry. Use absolute paths.

```json
{
  "mcpServers": {
    "cg": {
      "command": "neosyn-fpga-mcp",
      "args": [],
      "env": {
        "CG_JAR": "/abs/path/to/cg-language-server.jar"
      }
    }
  }
}
```

The same `command`/`args`/`env` shape works for Claude Desktop, Claude Code,
Cursor, Cline and other stdio-MCP hosts.

Then **load `cg_context.md` as the system prompt** (or paste it at the top of
the conversation). The model now knows the language *and* can verify it.

## Tools the server exposes

13 tools. Every tool that takes source accepts `source` (a C⏚ string) and an
optional `extra_files` map (`{"Defs.cg": "..."}`) for imported bundles/tasks.

These are the only names that exist, and the server says so rather than hoping
you read this table: a call to a tool that does not exist comes back with the
whole list and the closest real name (`cg_compile` → "did you mean `cg_check`?"),
`cg_capabilities` carries the list, and the first call of a session carries it
once. The list is generated from the tool
registry, so it cannot drift out of step with the table below.

| Tool | Params (besides `source` / `extra_files`) | Returns | When to use it |
|------|--------------------------------------------|---------|----------------|
| `cg_check` | — | `{ok, diagnostics:[…], warnings:[…], summary}` | After `cg_lint`, on any draft — fix every diagnostic before simulating. `warnings` carries validator findings the compiler accepts but objects to (`bool == 1`, assigning to a `const`): `ok` stays true because the program does compile, and the `summary` says so, because `ok` is the field that gets acted on. Needs a compiler ≥ 2.10.0 — older ones report nothing here. |
| `cg_simulate` | `timeout=60`, `simulator='bytecode'` | `{ok, simulator, timed_out, diagnostics, output}` | The ground-truth correctness check. `output` holds port values + `print()` lines; a `properties { test: {...} }` block self-checks. Iterate until `ok`. |
| `cg_generate_verilog` | `target='verilog'`, `output_dir=None` | `{ok, file_count, files:{path:content}}` (+ `{output_dir, written}` when persisted) | After simulate passes, to hand off RTL. `target` is `'verilog'` or `'vhdl'`. Pass `output_dir` (relative to `$PROJECT_ROOT`) to write the files to disk and keep them. |
| `cg_synth` | `top=None`, `timeout=180`, `flow='generic'` | `{ok, verdict, top, flow, cells, arith_ops, latches, warnings, stat, problems, output}` | The strongest correctness signal — yosys-synthesizes the Verilog. `verdict` ∈ REAL / FOLDED (constant-folded — inputs weren't on ports) / SUSPECT (latches inferred) / ERROR, so you can't confabulate success. `warnings` explains a degenerate datapath or inferred latch. |
| `cg_capabilities` | — | `{ok, jar, jar_present, bytecode_simulator:{available,reason,detail}, simulators:[…], tools:{…}, advice}` | What this host can actually do, **probed rather than assumed**. The fast bytecode simulator ships with the commercial distribution and is absent from the open-source compiler, so any flat claim about it is wrong in one of the two environments — call this before deciding how to verify. |
| `cg_scaffold` | `kind='task'`, `name`, `package`, `inputs`, `outputs`, `verify=True` | `{ok, kind, source, holes:[{line,text}], verified:{check,simulate}, message}` | **Start here when writing new C⏚ from a blank file.** Returns a complete, COMPILING, self-checking skeleton with the datapath left as `>>> FILL IN` holes, verified green before you get it — so any later failure is your edit. `kind` ∈ `task` (a `sync` task whose `test:` block value-checks every output cycle by cycle — the default and the strongest) / `fsm` / `stream` / `network` / `generic`. `inputs`/`outputs` are `"name:type"` strings, honoured for `task` and `stream`. Complements `cg_example`: scaffold when writing something new, example when a validated implementation of the kernel already exists. |
| `cg_example` | `pattern=''`, `k=1` | no pattern → `{ok, index:[{name,kind,use_when,tags}]}`; a pattern → `{ok, name, kind, source, …, runners_up:[…]}` | Scored lazy lookup into the validated-code dictionary (NOT search). Specificity-weighted, so `1/sqrt`→RSqrt but `sqrt`→FixedSqrt; returns 1-2 runners-up to self-correct. `k>1` returns more sources for composition. |
| `cg_lint` | — | `{ok, findings:[{rule,line,severity,message,fix}]}` | Static checks for code the compiler **accepts and is still wrong**. Chiefly a `test:` fixture that drives inputs but compares no output — it passes even with a dead design. No jar and no simulator, so run it on every draft before `cg_check`, and again before claiming a design is verified. |
| `cg_suggest_for_error` | `message` | `{ok, recipe, hint, source}` | Map a compiler rejection to the recipe with the fix pattern (div/shift-by-variable → Recip; data-dependent loop bound → SeqDiv). `cg_check`/`cg_simulate`/`cg_generate_verilog` auto-attach this as a `suggestion` when a diagnostic matches. |
| `cg_report` | `report_dir='fpga/build'`, `schematics=True` | `{ok, report, kernels, sim_ok, message}` | Finalize the FPGA report: renders `<report_dir>/report.html` (synthesis table with the REAL/FOLDED/SUSPECT verdict and cell counts, the simulation PASS/FAIL, the generated-Verilog list, and best-effort datapath SVGs). Does **no** synthesis — the rows accumulate as a byproduct of passing the same `report_dir` to `cg_synth` and `cg_simulate`. |
| `cg_fsm` | `task=None` | `{ok, diagnostics, fsm}` | Confirm a task's compiled state machine has the intended states/transitions. |
| `cg_graph` | `network=None` | `{ok, diagnostics, graph}` | Confirm a network's compiled wiring (instances, ports with widths/interfaces, connections). |
| `cg_docs` | `topic=''` | no topic → `{ok, topics:[{topic,description}]}`; a topic → `{ok, topic, description, content}` | Fetch a markdown knowledge doc on demand. `context` = the core C⏚ language pack; `riscv` = the worked RV32I CPU reference (loadable single-cycle core + reusable patterns for CPU-shaped hardware: barrel shifter, signed/unsigned widening, sub-word load/store, boot-stream program loading, testbench capture). Read `riscv` when building a processor/decoder/datapath/stack machine. |

### Choosing a backend

Two tools take a backend selector:

- **`cg_simulate(source, simulator=…)`** — which simulator runs the design:
  - `'bytecode'` *(default)* — the compiler's fast bytecode simulator. No HDL
    toolchain needed; a `properties { test: {...} }` block self-checks.
    `cg_simulate(src)` or `cg_simulate(src, simulator="bytecode")`.
  - `'iverilog'` — generate Verilog + a testbench and run Icarus Verilog
    (`vvp`), a Verilog-level cross-check. A testbench is emitted **only for a
    network whose name contains `Test` with a capital T** (e.g.
    `network TestFoo`); a lowercase `_test` network drives the bytecode sim's
    `test` property only, not iverilog. Needs `iverilog` on `PATH`.
    `cg_simulate(src, simulator="iverilog")`.
  - `'verilator'` — accepted for forward-compat but reported unavailable unless
    the `verilator` binary is installed. `cg_simulate(src, simulator="verilator")`.

- **`cg_synth(source, flow=…)`** — which yosys synthesis flow runs:
  - `'generic'` *(default)* — portable synthesizability check (`synth`).
    `cg_synth(src)` or `cg_synth(src, flow="generic")`.
  - a vendor FPGA family — `'ice40'`, `'ecp5'`, `'xilinx'`, `'gowin'`,
    `'intel'` — maps to that part's primitives (LUTs/BRAM/DSP).
    `cg_synth(src, flow="ice40")`.

  `top` defaults to the first non-testbench task/network (the synthesizable
  DUT); pass it when a file holds several designs. Override the yosys binary
  with `$YOSYS`.

## How the model should use it

1. Draft C⏚ (always starting with `package`).
2. `cg_lint` → free and instant; catches the mistakes the compiler will happily
   accept, above all a `test:` block that checks nothing.
3. `cg_check` → fix every diagnostic, and read `warnings`: those are the
   compiler's own objections to code it will nonetheless accept.
4. `cg_simulate` → confirm `ok: true` and that the output matches intent.
5. `cg_generate_verilog` once it simulates, to hand off RTL.
6. `cg_synth` (optional) → confirm the Verilog maps to real hardware
   (`ok: true`, a sensible `cells` count, no `problems`).

Step 2 exists because steps 3–4 can BOTH pass on a design that does nothing: a
fixture with no output vector is green against a dead DUT. `cg_lint` is the only
step that catches that, and it costs nothing to run.

The loop in steps 2–3 is the point: the model writes, the compiler judges, the
model fixes. `cg_context.md` ends with the same protocol so the model follows
it even without separate instruction.

### The loop, end to end

```python
from neosyn_fpga_mcp import cg_mcp_server as cg

src = '''package com.example.demo;
task Counter {
    properties { test: { value: [1, 2, 3] } }
    out push u8 value;
    u8 count;
    void setup() { count = 0; }
    void loop()  { count = count + 1; value.write(count); }
}'''

cg.check(src)                              # {'ok': True, 'diagnostics': [], ...}
cg.simulate(src)                           # {'ok': True, 'simulator': 'bytecode', ...}
cg.generate(src, output_dir="build/v")     # {'ok': True, 'file_count': N, 'written': [...]}
cg.synth(src, flow="ice40")                # {'ok': True, 'top': 'Counter', 'cells': ..., 'problems': []}
```

Through the MCP tools the same calls are `cg_check` → `cg_simulate` →
`cg_generate_verilog` → `cg_synth`. Draft, then walk down the list, fixing
diagnostics at each gate; `cg_synth` is the final hardware gate.

## Seed-and-adapt: start from a verified base

Knowledge + verification gets a model surprisingly far, but there's a ceiling:
for a genuinely hard fixed-point datapath (e.g. an n-body force kernel with a
`1/r²·√r²` term), a model asked to write it *from scratch* flails — in C⏚ **and**
in Verilog. The reliable pattern is **seed-and-adapt**: hand the model a small,
**verified** base and have it change only the dataflow, keeping the parts it
can't invent (the Q16.16 multiply-accumulate, the task/network/monitor shape).

Call **`cg_example(pattern)`** to fetch one. This is a **curated dictionary of
validated code with scored lazy access** (not free-form search): no pattern
returns the index; a name or intent (`"1/sqrt"`, `"distance"`, `"divide a by b"`,
…) returns the single best-matching source plus 1-2 runners-up so the model can
self-correct. Matching is specificity-weighted, so `"1/sqrt"`→RSqrt while a bare
`"sqrt"`→FixedSqrt. When the compiler *rejects* something,
`cg_suggest_for_error(msg)` points at the recipe with the synthesizable pattern.

`examples/` holds the verified entries — every one simulates, generates Verilog,
and passes yosys synth. `kind` splits the reusable **primitives** (Recip, Divide,
SeqDiv, FixedSqrt, RSqrt, SqrDist, DotProduct, Fir, Integ, Distance, Counter)
from application **examples** (Force, GalaxyForce — n-body composition). Full
table with `use_when`/tags/cell counts in **`examples/RECIPES.md`**. A primitive
whose demo drives constant inputs (DotProduct, FixedSqrt, Distance) reports
`cg_synth` `verdict: FOLDED` — drive it with `in push` ports (as SqrDist does) so
the datapath survives.

See `cg_adapt_demo.py` in the
[repository](https://github.com/Neosyn-Logic/cg-agent-kit) to watch the
seed-and-adapt loop run end to end, and `EVAL.md` for how C⏚ and Verilog write
rates were measured on small tasks — including what that measurement does *not*
show.

## Documentation

- [Setup and the full tool reference](https://neosyn.io/docs/agent-kit)
- [Installing C⏚](https://neosyn.io/docs/install) — the extension and the CLI
- [Licensing](https://neosyn.io/pricing)

## The older name

This project was published as `cg-agent-kit` up to 1.0.0; "cg" is our shorthand
for C⏚ and meant nothing to anyone searching for an FPGA tool. On PyPI that name
is now a shim that installs this package, and inside the package
`python -m cg_agent_kit.cg_mcp_server` and the `cg-mcp-server` command both
still resolve — so existing instructions and host configs keep working. New
installs should use `neosyn-fpga-mcp`.

## License

MIT. Copyright (c) 2026 Neosyn.

The software is provided **"as is", without warranty of any kind**, express or
implied, including but not limited to the warranties of merchantability, fitness
for a particular purpose and noninfringement. In no event shall the authors or
copyright holders be liable for any claim, damages or other liability, whether
in an action of contract, tort or otherwise, arising from, out of or in
connection with the software or the use or other dealings in the software. The
full text ships with the package as `LICENSE`.

C⏚, Cg and Neosyn are marks of Neosyn. The C⏚ compiler is a separate work under
its own licence — see [neosyn.io/open](https://neosyn.io/open).
