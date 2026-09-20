# C⏚ state machines — writing a control FSM

A **control FSM** (a sequence/pattern detector, a protocol controller, a serial
parser, a bus master) is a `task` with a **state register** and **next-state
logic** in `loop()`. This is the most common shape an LLM gets asked for and the
one with the most first-draft traps — the traps are all about *timing*, and the
compiler enforces them. Seed the verified base with `cg_example("fsm")` (or
`"state machine"` / `"sequence detector"`) → `Seq1011`.

## The shape

```cg
task Seq1011 {                       // overlapping "1011" sequence detector
    sync { in bool din; out bool found; out u2 scode; }

    enum St { S0, S1, S2, S3 }       // named states — 0..3
    St st;                           // the state register (inline-init, see below)

    void loop() {
        bool b = din.read();

        // 1) OUTPUTS for the current state — driven BEFORE the transition
        found.write((st == S3) && b);   // Mealy: depends on state AND input
        scode.write((u2) st);           // Moore: depends on state only

        // 2) NEXT-STATE logic — a plain if/else-if over (state, input)
        if      (st == S0) { st = b ? S1 : S0; }
        else if (st == S1) { st = b ? S1 : S2; }
        else if (st == S2) { st = b ? S3 : S0; }
        else               { st = b ? S1 : S2; }   // st == S3
    }
}
```

Verified: bytecode sim 8/8 + yosys **REAL** (18 cells) + iverilog elaborates. It
synthesizes to real sequential logic — flip-flops for the state, a mux tree for
the transition.

## State encoding — a named enum

- Use an **`enum`** for the state: named states document the machine and the width
  is inferred (4 states → `u2`). Both bare (`st == S0`) and qualified
  (`st == St.S0`) literals work in comparisons and assignments.
- An **enum is a valid port type** — you can expose the state directly with
  `out St scode; ... scode.write(st);`, and the port carries the enum's underlying
  width (`St` → 2 bits). For a link between two actors, declare the enum in a
  shared `bundle` so both sides name the same type. Publishing a bare `uN` code
  (`out u2 scode; scode.write((u2) st);`) is equally fine for a pure debug/status
  signal — this example does that — but the enum port is the clearer choice for a
  typed opcode/command/mode field crossing actors.
- A plain `uN` state variable works too (`u2 st;` with `st = 0/1/2/3`), but the
  enum is clearer and costs nothing (it *is* a `uN` after elaboration).

## Moore vs Mealy outputs

- **Moore** output = function of the **current state only** (`scode = (u2) st`).
- **Mealy** output = function of the current state **and** the current input
  (`found = (st == S3) && b`) — it can react one cycle earlier than a Moore output.

Both are fine. Compute either from the **current** state, before you transition.

## The two timing rules (this is where first drafts break)

**1. Publish the CURRENT state, before the transition.** A port reflects the
register as it was at the *start* of the cycle. So drive every output from the
current `st` **first**, then update `st`. If you compute a *next* state and then
publish it in the same cycle, it reads back **one cycle late** and every vector is
off by one.

```cg
// WRONG — publishes the next state, reads back a cycle late
st = next(st, b);
scode.write((u2) st);

// RIGHT — publish current, then transition
scode.write((u2) st);
st = next(st, b);
```

**2. Inline-initialize state; don't use `setup()` for it.** A `setup()` body
compiles to a **separate reset FSM state** that runs on the first clock — it eats
a cycle and offsets the whole input/output stream (a vector test then fails
off-by-one or times out one short). Initialize the register **inline** instead:

```cg
St st;          // defaults to the first enum member (S0) — no reset state, no offset
u8 count = 0;   // inline init also works for plain fields (like `bool flag = true;`)
```

Reserve `setup()` for genuine one-shot side effects (e.g. writing a boot value to
another instance), not for zeroing your own state.

## Single-cycle vs multi-cycle FSMs

- The `loop()` above is **one clock per iteration** — one state transition per
  cycle. That's the usual control FSM.
- A `loop()` that contains a `while`, a `fence`, an `idle(n)`, or several gated
  port reads becomes a **multi-cycle** FSM — the compiler infers one state per
  cycle of work. Inspect the result with `cg_fsm` (it prints the states and
  transitions). Use a `while` only for genuinely data-dependent, multi-cycle
  sequences (a handshake wait, a variable-length burst); a fixed control machine
  wants the single-cycle `loop()` above.

## Making it self-check

Drive the machine with a `test` vector property — one value per port per cycle.
Group the ports in a `sync { … }` block. A `bool` port accepts either `true`/`false`
**or** numeric `0`/`1` in the vectors:

```cg
properties {
    test: {
        din:   [1, 0, 1, 1, 0, 1, 1, 0],   // input bitstream
        found: [0, 0, 0, 1, 0, 0, 1, 0],   // Mealy pulse when 1011 completes
        scode: [0, 1, 2, 3, 1, 2, 3, 1]    // state entering each cycle
    }
}
```

`cg_simulate` drives the inputs, samples the outputs, and asserts they match —
`ok: true` means the machine is correct. Then `cg_generate_verilog` + `cg_synth`
to confirm it maps to real flip-flops (`verdict: REAL`, not FOLDED/SUSPECT).

## Quick diagnosis

- **Every output is off by one (or the sim times out one vector short):** a
  `setup()` body added a reset state — inline-init the state instead (rule 2).
- **Correct value but one cycle late / the wrong cycle:** you published a
  just-computed *next* state — publish the current state before transitioning
  (rule 1).
- **`operator == is undefined for the argument types bool and uN`:** you compared
  a `bool` with an integer (`b == 1`). It now evaluates correctly, but prefer
  `if (b)` / `if (!b)` for a bool, and reserve `==` for same-typed operands.
- **The machine wedges in one state:** a transition arm is missing or a branch is
  unreachable — print `scode` and check the transition table covers every
  (state, input) pair.
