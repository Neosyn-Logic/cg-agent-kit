# C⏚ Agent Kit

> **Renamed.** This was `cg-agent-kit` up to 1.0.0. "cg" is our shorthand for C⏚
> and meant nothing to anyone searching for an FPGA tool. `pip install cg-agent-kit`
> still works — it is a shim that installs this package — and
> `python -m cg_agent_kit.cg_mcp_server` still resolves, so existing MCP host
> configs keep working. New installs should use `neosyn-fpga-mcp`.

Make any LLM write **C⏚ (Cg)** instead of Verilog — **without retraining the
model.** The kit has two parts that work together:

1. **`cg_context.md`** — a paste-anywhere knowledge pack. Load it as the
   model's system prompt and it can write plausible C⏚: the mental model,
   types, ports, structs/enums/generics, the standard library, and the
   gotchas that otherwise sink first drafts.
2. **`cg_mcp_server.py`** — the Neosyn compiler exposed as MCP tools. The model
   *checks, simulates, and generates Verilog* against the real compiler and
   self-corrects. This is what makes the output actually correct despite the
   model having almost no C⏚ in its training data.

Knowledge gives a good first draft; the compiler-in-the-loop makes it right.
Both are model-agnostic — any MCP-capable host (Claude Desktop/Code, Cursor,
Cline, …) works, and the context pack works with any LLM at all.

## Why this instead of fine-tuning

C⏚ is a niche language with little public code, and it gains features every
release. A fine-tuned model is expensive and goes stale. In-context knowledge
plus a verification loop costs nothing to retrain, tracks the language as the
compiler evolves, and converges on correct code by *running* it rather than
recalling it.

## Tools the server exposes

13 tools. Every tool that takes source accepts `source` (a C⏚ string) and an
optional `extra_files` map (`{"Defs.cg": "..."}`) for imported bundles/tasks.

These are the only names that exist, and the server says so rather than hoping
you read this table: a call to a tool that does not exist comes back with the
whole list and the closest real name (`cg_compile` → "did you mean `cg_check`?"),
`cg_capabilities` carries the list, and the first call of a session carries it
once. The list is generated from the tool registry, so it cannot drift out of
step with the table below — `TestNoStaleToolNames` and
`TestStaticRostersMatchTheRegistry` fail if it does.

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

## Prerequisites

- **Java 21** on `PATH`.
- The **`cg-language-server.jar`**. Default location:
  `~/neosyn/neosyn-studio/releng/lsp-server/target/cg-language-server.jar`.
  Build it if missing: `cd releng/lsp-server && mvn package -DskipTests`.
  Point elsewhere with the `CG_JAR` environment variable.
- A dev license is assumed via `NEOSYN_CG_DEV=1` (the server sets it by
  default).
- **Optional, per backend:** `yosys` on `PATH` for `cg_synth` (override the
  binary with `$YOSYS`); `iverilog` (Icarus Verilog) on `PATH` for
  `cg_simulate(simulator='iverilog')`. Neither is needed for the default
  bytecode simulator or for `cg_check` / `cg_generate_verilog`.

## Install

```bash
pip install neosyn-fpga-mcp
```

Then point it at a built C⏚ compiler jar (download the prebuilt jar from
[cg-compiler releases](https://github.com/Neosyn-Logic/cg-compiler/releases/latest),
or build from source):

```bash
export CG_JAR=/path/to/cg-language-server.jar
```

Smoke-test the verification core without an MCP client:

```bash
python3 - <<'PY'
from neosyn_fpga_mcp import cg_mcp_server as cg
print(cg.simulate("package d;\ntask T { properties { test: { v:[1,2,3] } }\n"
                  "  out push u8 v; u8 c; void setup(){c=0;}\n"
                  "  void loop(){c=c+1; v.write(c);} }"))
PY
```

## Connect it to an MCP host

**Claude Desktop / Claude Code** (`claude_desktop_config.json` or the MCP
settings): add a server entry. Use absolute paths.

```json
{
  "mcpServers": {
    "cg": {
      "command": "neosyn-fpga-mcp",
      "args": [],
      "env": {
        "CG_JAR": "/abs/path/releng/lsp-server/target/cg-language-server.jar",
        "NEOSYN_CG_DEV": "1"
      }
    }
  }
}
```

The same `command`/`args`/`env` shape works for Cursor, Cline, and other
stdio-MCP hosts.

Then **load `cg_context.md` as the system prompt** (or paste it at the top of
the conversation). The model now knows the language *and* can verify it.

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

`cg_adapt_demo.py` drives the whole loop and is the place to see it work:

```bash
.venv/bin/python cg_adapt_demo.py --target l2_norm_sq   # one adapt, shows the C⏚
.venv/bin/python cg_adapt_demo.py --matrix              # robustness sweep
```

It seeds the model with `DotProduct.cg`, asks it to adapt to a new kernel
(weighted sum of differences, sum of squares, scaled dot, SAXPY-reduce, squared
distance), verifies with `cg_simulate`, and compares against an **independent**
Q16.16 reference (the model can't pass by hardcoding a wrong self-check). The
`--matrix` sweep also ablates *base vs no-base* and *terse vs detailed* prompts
so you can see what actually carries the result.

## What the eval measures — and what it does not

`cg_vs_verilog_eval.py` writes the same small hardware tasks in C⏚ and in
Verilog and verifies each with a real simulator. Read its aggregate percentage
with care.

**The aggregate is a property of the task list, not of the languages.** Measured
2026-08-24 at n=50 per cell (10 trials × 5 tasks), 9 of the 10 cells are
*deterministic* — reproduced identically across two independent runs:

| task | C⏚ first-try | Verilog first-try |
|---|---|---|
| Counter4 | 10/10 | 10/10 |
| Accum3 | 10/10 | 10/10 |
| Mod6 | **10/10** | **0/10** |
| Toggle | **0/10** | 10/10 |
| Fib8 | **0/10** | 9/10 |

Cells are 0/10 or 10/10, not rates. Each task that flips category moves the
headline by 20 points, so any single number quoted from this harness is really
a statement about which five tasks are in `TASKS`. The one stochastic cell
(Fib8-verilog, 9/10) is the entire difference between Verilog 98% and 100% —
i.e. repetition earned its keep in exactly the cell that disagreed with itself.
**Choose `n` per cell, not per harness: the cells that need repetition announce
themselves by varying.**

Totals from that run, with the failure-kind fix below applied:

```
cg        first-try 30/50 (60%)  after-loop 49/50 (98%)  avg attempts 1.5  fails={'sim': 1}
verilog   first-try 39/50 (78%)  after-loop 50/50 (100%) avg attempts 1.2  fails={}
```

An earlier writeup on the unmerged `docs/cg-agent-kit-eval` branch headlines
"first-try C⏚ 93% > native Verilog 60%". That does not reproduce, and per the
above it could not have meant what it says either way. Treat it as superseded.

**A defect that was hiding the interesting result.** `verify_cg` labelled every
diagnostic-bearing result `"compile"`, but a test-vector mismatch arrives *as* a
diagnostic — so a design that compiled, simulated, and merely computed the wrong
answer was counted as a compile failure. Both systematic C⏚ failures (Toggle,
Fib8) are exactly that, and both are the **same root cause**: state updated
before the port write, so the emitted sequence is off by one cycle. The
mislabelling made C⏚'s residue look syntactic when it is a timing/ordering
error. Fixed; `kind` now distinguishes `sim` from `compile`.

**MEASURED before/after on that fix (2026-08-24).** The two deterministic cells, same
harness, same model, 10 trials each, one variable — the `cg_context.md` edit:

| task | before | after |
|---|---|---|
| Toggle | **0/10** | **9/10** |
| Fib8 | **0/10** | **9/10** |

C⏚ first-try on those two tasks: **0/20 → 18/20**. Both cells were *perfectly deterministic
at zero* beforehand — twenty attempts across two independent runs, no passes — so a jump to
9/10 is not run-to-run variance. Caveats: one model (qwen3.6:35b-a3b), n=10, two tasks. The
compiler jar also changed between the runs, but that cannot affect **first-try**, because the
model writes before it sees any compiler output; the after-loop figures are confounded and are
not relied on here.

Note the cells are now 9/10 rather than 10/10 — they stopped being deterministic, which is the
harness saying these cells now need repetition where they previously did not.

The root cause was not a missing example. The pack's own `Counter` was
`count = count + 1; value.write(count);` — update, then write — for something described as
starting at 0, and it emits `1,2,3…`. The corrective rule existed but was scoped to enum
control FSMs and filed under a heading a counter author would not read. A curated corpus is a
liability in the same way it is an asset: **a wrong example is code the model will copy.**
Every example should be executed against a `test:` block that asserts its documented output —
this one survived because nothing ever ran it.

That failure class is why `cg_context.md` leads its state section with
*write first, then update*, with right/wrong pairs and the emitted vectors —
the wrong version reads like careful code and only the vectors reveal it.

**`CG_SEED_MIN_SCORE` does nothing here.** Seeding lives in `cg_local_client.py`
(`_seed_for`), a different runner. This harness never calls `cg.example()`, so
setting the variable neither enables nor disables anything in it. It is a real
safeguard for the client, and a no-op for the eval.

## Files

```
neosyn-fpga-mcp/
├── README.md            this file
├── cg_context.md        the "C⏚ for LLMs" knowledge pack (system prompt)
├── cg_mcp_server.py     the MCP server (stdlib core + thin mcp wrapper)
├── examples/            verified C⏚ bases to seed-and-adapt from
│   ├── RECIPES.md       the recipe catalogue (use_when / adapt / gotcha)
│   ├── Counter.cg
│   ├── DotProduct.cg
│   ├── SqrDist.cg
│   ├── FixedSqrt.cg
│   └── Distance.cg
├── cg_adapt_demo.py     seed-and-adapt demo + robustness matrix
├── cg_vs_verilog_eval.py   measures C⏚-vs-Verilog write rates on small tasks
├── cg_local_client.py   minimal local-LLM driver (Ollama / OpenAI-style)
└── requirements.txt     `mcp` (only needed to run as a server)
```
