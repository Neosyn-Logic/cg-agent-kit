# Measuring C⏚ against Verilog

Moved out of `README.md` on 2026-09-27. It is methodology and dated results —
useful if you are reproducing or extending the measurement, and noise to someone
deciding whether to install the package.

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
