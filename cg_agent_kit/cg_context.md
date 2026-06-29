# Writing C⏚ (Cg) — working context for an LLM

You are writing **C⏚** ("C-Ground", file extension `.cg`), a C-like hardware
description language. C⏚ compiles to **synthesizable Verilog/VHDL** and to
**JVM bytecode for a fast cycle-accurate simulator**. It is *not* Verilog and
*not* C. Do not emit Verilog. Write C⏚ and verify it with the compiler tools.

You have compiler tools (`cg_check`, `cg_simulate`, `cg_generate_verilog`,
`cg_synth`, `cg_example`, `cg_suggest_for_error`, `cg_fsm`, `cg_graph`,
`cg_docs`). `cg_docs("riscv")` returns a worked CPU reference — the loadable
single-cycle RV32I core plus reusable patterns for CPU-shaped hardware (barrel
shifter for runtime shifts, `u(N+1)` widening for unsigned compares, sub-word
load/store, count-prefixed boot-stream program loading, lossless-capture
testbenches); read it before building a processor, decoder, datapath, or stack
machine.
**Always** `cg_check` then `cg_simulate` a draft and fix every diagnostic before
presenting code. The compiler is ground truth; your training data has almost no
C⏚, so verify, don't guess. For a hard fixed-point kernel, call `cg_example`
first to seed from a verified base instead of writing it from scratch — it's a
scored dictionary of validated code (specificity-weighted: `1/sqrt`→RSqrt,
`sqrt`→FixedSqrt), returning the best match plus runners-up. When the compiler
rejects something, `cg_suggest_for_error(msg)` names the recipe with the
synthesizable pattern (and `cg_check`/`cg_simulate`/`cg_generate_verilog`
auto-attach it as a `suggestion`). When the target is hardware,
`cg_synth` is the final gate — it yosys-synthesizes the Verilog and returns
`{ok, verdict, cells, warnings, …}`; insist on `verdict: "REAL"` (not FOLDED =
constant-folded, or SUSPECT = latches). But REAL means real *hardware*, not
*correct* hardware — `cg_synth` is not a correctness oracle. `cg_simulate` (the
asserting test network) is the correctness check; pass it FIRST, then use
`cg_synth` to confirm the hardware is real, not folded or latched.

---

## The mental model

C⏚ has three top-level constructs:

- **task** — a sequential hardware block. It has state, ports, and behaviour
  written as `setup()` (runs once at reset) and `loop()` (runs every clock
  cycle). After compilation a task is an FSM, the way the Verilog backend sees
  it.
- **network** — structural composition. It declares **instances** of tasks /
  other networks and wires their ports together. No behaviour of its own.
- **bundle** — a stateless container of constants, `typedef`s, lookup tables,
  and `const` helper functions. Imported by tasks/networks.

Every file **must** start with a `package` declaration. This is the single
most common first-draft error.

```cg
package com.example.demo;
```

---

## Types

- Bit-accurate integers: `u8`, `u16`, `u4`, `int<16>` (signed), `uint<W>`
  (parameterized width). `bool`. Unsigned by default.
- Casts mask/extend: `(u8) x`, `(uint<W>) 0xFFFF`.
- Arrays: `u8 mem[16];` (fixed size). Arrays of state are mutable and persist
  across cycles. Brace initializers work: `u8 lut[4] = {1, 2, 4, 8};`.
- **struct**: composite type. **enum**: named integer constants.
- Width is strict: the validator rejects implicit narrowing; cast explicitly.
  Arithmetic *widens* — `a + b` is one bit wider than its operands — so
  accumulating into a fixed-width variable needs a cast every step:
  `sum = (int<32>) (sum + x);`. Forgetting this ("cannot convert from i33 to
  i32") is the single most common validation error.
- `*` is fine, but **`/` and `%` must be by a constant power of two** (they
  compile to a shift / mask). A variable or non-power-of-two divisor is not
  synthesizable — there is no hardware divider; precompute, use a power of two,
  or restructure. (`x >> k` / `x & (k-1)` are the explicit forms.)
- **Shift amounts must be literal too** — `x << n` / `x >> n` can't take a
  runtime `n`. For a variable shift, build a barrel shifter (literal shifts
  gated by the amount bits); see gotcha #10 and `cg_example("barrel shift")`.
- **Unsigned `<`/`>` on a full-width value compares as signed** — widen past
  the sign bit (`(u33)a < (u33)b`) for a true unsigned compare; see gotcha #11.

## Fixed-point arithmetic (the #1 thing to get right)

C⏚ has no floats. Represent a real value V in **Q16.16** as the integer `V<<16`
(i.e. `V * 65536`). Add/subtract is just integer add/sub. **Multiply is the trap:**
a Q16.16 × Q16.16 product is Q32.32, so you must shift it back **exactly once**
with `>> 16`. Getting this `>>16` wrong (missing it, or doing it once for a
chained product) is the single most common bug — it overflows and the result
saturates to garbage.

**Always multiply through this helper — never hand-roll the shift.** Note a
value-returning function MUST be declared `const` (a non-const one compiles to
"no body" and fails at runtime):

```cg
const int<32> fxmul(int<32> x, int<32> y) {
  return (int<32>) ((((int<64>) x) * ((int<64>) y)) >> 16);   // exactly one >>16
}
```

Use it for every product, and **chain it for products of 3+ values** — one
`fxmul` per multiply:

```cg
int<32> sq   = fxmul(d, d);            // d^2            (Q16.16)
int<32> term = fxmul(w, fxmul(d, d));  // w * d^2        (Q16.16) — two muls, two fxmul
int<32> acc  = acc + fxmul(a, b);      // accumulate Q16.16 products
```

Widen to `int<64>` only inside `fxmul` (the helper already does). Don't carry raw
`x*y` products around un-shifted.

---

## Ports and how tasks talk

A port is `in`/`out`, an optional interface qualifier, a type, a name:

```cg
out push u8 dout;     // output, push interface
in  stream u8 din;    // input, stream interface
out u4 count;         // bare (no qualifier) — a plain wire, valid every cycle
```

Interfaces (a port chooses how producer and consumer synchronize):

| Qualifier  | Handshake        | Use when…                                  |
|------------|------------------|--------------------------------------------|
| *(bare)*   | none             | a value that is valid every cycle          |
| `push`     | valid only       | fire-and-forget, producer-driven           |
| `stream`   | valid + ready    | the consumer may stall the producer        |
| `confirm`  | valid + ack      | the producer needs delivery confirmation   |

Read and write with `.read()` and `.write(v)` (use the parentheses):

```cg
u8 v = din.read();
dout.write(v + 1);
```

### Wiring instances in a network

Use the **positional** `consumer.reads(producer.port, ...)` form. It fills the
consumer's unconnected input ports in declaration order:

```cg
processor.reads(driver.a, driver.b, driver.c);   // inA<-a, inB<-b, inC<-c
sink.reads(fifo.dout);
```

A consumer can also read a producer's output directly by reference:
`gcd.z.read()`, `processor.out_pkt.read()`. **Do not** use the per-port
`processor.inA.reads(driver.a)` form — it does not resolve in the simulator.

---

## Packages and multi-file projects

Every `.cg` starts with a `package` line. **Tasks in the same package resolve
across files** — a `network` in `Force.cg` can instantiate a `SqDist3` defined in
`SqDist3.cg`, as long as both declare the *same* package (e.g.
`package com.acme.nbody;`). Split a design one-task-per-file if you like; just
keep the package line identical in every file. Pick a real package name for your
project — not the placeholder `com.example`.

Two things that bite on a multi-file project:

- **A `cg_example` result is *text*, not a registered module.** To use it, **save
  it to a `.cg` file** in your package and **set its `package` line to match
  yours**. Instantiating `new Tee2()` without writing `Tee2` to a file gives
  `Couldn't resolve reference to Instantiable 'Tee2'`.
- **The tools only see what you hand them.** `cg_check` / `cg_simulate` /
  `cg_synth` / `cg_generate_verilog` compile in an isolated dir, so a multi-file
  design needs **`package_dir`**: pass the folder holding your `.cg` files (e.g.
  `package_dir="fpga/src/main/cg"`, relative to the project root) and the tool
  reads every sibling there — exactly like the IDE. Without it, only the single
  `source` string is compiled and tasks in your other files won't resolve.

---

## State, setup/loop, and FSMs

```cg
task Counter {
    out push u8 value;
    u8 count;                 // state — persists across cycles

    void setup() { count = 0; }            // once, at reset
    void loop()  { count = count + 1; value.write(count); }   // every cycle
}
```

A task becomes a multi-state FSM automatically when `loop()` contains blocking
operations: a `while` loop, a `fence` (end-of-cycle barrier), an `idle(n)`
(wait n cycles), or multiple gated port reads. The compiler infers one state
per cycle of work. Use `cg_fsm` to see the result.

```cg
void loop() {
    while (counter < 5) {
        value.write(counter);
        fence;                 // advance to next clock cycle
        counter++;
    }
}
```

A **`for` loop with a compile-time-constant trip count is unrolled** into
straight-line combinational code — use it for fixed-size datapaths (e.g. a
24-stage bit-by-bit sqrt) instead of copy-pasting stages. Only a
**data-dependent** bound (a runtime value) stays a `while`/FSM. One caveat:
the loop index binds as a runtime constant, so don't use it where a
*compile-time* constant is required — keep shift amounts and type widths
literal (carry a `bit` and `bit = bit >> 2`, not `<< (46 - 2*i)`).

Increment/decrement work in both forms: `i++`, `++i`, `i--`, `--i`, and the
compound assignments `i += 2`, `i -= 1`. **`continue` and `break` work** inside
both `while` and `for` loops (including nested loops — an inner `break` exits
only the inner loop; a `for` `continue` still runs the increment). The compiler
FSM-lowers a loop that carries them. Using one outside any loop is a clear
error.

---

## Structs

```cg
struct Header { u8 src; u8 dst; }
struct Packet { Header hdr; u16 payload; }   // nested

Packet p;
p.hdr.src = 1; p.payload = 0x100;            // field write
Packet copy = p;                             // whole-struct copy
out stream Packet out_pkt;                   // struct-typed port
```

Arrays of struct and per-element field access work: `Packet batch[3];
batch[i].hdr.src = ...`. Struct fields at *task state* scope (persisting across
cycles) are also supported.

---

## Enums

```cg
enum Light { GREEN, YELLOW, RED }   // 0-indexed; width inferred (3 -> 2 bits)

Light state;
state = GREEN;          // bare literal
state = Light.RED;      // qualified literal (same as RED)
if (state == GREEN) ... // compares against the literal / its integer value
```

**Limit:** enums are internal value types, not a port type. Publish a code
(`u2`) on the port, not the enum itself.

---

## Generics (parameterized tasks)

```cg
task Register<int W = 8, int EXPECT = 0xFF> {
    uint<W> value;
    void loop() { value = (uint<W>) 0xFFFF; assert(value == EXPECT); }
}

network Top {
    narrow = new Register<4, 0xF>();    // monomorphized: a distinct module
    byte   = new Register();            // both defaults (W=8, EXPECT=0xFF)
}
```

Each `new Foo<...>()` is a separate specialized instance; parameters are
compile-time, no runtime cost. Compare a `uint<W>` value against an `int`
*parameter* (as above); do not cast inside an `assert` and compare to the
literal — the comparison resizes to a default width and the mask is lost.

---

## Standard library

Instantiate stdlib blocks with a property object:

```cg
fifo = new std.fifo.SynchronousFIFO({size: 16, width: 8});   // single-clock queue
ram  = new std.mem.SinglePortRAM({size: 256, width: 16});

import std.lib.SynchronizerFF;
sync_ff = new SynchronizerFF();          // CDC: inherits parent's clocks
sync_ff.reads(din); sync_ff.writes(dout);
```

**FIFO (`std.fifo.SynchronousFIFO`)** — an elastic queue to decouple a producer
from a consumer. Both ends are `stream`, so the handshake is automatic: a
`dout.write` blocks while the FIFO is full and a `din.read` blocks while it is
empty — never poll `full`/`empty`. The FIFO holds each element until the
consumer reads it, so read one value per `din.read` and let the loop come back
for the next. Wire it positionally — `din` from the producer, then the consumer
from `dout`:

```cg
fifo = new std.fifo.SynchronousFIFO({size: 16, width: 8});
fifo.reads(producer.dout);    // producer.dout -> fifo.din
consumer.reads(fifo.dout);    // fifo.dout    -> consumer.din
```

`AsynchronousFIFO` is the two-clock-domain (CDC) variant — same `stream` ends,
plus `properties { clocks: ["din_clock", "dout_clock"] }`. See the `FifoPipe`
recipe (`cg_example`) for a full, both-backend-verified producer→FIFO→consumer.

Multiple clock domains: `properties { clocks: ["clock_in", "clock_out"] }` on
the network.

---

## Making a program self-check (so the tools can verify it)

Attach a `test` property. Two forms:

**Vector form** — drive inputs / check outputs by name (the simulator wraps the
task, drives stimulus, and asserts outputs):

```cg
task SimpleAdder {
    properties { test: {
        a:   [1, 10, 100],
        b:   [2, 20,  50],
        sum: [3, 30, 150]
    } }
    in push u8 a; in push u8 b; out push u8 sum;
    void loop() { sum.write(a.read() + b.read()); }
}
```

**Monitor form** — a `finished` flag plus `terminate`, for networks:

```cg
network Demo {
    properties { test: { terminate: "driver.finished" } }
    driver = new task {
        bool finished;
        void setup() { finished = false; }
        void loop() {
            if (!finished) {
                assert(/* some condition */);
                print("=== Demo done ===\n");
                finished = true;
            }
        }
    };
}
```

`assert(cond)` fails the simulation on a false condition. `print(...)` emits to
the sim log. A passing `cg_simulate` (ok: true) means the asserts held.

---

## Gotchas that make first drafts fail (read these)

1. **`package` first.** Every `.cg` begins with a `package` line, or you get
   `mismatched input '...' expecting 'package'`.
2. **Write a `push` output every cycle.** If a `push`/`stream` output is
   written only on some `loop()` iterations, the simulator stalls (times out).
   Make the write unconditional and carry the meaning in the value, or in a
   separate always-written `bool` flag.
3. **`.read()` / `.write()` with parentheses**, not `.read` as a field.
4. **Positional `consumer.reads(producer.port, ...)`** — not per-port
   `consumer.inPort.reads(...)`.
5. **Enums are not port types.** Publish an integer code.
6. **Don't cast inside an `assert` and compare to a wide literal** — pass the
   expected value as a parameter/constant of the right width.
7. **Width is strict** — cast explicitly when narrowing, and re-cast each step
   when accumulating (`sum = (T)(sum + x)`).
8. **`/` and `%` only by a constant power of two** — no hardware divider. For a
   runtime divisor seed `cg_example("divide")` (`Recip` / `Divide` / `SeqDiv`).
9. **`continue` / `break` work inside loops** (`while` and `for`, nested OK).
   Only outside a loop is an error.
10. **No shift by a runtime amount.** `x << n` / `x >> n` need `n` to be a
    literal. To shift by a variable, build a **barrel shifter**: conditional
    literal shifts by 1/2/4/8/16 gated by each bit of the amount — exactly how
    RTL does it. Seed `cg_example("barrel shift")` (`BarrelShift`).
11. **A full-width unsigned `<` compares as signed.** `(u32)0xFFFFFFFF < 1`
    reads as `-1 < 1` (true). For a true unsigned compare, widen past the sign
    bit: `(u33)a < (u33)b`. Signed compares use an explicit `(int<32>)` cast.

---

## Your workflow

1. Draft the C⏚, starting with `package`.
2. `cg_check` → fix every diagnostic (each is `{file, line, message}`).
3. `cg_simulate` → confirm `ok: true` and the `output` matches intent; if it
   times out, suspect gotcha #2.
4. `cg_fsm` / `cg_graph` if you need to confirm state count or wiring.
5. `cg_generate_verilog` once it simulates, to hand off RTL.
6. `cg_synth` to confirm the Verilog synthesizes (`ok: true`, sensible `cells`,
   empty `problems`). A constant-bound `for` synthesizes (it's unrolled); a
   genuinely data-dependent loop becomes an FSM (also fine). If `problems`
   flags a construct yosys can't map, simplify the dataflow.

For a hard fixed-point kernel, `cg_example("sqrt")` (or `"distance"`, `"dot"`,
…) first — adapt a verified base, don't synthesize the datapath from scratch.

Choosing a backend:

- `cg_simulate(src, simulator="bytecode")` (default, fast, no toolchain) or
  `cg_simulate(src, simulator="iverilog")` for a Verilog-level cross-check. The
  iverilog backend needs a network whose name contains `Test` with a **capital
  T**, e.g. `network TestFoo`, so the HDL backend emits a testbench; a lowercase
  `_test` network only drives the bytecode sim's `test` property.
  (`simulator="verilator"` is accepted but reported unavailable unless
  installed.)
- `cg_synth(src, flow="generic")` (default, portable check) or a vendor FPGA
  family: `cg_synth(src, flow="ice40")` (also `ecp5`/`xilinx`/`gowin`/`intel`)
  to map to that part's primitives.

Iterate steps 2–3 until the program is correct. The compiler, not your prior,
is the authority on C⏚.
