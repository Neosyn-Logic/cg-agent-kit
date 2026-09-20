# C⏚ handshakes — port protocols, back-pressure, and pacing

How a producer and a consumer synchronize is chosen per **port**, by a qualifier
in front of the type. Getting this right is the single most common cause of a
design that *compiles and elaborates but deadlocks or drops data in simulation*.

## The four protocols

| Qualifier | Old syntax (still accepted, deprecated) | Wires added | Back-pressure? | Use when |
|---|---|---|---|---|
| *(bare)*  | — | data only | none | a value that is valid **every** cycle (a plain wire) |
| `push`    | `sync` | `valid` | **no** | fire-and-forget, producer-driven; the consumer must keep up |
| `stream`  | `sync ready` | `valid` + `ready` | **yes** | the consumer may stall the producer (elastic) |
| `confirm` | `sync ack` | `valid` + `ack` | yes (ack) | the producer needs delivery confirmation |

Key facts:
- `push` ≡ old `sync` — **valid only, NO ready line**. The producer asserts `valid`;
  nothing can tell it to wait. If the consumer isn't ready that cycle, the value is lost.
- `stream` ≡ old `sync ready` — **valid + ready**. The consumer lowers `ready` to
  back-pressure the producer. This is the protocol every `std.math.*` / `std.mem.*` /
  `std.fifo.*` built-in uses on its handshake ports (you'll see `sync ready` in their
  source — same thing as `stream`).
- Prefer the **new** keywords (`push`/`stream`/`confirm`) in new code; the `sync …`
  forms are deprecated but identical in meaning.

## Writing a producer correctly

- A `push` (or bare) output should be written **every cycle** of the actor's `loop()`.
  A `push`/`stream` output left unwritten in a cycle is a common source of an X / stall.
- A `stream` output blocks the writing actor until the consumer is `ready`. That
  back-pressure is your friend — it paces the whole chain automatically (see below).
- `out stream` between two ordinary tasks **sample-holds** the last value; if you need a
  fresh value pushed every cycle, use `out push`. (A fast producer feeding a slow
  consumer needs a FIFO — see below.)

## Connecting instances

Inside a `network`, wire an instance's inputs from another's outputs with `.reads()`:

```cg
mul = new std.math.Multiply();
mul.reads(feeder.a, feeder.b);   // feeder's two stream outputs drive mul's stream inputs
sink.reads(mul.p);               // sink's stream input reads mul's product
```

The protocol is taken from the ports themselves — connect `stream` to `stream`.

## THE pacing gotcha (read this before using a built-in)

`std.math.Multiply` and `std.math.Divide` are **registered with no input FIFO**
(latency ≥ 1, `stream` handshake). If you feed such a built-in from a **single task**
that reads both operands and then reads the product in the same `loop()`, the
non-buffered 1-cycle handshake will **silently drop a vector** — the sim produces the
wrong sequence (e.g. `30, -7, …` where `-20` is missing), not a crash.

**Wrong** — one task bridging a two-input built-in:
```cg
bridge = new task {
    void loop() {
        mul.a.write(a.read());
        mul.b.write(b.read());
        p.write(mul.p.read());   // races the next iteration's writes → drops data
    }
};
```

**Right** — split into feeder → built-in → sink with native `stream` links, so the
built-in's `ready` back-pressure flows all the way to the source and paces the stream
with no manual timing:
```cg
feeder = new task {                 // adapts external inputs onto the built-in's stream ports
    out stream int<32> ma;
    out stream int<32> mb;
    void loop() { ma.write(a.read()); mb.write(b.read()); }
};
mul = new std.math.Multiply();
mul.reads(feeder.ma, feeder.mb);
sink = new task {                   // drains the built-in's stream product
    in stream int<64> mp;
    void loop() { p.write(mp.read()); }
};
sink.reads(mul.p);
```

Alternative when you drive a built-in from a stimulus source: **space the writes** with
`idle(n)` where `n` exceeds the handshake round-trip (this is why the Multiply/Divide
KATs use `idle(8)` between vectors).

## Bridging external `push` ports to a built-in

A `network` often exposes plain `push` ports for its testbench, but a built-in wants
`stream`. Adapt with small bridge tasks (the pattern above): the feeder converts
`push` → `stream`, the sink converts `stream` → `push`. Referencing the network's own
external ports from an inline task is allowed.

## FIFO — elastic decoupling

To let a fast producer and a slow consumer run at their own rates, drop a FIFO between
them. Both ends are `stream`, so the handshake is automatic:

```cg
fifo = new std.fifo.SynchronousFIFO({size: 16, width: 8});
fifo.reads(producer.out);
consumer.reads(fifo.out);
```

`std.fifo.AsynchronousFIFO` is the two-clock (CDC) variant with the same `stream` ends.

## Streaming reductions (emit once per group) — read streams UNCONDITIONALLY

A reduction consumes N inputs and emits one result (a dot product, a running sum, a
MAC). Drive it with a counter and **read every input stream on every cycle** — gate only
the *emit*, never the *reads*:

```cg
dut = new task {
    in stream uint<32> ia, ib;
    out stream uint<64> oy;
    uint<32> cnt = 0;
    uint<64> acc = 0;
    void loop() {
        acc = acc + ia.read() * ib.read();   // BOTH streams read every cycle
        if (cnt == M - 1) { oy.write(acc); cnt = 0; acc = 0; }  // gate the EMIT
        else { cnt = cnt + 1; }
    }
};
```

This is the `StreamDot` recipe (bytecode-sim verified; synthesizes REAL). `cnt` and `acc`
are state; the accumulator is flushed and cleared on the last element of each group.

> **Signed inline `a*b` of stream inputs** works on the current toolchain — the Verilog
> backend distributes the sign-extension over the handshake mux, so a signed MAC reduction
> elaborates and synthesizes. (On releases ≤ 2.9.0 it emitted invalid Verilog; there, keep
> operands unsigned or route the product through the `std.math.Multiply` built-in — see the
> `MulStream` recipe.)

> **A conditional read of a `stream` works; a conditional read of a `push` does not.**
> A `stream` (sync-ready) input read only on *some* iterations —
> `if (cnt == 0) { acc = bias.read(); }` while reading the other streams every cycle —
> is paced by its ready/valid handshake and reads the fresh value each group (correct on
> both hardware and Fast-sim). A `push` input read the same way silently drops the
> skipped values — `push` has no back-pressure to hold them. Even for streams, the
> simplest always-correct shape is to read every cycle and use the value conditionally:

```cg
// per-group scalar (a bias) done safely: read every cycle, use only at the start
void loop() {
    int<32> gv = ig.read();            // unconditional read
    if (cnt == 0) { acc = gv; }        // conditional USE is fine
    acc = acc + is.read();
    if (cnt == M - 1) { oy.write(acc); cnt = 0; acc = 0; }
    else { cnt = cnt + 1; }
}
```

The producer must then present the scalar on every cycle of the group (replicate it), or
carry it as a `const`/parameter rather than a stream.

## Quick diagnosis

- **Sim deadlocks / "timed out after N cycles":** a `stream`/built-in consumer is
  waiting on `valid` that never comes, or a producer is blocked on `ready` that never
  rises — check that every instance is actually connected and driven.
- **Sim runs but values are wrong/short by one:** the pacing gotcha above — a
  non-buffered built-in fed too fast. Use feeder/sink or `idle()`.
- **A reduction is correct on the first group but wrong on later ones:** a `push` input is
  being read conditionally (once per group) — `push` has no back-pressure, so the skipped
  values are lost. Make it a `stream` (its handshake paces the conditional read), or read
  every cycle and use the value conditionally. See the reduction section above.
- **A `push` output is intermittently lost:** the consumer wasn't ready; it needs a
  `stream` port or a FIFO, not `push`.
