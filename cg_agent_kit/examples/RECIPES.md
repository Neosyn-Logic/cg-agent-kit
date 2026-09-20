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

> The nine entries added in S169 (`Lfsr` … `MovingAverage`) carry a stronger gate than
> the rest: every one is value-checked on the **bytecode** simulator AND re-checked
> **cycle-for-cycle under iverilog** against the same vectors, analysed clean by **ghdl**,
> synthesized by yosys with **no inferred latches**, and **mutation-tested** (the datapath
> was sabotaged and the fixture confirmed to fail).

> **Division by a CONSTANT needs no recipe.** `x / 10`, `x % 3`, `x / 4` compile
> inline (pow2 → shift/mask, else a single-cycle reciprocal multiply). The recipes
> below are for a **runtime** divisor only — and for that, the `std.math.Divide`
> built-in (multi-cycle, `sync ready` handshake) is the first-class option; `Recip`
> / `Divide` / `SeqDiv` are source-included alternatives when you want the divider
> in your own RTL.

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
| `MulStream` | stream two runtime operands through a registered full-width multiplier (std.math.Multiply) | multiply, mul, product, a*b, times, registered-multiply, dsp | sim✓ REAL |
| `StreamDot` | streaming reduction (dot / MAC / running sum): consume M inputs per group, emit one result — read every stream each cycle, gate only the emit | reduction, reduce, dot-product, mac, accumulate, running-sum, streaming-reduction | 47 cells |
| `ScaleGen` | parameterize a task by compile-time `const`(s) and instantiate with `new Foo({param})` — a distinct module per parameter set | generic, generics, parameterized, template, monomorphize, const-param | 65 cells |
| `Fir` | streaming FIR filter; sample shift-register is state | fir, filter, convolution, stream, taps | 13 cells |
| `Integ` | Euler integrator v+=a*dt; x+=v*dt; stateful pos/vel time loop | integrator, euler, timestep, kick, drift | 6 cells |
| `Distance` | Euclidean distance r = sqrt(sum (a-b)^2) (pre-composed MAC + isqrt) | distance, euclid, euclidean, norm, magnitude | 229 cells |
| `Counter` | sequential state -> a registered output that advances each cycle | counter, sequential, state, register, increment | sim✓ |
| `Seq1011` | a control FSM: enum state register + next-state logic (sequence/pattern detector, protocol controller) | fsm, state-machine, sequence-detector, controller, moore, mealy, enum-state | 18 cells |
| `UartTx` | serialize a byte onto a one-bit line, one bit per clock — start/data/stop framing via a shift register + bit counter (UART TX) | uart, serial, transmitter, tx, shift-register, framing, start-bit, stop-bit, baud, protocol | 16 cells |
| `UartRx` | deserialize a one-bit line back into a byte — start-bit detect, LSB-first shift-in, stop-bit framing check, one-cycle `valid` (UART RX) | uart, serial, receiver, rx, deserialize, shift-register, framing, start-bit, stop-bit, oversample, protocol | 30 cells |
| `Crc8` | bit-serial CRC / checksum over a stream — the XOR-feedback shift register behind every CRC, LFSR, scrambler and PRNG | crc, crc8, crc16, crc32, checksum, lfsr, prng, scrambler, polynomial, error-detection | 13 cells |
| `Debounce` | clean a noisy async input (button/switch/sensor) into a stable level + one-cycle rising/falling pulses; N=1 gives a plain edge detector | debounce, button, switch, edge-detector, rising-edge, falling-edge, one-shot, glitch-filter, input-conditioning | 21 cells |
| `Pwm` | duty-cycled output (LED/motor/servo) **and** the clock/rate divider — its one-cycle `tick` is the "baud-tick enable" that gates a slower machine | pwm, duty-cycle, clock-divider, rate-divider, prescaler, tick, strobe, enable, baud-tick, timer | 13 cells |
| `SpiMaster` | drive an SPI bus as master (mode 0) — generates sclk, full-duplex: clocks a byte out on MOSI while clocking one in on MISO | spi, master, sclk, mosi, miso, chip-select, full-duplex, synchronous-serial, adc, dac, flash, sensor | 48 cells |
| `BarrelShift` | shift by a RUNTIME amount (Cg can't emit a variable shift) — mux tree of literal shifts | shift, barrel, shifter, sll, srl, sra, variable-shift | 445 cells |
| `RegisterFile` | array addressed by a runtime index, hardwired-zero entry, write-first reads | register-file, regfile, array, indexed, x0, hardwired-zero, write-first | 10466 cells |
| `BitFieldDecode` | extract a bit field from a word and sign-extend it | bitfield, extract, sign-extend, decode, immediate, slice | 123 cells |
| `Tee2` | EXPLICIT 1->2 replicator, for when the two branches must diverge (a bare push fan-out already broadcasts correctly — don't add a Tee to fix one) | tee, fanout, replicate, split, broadcast, fork | 33 cells |
| `Clamp` | saturate/clip a value to a [lo,hi] range (overflow guard) | clamp, saturate, clip, limit, min, max, range | 410 cells |
| `Lerp` | linear interpolation y = a+(b-a)·t, Q16.16 (blend/ramp/crossfade) | lerp, interpolate, blend, mix, crossfade, ramp | 6735 cells |
| `Lfsr` | pseudo-random bits/bytes per cycle (PRBS, scrambler, dither, cheap counter) — maximal-length Galois LFSR, period PROVEN by running it | lfsr, prbs, prng, pseudo-random, galois, maximal-length, scrambler, test-pattern, dither | 12 cells |
| `PriorityEncoder` | first set bit -> index + valid (interrupt controller, free list, normaliser, the encode step of any arbiter) | priority-encoder, first-set-bit, find-first, one-hot-to-binary, interrupt, allocator, leading-zero | 22 cells |
| `RoundRobinArbiter` | share a bus/port/link among N requesters FAIRLY — rotate, encode, rotate back; fairness verified explicitly, not just "someone got granted" | arbiter, arbitration, round-robin, fair, starvation, grant, bus-arbiter, rotating-priority | 38 cells |
| `GrayCounter` | a count where exactly ONE bit changes per step — async-FIFO pointer / CDC, position encoder — plus both binary<->Gray conversions | gray-code, gray-counter, binary-to-gray, gray-to-binary, cdc, clock-domain-crossing, fifo-pointer, position-encoder | 23 cells |
| `EdgeDetect` | level -> one-cycle EVENT (rising / falling / both) — the smallest and most-instantiated block there is; put Debounce in front of anything that bounces | edge-detector, rising-edge, falling-edge, pulse, strobe, one-shot, level-to-pulse, trigger | 12 cells |
| `Biquad` | fixed-point 2nd-order IIR section (low/high/band-pass, notch, shelf, EQ, DC blocker, loop filter); Q format and the truncation/feedback traps spelled out | biquad, iir, filter, second-order-section, direct-form, notch, equaliser, dc-blocker, q-format | 15 cells (5 $mul) |
| `Manchester` | self-clocking, DC-balanced line code over ONE wire — encoder + decoder verified as a ROUND TRIP, with coding-violation detection | manchester, line-code, biphase, self-clocking, clock-recovery, dc-balance, 10base-t, rfid, encoder-decoder | 29 cells |
| `HammingEcc` | correct a single-bit error and DETECT a double-bit one (ECC memory, NAND, SEU-hard registers); errors injected explicitly through a port | hamming, ecc, secded, error-correction, syndrome, parity, bit-flip, seu, memory-protection | 119 cells |
| `MovingAverage` | smooth a stream over the last N samples with a running sum (one add + one subtract, any N) | moving-average, sliding-window, running-sum, boxcar, smoothing, rolling-average, circular-buffer | 65 cells |

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
