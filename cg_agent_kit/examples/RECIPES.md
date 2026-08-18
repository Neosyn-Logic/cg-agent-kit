# C⏚ validated-code dictionary

A curated dictionary of **validated** C⏚ — every entry compiles, simulates, and
synthesizes (yosys) to a REAL datapath. Don't synthesize a hard kernel from scratch:
`cg_example` returns the closest entry (scored, with runners-up) to seed-and-adapt;
no argument returns the index.

Access is **scored**: exact name ≫ name word ≫ full tag phrase ≫ partial overlap,
so `1/sqrt` → RSqrt while a bare `sqrt` → FixedSqrt. `cg_suggest_for_error(msg)`
maps a compiler rejection to the recipe with the synthesizable pattern
(`/`/`%` by a variable → Recip; shift by a variable → BarrelShift;
data-dependent loop bound → SeqDiv).

Cell counts are the coarse word-level yosys stat (`proc; flatten; opt; stat`).

## Primitives (the reusable library)

| Recipe | Use when | Tags | Verified |
|--------|----------|------|----------|
| `Recip` | 1/d reciprocal of a runtime value (no hardware divider) | reciprocal, recip, inverse, 1/x, one-over | 252 cells |
| `Divide` | general a/b division of runtime operands | divide, division, a/b, quotient, ratio | 284 cells |
| `SeqDiv` | area-cheap divider when latency is acceptable (one stage reused over N cycles) | divide, sequential, multicycle, area-efficient, fsm | 42 cells |
| `FixedSqrt` | Q16.16 square root | sqrt, root, isqrt, square-root | 211 cells |
| `RSqrt` | 1/sqrt(x) (normalization, inverse magnitude) | rsqrt, inverse-sqrt, 1/sqrt, one-over-sqrt, normalize | 461 cells |
| `SqrDist` | weighted squared-difference reduction with REAL input ports (datapath survives synthesis) | squared, sqrdist, sum-of-squares, r2, ports | 22 cells |
| `DotProduct` | fixed-point multiply-accumulate over vectors | dot, mac, multiply-accumulate, inner-product, reduction | 17 cells |
| `Fir` | streaming FIR filter; sample shift-register is state | fir, filter, convolution, stream, taps | 13 cells |
| `Integ` | Euler integrator v+=a*dt; x+=v*dt; stateful pos/vel time loop | integrator, euler, timestep, kick, drift | 6 cells |
| `Distance` | Euclidean distance r = sqrt(sum (a-b)^2) (pre-composed MAC + isqrt) | distance, euclid, euclidean, norm, magnitude | 229 cells |
| `Counter` | sequential state -> a registered output that advances each cycle | counter, sequential, state, register, increment | sim✓ |
| `BarrelShift` | shift by a RUNTIME amount (Cg can't emit a variable shift) — mux tree of literal shifts | shift, barrel, shifter, sll, srl, sra, variable-shift | 445 cells |
| `RegisterFile` | array addressed by a runtime index, hardwired-zero entry, write-first reads | register-file, regfile, array, indexed, x0, hardwired-zero, write-first | 10466 cells |
| `BitFieldDecode` | extract a bit field from a word and sign-extend it | bitfield, extract, sign-extend, decode, immediate, slice | 123 cells |
| `Tee2` | replicate ONE push stream to two consumers (bare fan-out deadlocks the sim) | tee, fanout, replicate, split, broadcast, fork | 33 cells |
| `Clamp` | saturate/clip a value to a [lo,hi] range (overflow guard) | clamp, saturate, clip, limit, min, max, range | 410 cells |
| `Lerp` | linear interpolation y = a+(b-a)·t, Q16.16 (blend/ramp/crossfade) | lerp, interpolate, blend, mix, crossfade, ramp | 6735 cells |

## Examples (composed domain answers)

Deliberately **not served**. The dictionary provides reusable **primitives** to
compose, not finished domain solutions — handing over a complete kernel (e.g. the
whole n-body `Force`) defeats the point: the model should compose the verified
primitives itself. Pull the primitives above and wire them.

## Notes

- Every primitive is **driven by `in push` ports** from its test-network driver, so
  the datapath survives synthesis (`cg_synth` `verdict: REAL`). Driving a kernel with
  compile-time **constants** instead folds it to a constant (`verdict: FOLDED`) — a
  common trap; keep your inputs on ports.
- `cg_synth` reliably catches FOLDED (dead datapath) and SUSPECT (inferred latches),
  but it is **not a correctness oracle** — a REAL verdict means real hardware, not
  *correct* hardware. `cg_simulate` (the asserting test network) is the correctness check.
- Fully-unrolled bit-serial dividers (Recip/Divide/RSqrt) are area-heavy with a long
  combinational path; SeqDiv is the sequential (FSM) divider when latency is OK.
