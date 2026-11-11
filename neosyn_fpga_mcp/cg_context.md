# Writing C⏚ (Cg) — working context for an LLM

You are writing **C⏚** ("C-Ground", file extension `.cg`), a C-like hardware
description language. C⏚ compiles to **synthesizable Verilog/VHDL** and to
**JVM bytecode for a fast cycle-accurate simulator**. It is *not* Verilog and
*not* C. Do not emit Verilog. Write C⏚ and verify it with the compiler tools.

You have compiler tools (`cg_lint`, `cg_check`, `cg_simulate`,
`cg_generate_verilog`, `cg_synth`, `cg_scaffold`, `cg_example`,
`cg_suggest_for_error`, `cg_report`, `cg_fsm`, `cg_graph`, `cg_docs`,
`cg_capabilities`). Those are the only tool names there are — a call to
anything else (`cg_compile`, `cg_run`, …) comes back with this list and the
closest real name, so you never have to guess twice. **Do not assume which
simulator you have.** The fast bytecode simulator ships with the commercial Neosyn
distribution and is absent from the open-source compiler; `cg_capabilities`
probes this host and tells you which backend to use. Where it exists it is the
default and the right choice — `simulator="iverilog"` is a slower Verilog-level
cross-check, not the everyday tool. `cg_docs("riscv")` returns a worked CPU reference — the loadable
single-cycle RV32I core plus reusable patterns for CPU-shaped hardware (barrel
shifter for runtime shifts, unsigned vs signed compares, sub-word
load/store, count-prefixed boot-stream program loading, lossless-capture
testbenches); read it before building a processor, decoder, datapath, or stack
machine.
## Work in baby steps (read this first)

Work in BABY STEPS -- this is how C⏚ designs get finished. Never write a whole design in one reply:
a reply that tries is cut off by the output limit and leaves nothing that compiles.
1. Interface first: the ports and an empty loop (`cg_scaffold`), then `cg_check`.
2. One task at a time, about 40 lines at most, `cg_check` after each.
3. `cg_simulate` as soon as a piece can be tested; only then write the next piece.
4. When a check fails, fix ONLY the reported line and check again -- do not rewrite the file.

**Do not start from a blank file.** Call `cg_scaffold(kind=...)` first: it
returns a complete skeleton that ALREADY COMPILES and whose self-test ALREADY
PASSES, with the datapath left as `>>> FILL IN` markers (their line numbers come
back in `holes`). You then change one thing — the datapath — instead of
inferring the file skeleton, the port syntax and the test-harness shape at the
same time, which is where drafts actually fail. Because it starts green, any red
after your edit IS your edit. `kind="task"` is the default and the strongest: its
`test:` block value-checks every output cycle by cycle. Use `"fsm"` for a control
machine, `"stream"` for a push-handshake dataflow stage, `"network"` for a
multi-stage pipeline, `"generic"` for a parameterized entity.

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

**File-scope declarations.** On a recent Neosyn compiler you may write `const`,
`typedef`, `struct` and `enum` directly after `package`/imports, with no enclosing
container; they are then in scope UNQUALIFIED for the whole file. After compiler 3.5.2
they may sit anywhere between entities; on 3.5.2 or older they must precede the first
`task`/`network`/`bundle`. (An open-source compiler OLDER than 3.5.1 does not accept
this — there, put them in a `bundle` and reference them as `BundleName.member`; the 3.5.1
open-source jar does. `cg_capabilities` tells you which compiler you have.) Enum literals: write them qualified, `Mode.RUN`, which works on
every compiler. From 3.5.3, `import Pkg.Bundle.*;` also makes a bundle enum's literals resolve
bare (`RUN`), and so does an enum declared at file scope (after 3.5.2); on older compilers a bare one is "RUN cannot be resolved". When two enums of one task or bundle
declare the same literal name, ALWAYS write it qualified (`B.X`): older compilers silently take
the FIRST enum's literal for a bare `X` (a wrong value, no message); from 3.5.3 it is the error
"'X' is ambiguous ... Write A.X or B.X." In a network every output (and every instance input) has
EXACTLY ONE writer: never `.writes()` two instances into the same port. Older compilers only warn
"connected too many times" and emit a multi-driven net; 3.5.3 refuses it. Never `.write()` an `in` port or `.read()` an `out`
port: older compilers only warn (and emit an assignment to an HDL input); 3.5.3 refuses it.

```
package com.example;
const int<32> FIX_ONE = 1 << 16;
const fx_t fxmul(fx_t x, fx_t y) { return (fx_t) ((((int<64>) x) * ((int<64>) y)) >> 16); }
task Gain { ... y.write(fxmul(x.read(), FIX_ONE)); }
```

C⏚ has three top-level constructs:

- **task** — a sequential hardware block. It has state, ports, and behaviour
  written as `setup()` (runs once at reset) and `loop()` (runs every clock
  cycle). After compilation a task is an FSM, the way the Verilog backend sees
  it.
- **network** — structural composition. It declares **instances** of tasks /
  other networks and wires their ports together. No behaviour of its own.
- **bundle** — a stateless container of constants, `typedef`s, lookup tables,
  and `const` helper functions. Imported by tasks/networks.

A file **may** start with a `package` line; it is optional. Without one, the
file joins the package the other `.cg` files of its folder declare, or, when
none does, takes it from its path (the folders below `src/`, as in Java).

```cg
package com.example.demo;   // optional
```

---

## Types

- Bit-accurate integers: `u8`, `u16`, `u4`, `int<16>` (signed), `uint<W>`
  (parameterized width). `bool`. Unsigned by default.
- Casts mask/extend: `(u8) x`, `(uint<W>) 0xFFFF`.
- Arrays: `u8 mem[16];` (fixed size). Arrays of state are mutable and persist
  across cycles. Brace initializers work: `u8 lut[4] = {1, 2, 4, 8};`.
- **struct**: composite type. **enum**: named integer constants.
- Every type has an exact width, and **a value declared wider than its target
  needs a cast** (3.5.3+, an error): `u8 w = 0x3c; u4 n = w;` is refused with
  "A u8 value does not fit in u4: 4 bits would be lost. Write `(u4) w` if the
  truncation is meant"; the same for `o.write(w)` into a narrower port. Write
  `u4 n = (u4) w;` (keeps the low bits, `0xc`). Before 3.5.3 the local truncated
  silently and the port only warned. A constant counts at its value's width:
  `const int N = 10; u4 r = N;` is fine. Arithmetic *widens* — `a + b` is one bit wider than its wider operand — so a
  sum of two variables stored back into their width warns "This sum can reach
  ... it wraps before it is used". Size the destination for the result, or
  cast to say the wrap is intended: `sum = (int<32>) (sum + x);`.
- `*` is fine (single-cycle, maps to a DSP/multiplier). **`/` and `%` by any
  compile-time CONSTANT are also fine** — a power of two becomes a shift/mask,
  any other constant a reciprocal (magic-number) multiply, both single-cycle and
  exact (floor for unsigned, truncate-toward-zero for signed). So `x / 10`,
  `x % 3`, `x / 4` all just work. Only a **VARIABLE (runtime) divisor** has no
  inline datapath (division is multi-cycle in hardware): use the multi-cycle
  `std.math.Divide` built-in, or seed a source-included divider with
  `cg_example("divide")` (`Recip` / `Divide` / `SeqDiv`). The divisor must be
  positive.
- **Shift amounts must be literal too** — `x << n` / `x >> n` can't take a
  runtime `n`. For a variable shift, build a barrel shifter (literal shifts
  gated by the amount bits); see gotcha #10 and `cg_example("barrel shift")`.
- **`<`/`>` on unsigned values is an unsigned compare**, as in the HDL. Fast Sim
  before 3.5.3 got it wrong for a full-width `u32`/`u64` with the top bit set; see
  gotcha #11.

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

On compilers after 3.5.2, `in`, `out`, `sync`, `ack` and `ready` may also be names
(`in push u8 in;`, `out push bool ack;`, `u8 sync = x.read();`) — except that `ready` is
never a port, field or enum-literal name (`x.ready` is the handshake test). On 3.5.2 or
older they are reserved: name ports `din`/`dout`/`acked`.

After 3.5.2 a BARE output may also be written with `=` (`sum = acc;` is `sum.write(acc);`).
A `push`/`stream`/`confirm` output needs `.write(v)` — `=` there is refused (it sends no
value). `.write()` works everywhere and on every compiler.

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
`gcd.z.read()`, `processor.out_pkt.read()`.

On compilers after 3.5.2 you can also **name** the input you wire, one per statement, in
any order — the design then no longer depends on the order the ports are declared in:

```cg
processor.inB.reads(driver.b);
processor.inA.reads(driver.a);
processor.reads(driver.c);        // positional: the one input still free (inC)
this.result.reads(processor.sum); // a network output, by name
```

A misspelled name is refused with the list of the instance's ports; naming a port twice,
or giving one named port two sources, is refused too. On 3.5.2 or older the named form
does not resolve (`Couldn't resolve reference to Inst 'processor.inA'`): use positional.

---

## Packages and multi-file projects

**Tasks in the same package resolve across files** — a `network` in `Force.cg`
can instantiate a `SqDist3` defined in `SqDist3.cg` with no import. Files of one
folder are always in the same package: one with no `package` line joins the one
its folder-mates declare. Split a design one-task-per-file if you like; either
leave the `package` line out everywhere, or keep it identical in every file.

Two things that bite on a multi-file project:

- **A `cg_example` result is *text*, not a registered module.** To use it, **save
  it to a `.cg` file** in your package and **drop its `package` line (or set it to match
  yours)**. Instantiating `new Tee2()` without writing `Tee2` to a file gives
  `Couldn't resolve reference to Instantiable 'Tee2'`.
- **The tools only see what you hand them.** `cg_check` / `cg_simulate` /
  `cg_synth` / `cg_generate_verilog` compile in an isolated dir, so a multi-file
  design needs **`package_dir`**: pass the folder holding your `.cg` files (e.g.
  `package_dir="fpga/src/main/cg"`, relative to the project root) and the tool
  reads every sibling there — exactly like the IDE. Without it, only the single
  `source` string is compiled and tasks in your other files won't resolve.
- **Verify the file you will ship, not a copy of it.** Pass **`path`** (the `.cg`
  file) instead of, or with, `source`: the tool then reads the file itself, and
  if `source` and the file differ the call is refused at the first differing line.
  Every result carries `verified: {path, sha256, bytes, lines}` — quote it when you
  claim a design passes. Fixing a value in the `source` argument without saving it
  proves nothing about the file.

---

## State, setup/loop, and FSMs

```cg
task Counter {
    out push u8 value;
    u8 count;                 // state — persists across cycles

    void setup() { count = 0; }            // once, at reset
    void loop()  { value.write(count); count = count + 1; }   // every cycle
}
```

**Write first, then update — this is the single most common way a correct-looking
first draft produces wrong values.** The example above emits `0, 1, 2, 3, …`. Swap
the two statements and it emits `1, 2, 3, …`: the port carries what the register
holds at the START of the cycle, so a value you compute and then write is already
one cycle late.

It costs nothing to get right and it is invisible until you check the vectors —
the wrong version reads like careful code:

```cg
// WRONG — emits true, false, true …     // RIGHT — emits false, true, false …
void loop() {                            void loop() {
    state = !state;                          q.write(state);
    q.write(state);                          state = !state;
}                                        }
```

Same for a recurrence — publish the current term, then advance:

```cg
task Fib {                               // emits 1, 1, 2, 3, 5, 8, 13, 21
    out push u8 q;
    u8 cur; u8 nxt;
    void setup() { cur = 1; nxt = 1; }
    void loop() {
        q.write(cur);                    // publish FIRST
        u8 t = (u8) (cur + nxt);         // then advance
        cur = nxt;
        nxt = t;
    }
}
```

Do not try to detect "the first iteration" by testing the state values
(`if (prev2 == 0 && prev1 == 1) …`). Those guards go on matching a later state and
latch the output forever. Order the statements correctly and no guard is needed.

A task becomes a multi-state FSM automatically when `loop()` contains blocking
operations: a `while` loop, a `fence` (end-of-cycle barrier), an `idle(n)`
(wait n cycles), or multiple gated port reads. The compiler infers one state
per cycle of work. Use `cg_fsm` to see the result. `n` must be a literal or a
`const`, at least 1: from 3.5.3 `idle(k)` with a run-time `k` is an error; older
compilers build it without a message and wait ONE cycle, whatever `k` holds. To wait a computed number of cycles, count it down
yourself: `while (k != 0) { k = k - 1; }` (no `fence` inside: each iteration is
already one cycle, and a fence at the end of a `while` body does nothing). Measured: it takes
one cycle more than `idle` with the same constant.

A `fence` that ends no cycle gets the warning "This fence does nothing": `fence; fence;`
(ONE cycle -- use `idle(n)` to wait longer), a fence next to `idle`, right before a
`while`, last in a `while` body, first or last in `loop()`, last in a branch of an `if`
that itself ends `loop()` or a `while` body. Everywhere else -- inside an `if`/`else`
branch with code after the `if`, right after an `if` or a loop, anywhere in a `for` body
-- a fence adds a cycle: keep it. Compilers before 3.5.3 called many of those "Illegal fence";
that message was wrong, never delete a fence because of it.

For an explicit **control FSM** (a sequence/pattern detector, a protocol
controller, a serial parser) — an enum state register plus next-state logic —
read `cg_docs("fsm")` and seed `cg_example("fsm")` (`Seq1011`). Two timing rules
the compiler enforces, and that break most first drafts: **(a)** a port reflects
the register at the *start* of the cycle, so publish the CURRENT state and drive
every output BEFORE the transition (writing a just-computed next state reads back
one cycle late) — this is the same write-then-update rule as for ordinary state
above, and it applies to EVERY state variable, not only to an enum state register;
**(b)** inline-initialize the state (`St st;` defaults to the
first enum member) rather than a `setup()` body — a `setup()` compiles to a
separate reset STATE that eats the first clock and offsets the whole stream.

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

### One-statement bodies (compilers after 3.5.2)

`if`, `else`, `for` and `while` take one statement without braces, as in C; an `else`
belongs to the nearest `if`. Also accepted: `};` after an `enum` or `struct`, a trailing
`,` in an enum, and a `u` suffix on a literal (`0xA5u`, ignored: width comes from the
value and its use). On 3.5.2 or older every body needs braces.

```cg
u8 v = a.read();
if (v < 10) v = 10;
else if (v > 100) v = 100;
y.write(v);
```

### `switch` (compilers after 3.5.2)

A case never falls through (as in Verilog): it ends at the next `case`.
`break;` is optional, `case A, B:` and stacked labels share a body, `default:`
comes last. Switch on a variable (read a port into a local first). A `break`
inside a nested block of a case is refused.

```cg
enum State { RED, GREEN, YELLOW }
State state = RED;
void loop() {
  switch (state) {
    case RED:    color.write(0); state = GREEN;
    case GREEN:  color.write(1); state = YELLOW;
    case YELLOW: color.write(2); state = RED;
  }
}
```

`State state = RED;` as a field works on compilers after 3.5.2; on 3.5.2 or older it
draws "not a compile-time constant" -- there, set it in `setup()` instead.

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
cycles) are also supported. Never use a whole array element or a whole sub-struct
as a value (`Packet p = batch[i];`, `Header h = pk.hdr;`): copy the leaf fields.
Older compilers only warn there and use 0 for every field; 3.5.3 refuses it.
Write ONE `properties` block per entity: a second one replaced the first in older
compilers (a `reset:` or `test:` in the first was silently lost); 3.5.3 refuses it.

---

## Enums

```cg
enum Light { GREEN, YELLOW, RED }   // 0-indexed; width inferred (3 -> 2 bits)

Light state;
state = GREEN;          // bare literal
state = Light.RED;      // qualified literal (same as RED)
if (state == GREEN) ... // compares against the literal / its integer value
```

An **enum is a legal port type** — `out Light state;` works, and the port carries
the enum's underlying width (`Light` → 2 bits). Both sides of a cross-actor link
must see the *same* enum, so declare a shared enum in a `bundle` and reference it
(`out push Ops.Op op;` … `in push Ops.Op op;`). A numeric test vector on an enum
port is accepted (coerced to the enum), and the emitted Verilog/VHDL port is a
plain `uN`/`std_logic_vector`. (Publishing a bare `uN` code instead is still fine
for a pure debug/observation signal, but a typed enum port is clearer for an
opcode/command/mode field that crosses actors.) An explicit underlying type widens
the port: `enum Op : u4 { … }` → a 4-bit port.

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
the network. A multi-bit value crosses with `std.lib.SynchronizerMux` (`push` in,
bare out); leave `stages + 2` destination-clock periods between writes. Before
3.5.3 it LOST values whenever the destination clock was slower than the source.
`cg_simulate` has one clock and cannot show a crossing: say the CDC is unverified unless
the HDL was run with unequal clock periods.

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

**Outputs are matched in WRITE order, not cycle by cycle.** An output port's
vector lists the values the task writes to it, in order: vector i is the i-th
write, in whatever cycle it happens. So a design with latency (a line buffer, a
3x3 window) needs nothing special: list only the outputs it produces. The
output vector can be shorter than the inputs (`cg_example Window3x3`: 16 pixels
in, 4 sums out). Every write counts, including any made while a pipeline fills.

Each output port is checked on its OWN writes, so outputs written at different
rates are fine: `every: [1, 2, 3, 4, 5, 6]` and `odd: [1, 3, 5]` on a task that
writes `odd` only for odd inputs passes with 9 checks. Before compiler 3.5.3 the
checker waited for vector i of ALL outputs at once and such a task failed
(`every == 2 -- every = 3`) although it was right; on an older jar, check outputs
that come at different rates from a monitor task. This needs every checked output
to be `push` or `stream` with no `null` in its vector; a bare output, or a vector
with a `null`, is still read step by step beside the others. A `null` entry checks nothing:
a value written on that step is not checked (it is not a "must be quiet" check).

The vector form is for **short** tests. Each port's list compiles into one method,
and the JVM caps a method at 64 KB, so a vector holds a few thousand entries at
most (measured: 2,000 `u8` values fit, 3,000 do not; the exact limit depends on
the ports and the values). A whole frame, or enough values to push an
accumulator past 2^32, needs the monitor form below: a stimulus task that
GENERATES the values, and a monitor that checks them and sets `finished`. Too
long a vector is reported as "a `test:` vector is too long to compile".

**Where large expected values come from: the host, not the test.** Do not compute a
big stimulus or its expected results INSIDE C⏚ (a random generator, a reference
model): a runtime divisor, `%` or a wide multiply is rejected there, and the test
becomes harder than the design. Run the reference on the host instead (a short
Python script, with a shell command) and have it WRITE a generated bundle the test
reads:

```cg
package com.example;
// Generated by gen_vectors.py from reference.py. Do not edit; regenerate.
bundle Vectors {
    const int N = 4;
    u8 IN[N]  = {12, 200, 7, 99};
    u8 EXP[N] = {24, 144, 14, 198};
}
```

The driver writes `Vectors.IN[i]` and the monitor asserts against `Vectors.EXP[i]`;
pass `package_dir` so the bundle's file resolves. Regenerate it whenever the
reference changes.

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

1. **`package` is optional** (compilers after 3.5.2). A compiler of 3.5.2 or older
   still needs it first in every file: there, `expecting 'package'` or "a `}` is missing
   above this line" on line 1 means add `package <name>;`.
2. **A `push` output may be written on only some passes; a BARE output may not.** A
   `push` output that is not written carries no value that cycle, and the reader sees
   nothing (`if (src.q.available()) { ... }`); a `test:` vector lists only the writes
   (measured: `odd: [1, 3, 5]` on a task that writes `odd` for odd inputs passes). A
   **bare** output KEEPS its last value when not written, so a flag written only when
   it becomes true stays true for ever: write a bare flag every pass
   (`busy.write(cond);`). See `cg_docs("handshakes")`. Both ends of a link use the
   same protocol, with ONE allowed mix from 3.5.3: a `push` output read by a bare
   input reads the LAST value pushed (pushes between two reads are not seen; same on
   the sim and both HDLs). `stream` → bare and bare → `push` are errors (`Port
   mismatch: incompatible interface type`); 3.5.2 refuses the push → bare mix too.
3. **`.read()` / `.write()` with parentheses**, not `.read` as a field.
4. **Positional `consumer.reads(producer.port, ...)`**, or after 3.5.2 the named
   `consumer.inPort.reads(producer.port);` (one port per statement). On 3.5.2 or older
   only the positional form resolves.
5. **Enums ARE valid port types** (`out Light state;`) — the port carries the
   enum's underlying width. For a cross-actor link, share the enum via a `bundle`
   so both sides name the same type. (Older notes saying enums can't be ports are
   stale.)
6. **Don't cast inside an `assert` and compare to a wide literal** — pass the
   expected value as a parameter/constant of the right width.
7. **Width is strict** — storing a wider VARIABLE needs a cast (`(u8) w`), an
   error from 3.5.3. Arithmetic wraps at the target: `c = c + 1;` on a `u8` is
   fine. A `bool` compares only with a `bool`: write `if (flag)` / `!flag`, never
   `flag == 1` (an error from 3.5.3; turn a number into a bool with `x != 0`).
8. **`/` and `%` by any positive compile-time constant just work** (pow2 →
   shift/mask, else a reciprocal multiply — both single-cycle). Only a RUNTIME
   divisor needs the `std.math.Divide` built-in or `cg_example("divide")`
   (`Recip` / `Divide` / `SeqDiv`).
9. **`continue` / `break` work inside loops** (`while` and `for`, nested OK).
   Only outside a loop is an error.
10. **No shift by a runtime amount.** `x << n` / `x >> n` need `n` to be a
    literal. To shift by a variable, build a **barrel shifter**: conditional
    literal shifts by 1/2/4/8/16 gated by each bit of the amount — exactly how
    RTL does it. Seed `cg_example("barrel shift")` (`BarrelShift`).
11. **Unsigned compares are unsigned; cast for a signed one.** `a < b` on two
    `u32` is unsigned in the sim and both HDLs (`0xFFFFFFFF < 1` is false). For a
    signed compare cast both sides: `(i32) a < (i32) b`. Fast Sim BEFORE 3.5.3
    compared a full-width `u32`/`u64` as signed (`0xFFFFFFFF < 1` true, the HDL
    false); there, widen past the sign bit (`(u33) a < (u33) b`), which is right on
    every version.
12. **Write the port BEFORE updating the state it reads from.** `count = count + 1;
    value.write(count);` emits `1,2,3…` where `value.write(count); count = count + 1;`
    emits `0,1,2…`. A port carries the register as it stood at the START of the cycle.
    This compiles and simulates either way — only the vectors differ — and it is the
    most common cause of an otherwise-correct design failing its `test:` block. Applies
    to every state variable, not just enum FSM registers. See *State, setup/loop and
    FSMs* for worked right/wrong pairs.
13. **Reading a `push` input conditionally doesn't work — use a `stream`, or read
    every cycle.** A `push` port has no back-pressure, so a value you skip on a
    cycle is lost. A `stream` (sync-ready) input CAN be read conditionally —
    `if (cnt == 0) acc = bias.read();` while reading the other streams every cycle
    works correctly (the handshake paces it, on both hardware and Fast-sim). Even
    so, the simplest always-correct reduction reads every stream every cycle and
    uses the value conditionally — seed `cg_example("reduction")` (`StreamDot`).
    **The same loss happens with an unconditional `if (x.available())` when the
    task is busy:** a `loop()` that needs more than one clock (two writes of one
    output that could fall in the same cycle, a `fence`, a multi-cycle `if`) sits
    in a later state on some cycles, and a `push` value arriving then is gone.
    If a producer can send while the consumer is busy, make the link `stream`.
    **Write each output at ONE place per pass.** Writing a port in several
    separate `if`s (`if (a) { b.write(1); } if (c) { b.write(1); }`) adds a
    cycle per extra write even when only one runs, so decide in a local and
    write once at the end: `bool send = false; if (a) { send = true; } if (c)
    { send = true; } if (send) { b.write(1); }`. A plain (non-push) output holds
    its value: `p.write(flag);` once at the end is fine. From 3.5.3 the compiler
    warns `push input `x` can be missed: `b` is written at N places...` with this
    rewrite; apply it rather than ignore it. A deliberate serializer
    (`dout.write(a); dout.write(b);`) is not flagged.
14. **Braces around EVERY loop and branch body, even one statement — on a compiler of
    3.5.2 or older** (later ones accept one statement without braces, as C).
    There `for (i = 0; i < N; i++) v.write(x);` is a parse error — write
    `for (i = 0; i < N; i++) { v.write(x); }`; same for `if`, `else`, `while`. The
    compiler reports it as `missing '{' at '<token>'`, naming the body's first
    statement rather than the missing brace before it.
15. **Always read an input with `x.read()`; a bare `x` is refused.** A
    `push`/`stream` input used by its bare name (`acc = acc + x;`) with no
    `.read()` anywhere in the task is a blocking error ("read it with
    `x.read()`"). Older compilers accepted it, and then the simulator and the
    Verilog disagreed whenever the input had a gap. A bare `x` in a task that
    also does `v = x.read()` or tests `x.available()` still means the value just
    read.
16. **An unsigned subtraction wraps BEFORE your cast.** With `u3 r`,
    `(int<9>) (10 * r - 20)` is **236** in hardware for `r = 0`: `10 * r - 20`
    is computed unsigned at its own width and wraps, then the cast zero-extends
    it. Cast an operand to the signed type first: `(int<9>) r * 10 - 20` gives
    -20 in the simulator and the Verilog. Same for any `a - b` that can go
    below zero: make `a` (or `b`) signed before subtracting. The compiler
    warns on this ("This subtraction is unsigned ... wraps to a large positive
    value"); fix the code when you see it. Compilers before 3.5.3 do not warn,
    and their simulator gave -20 where the hardware gives 236.
17. **`terminate` names flags, not an expression: `terminate: "mon.finished"`.**
    From compiler 3.5.3 several flags may be joined by `&&`
    (`"a.finished && b.finished"`: the run ends when all are true); anything else
    (`||`, `!`, a comparison, an unknown instance, a non-bool variable) is an error
    that shows the form. Before 3.5.3 only ONE flag works: have one monitor set
    `finished = true` once everything it watches is done.
18. **A name is declared once per block.** Two `const N` (or two locals of one
    name) in the same scope are refused; the same name in two separate branches
    (`if { u8 t; } else { u8 t; }`) is fine.
19. **Two tasks that ask and answer must not use `stream` both ways.** `rom.reads(core.addr);
    core.reads(rom.data);` with `stream` ports on both links is a combinational loop between the
    `ready` signals: it simulates, but `cg_generate_verilog` refuses it (from 3.5.3). Put a
    `std.fifo.SynchronousFIFO({size: 4, ...})` on one link, or make the answer `push` and send
    one request at a time. See `cg_docs("handshakes")`.

---

## Your workflow

Baby steps, always: each step below is a SMALL change followed by a check.

1. `cg_scaffold` (or the interface alone: `package`, ports, an empty loop) → `cg_check`.
2. Add ONE task or ONE piece of datapath (about 40 lines at most) → `cg_check` → fix only
   the lines reported (each diagnostic is `{file, line, message}`).
3. `cg_simulate` as soon as that piece can be tested → confirm `ok: true` and the `output`
   matches intent; if it times out, the `terminate` flag was never set: a monitor is waiting for a value
   that was never written, or a `stream` read has nothing feeding it. Then repeat 2–3 for the next piece.
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
