# C⏚ arithmetic — multiply, divide, modulo, shift

What the operators synthesize to, when they need a built-in, and when they cost money.
C⏚ is **width-strict**: it rejects implicit narrowing, so the width of the *destination*
decides whether you keep or truncate a result. Cast explicitly.

## Multiply `*`

- `*` is **full-width**: `int<N> * int<M>` produces an `int<N+M>` product — no bits are
  lost in the operation. To keep the whole product, the destination must be wide enough
  (`int<32> * int<32>` → assign to `int<64>`, not `int<32>`, or you truncate on store).
- A runtime `*` maps to a DSP block. If **one operand is a compile-time constant**, it
  folds to shift-adds (no DSP, no hint).
- A **wide runtime `*`** (both operands wider than ~18 bits) is a single combinational
  multiplier spanning more than one DSP tile. The validator emits an advisory hint. If it
  doesn't meet timing, use the **`std.math.Multiply` built-in** — a *registered* signed
  product (1-cycle latency, `stream` handshake) that the tool can retime into the DSP's
  pipeline registers. See the `MultiplyStream` example.

```cg
mul = new std.math.Multiply();   // p = a * b, p is 2*width bits, registered
mul.reads(feeder.a, feeder.b);
```

## Reductions (MAC, dot product, running sum)

A reduction consumes N stream elements and emits **one** result — a dot product, a
multiply-accumulate, a running/windowed sum. Drive it with a counter and a state
accumulator; **read every input stream on every cycle** and gate only the *emit*:

```cg
dut = new task {
    in stream uint<32> a, b;
    out stream uint<64> p;
    uint<32> cnt = 0;
    uint<64> acc = 0;
    void loop() {
        acc = acc + a.read() * b.read();                      // read BOTH streams every cycle
        if (cnt == M - 1) { p.write(acc); cnt = 0; acc = 0; }  // gate only the EMIT
        else { cnt = cnt + 1; }
    }
};
```

Seed `cg_example("dot product")` / `cg_example("reduction")` (`StreamDot`). A signed inline
`a*b` of stream operands works on the current toolchain (on releases ≤ 2.9.0 keep operands
unsigned or route the product through `std.math.Multiply`).

**A per-group side input (a bias) read conditionally must be a `stream`, not a `push`.**
Seeding an accumulator with `if (cnt == 0) acc = bias.read();` works when `bias` is a
`stream` (sync-ready) input — the handshake paces it, so each group reads the fresh value
(correct on hardware and Fast-sim). A `push` `bias` read this way silently drops the skipped
values (no back-pressure). The simplest always-correct shape reads every stream every cycle
and uses the value conditionally, or carries a per-group scalar as a `const`/parameter.

## Divide `/` and modulo `%`

There is **no general hardware divider** for a runtime denominator. What's legal:

- **By a compile-time constant** — compiles directly, single cycle:
  - a **power of two** → a shift / mask;
  - **any other positive constant** → a *reciprocal (magic-number) multiply* `(x*M) >> s`
    (the same trick GCC/LLVM emit). Correct for both signednesses: floor for unsigned,
    truncate-toward-zero for signed. E.g. `u32 x; x / 10` → `(x * 0xCCCCCCCD) >> 35`.
  - a **zero or negative** constant divisor is rejected.
- **By a runtime value** → rejected with a hint. Use the **`std.math.Divide` built-in**
  (sequential shift/subtract, multi-cycle, `stream` handshake; a `use_hard` option maps to
  the target's native `/`, and a power-of-two divisor takes a fast path):

```cg
div = new std.math.Divide();     // q = a / b for runtime a, b
div.reads(num.a, num.b);
```

`%` by a constant is lowered as `x - (x/n)*n` reusing the quotient (correct sign both ways).

## Shift `<<` `>>`

- **By a constant** → free (it's just wiring).
- **By a runtime amount** → rejected. Build a **barrel shifter**: mux the input across the
  constant power-of-two shift amounts, selected by the variable's bits. See the
  `BarrelShift` example.

## What's free vs. what's a paid IP core

- **Free (built-in):** integer `std.math.Divide` and `std.math.Multiply`, constant `/`,
  `%`, `<<`, `>>`, and `*`.
- **Paid (Divider IP core):** **Q16.16 fixed-point** division and the runtime variable-shift
  block — the fixed-point/precision layer on top of the free integer divide.

## Common mistakes an LLM makes here

1. Writing `int<32> p = a * b;` for two 32-bit operands — **truncates**. Use `int<64> p`.
2. Writing `x / y` or `x % y` for runtime `y` — not synthesizable; reach for
   `std.math.Divide`. (Constant `y` is fine.)
3. Writing `x << n` / `x >> n` for runtime `n` — not synthesizable; build a barrel shifter.
4. Feeding `std.math.Multiply`/`Divide` too fast from one task — they're registered with no
   input FIFO and will drop data. See the handshakes doc (`cg_docs("handshakes")`) for the
   feeder/sink pacing pattern.
5. Assuming a big runtime `*` is free at any clock — it maps to a DSP but a wide
   combinational product may miss timing; register it via `std.math.Multiply`.
