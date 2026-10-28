# Medium and large C⏚ designs — how to build one without getting lost

Read this when the design is bigger than one task: more than about **150 lines, or more than
three tasks**. `cg_context.md` tells you how to write a task; this file tells you how to build
twenty of them into something that works. It is how Neosyn's own cores were built (an Ethernet
MAC of 34 tasks and networks, a UDP/IP stack of 15, an Intel 8088 CPU of 24), including what went wrong first. Two worked examples follow the method on real cores:
`walkthrough_udp_stack.md` (medium, 15 tasks) and `walkthrough_8088_cpu.md` (large, 24 tasks).

---

## Why big designs fail

A model that writes a 300-line task correctly can still fail a 2,000-line design, for four
reasons. Every rule below answers one of them.

1. **Too much unverified code at once.** Ten tasks written before any is simulated fail
   together, and the errors cannot be told apart. You end up rewriting everything.
2. **Losing the plan.** In a long session the early messages drop out of your context: the
   port widths you chose, which blocks are finished, what you were doing. You then contradict
   your own earlier decisions.
3. **Trusting a block nobody checked.** "It compiles" and "the output looked right once" are
   not tests. A later failure gets blamed on the wrong block.
4. **The seams.** Most top-level failures are not inside a block but between two: a width, a
   protocol (`push` vs `stream`), who waits for whom, how a frame ends, one cycle of latency.

---

## Phase 1 — the design on paper, before any code

Write a file `DESIGN.md` in the project. It is short, and it is the only thing you are allowed
to trust after your context has moved on. Fill in these four sections before writing C⏚:

**Blocks.** One line per task: name, file, what it does, rough size. Aim for tasks of 40–150
lines; split anything bigger, usually into control (an FSM) and datapath. One task per file.

**Layout: ONE folder, ONE package.** Put every `.cg` of the design — blocks, the shared bundle
and the tests — in a single folder, all with the same `package` line, and pass that folder as
`package_dir`. The tools read only the `.cg` files directly in that folder, not its subfolders,
so a block in `ip/` and its test in `test/` would not see each other. Tell the files apart by
name instead: `Parser.cg`, `TestParser.cg`.

The folder compiles as a whole, so **one file with an error stops every check and every test in
it** — the diagnostic then names that other file, not the one you passed. Never leave a
half-written file in the folder: finish the piece you are on until `cg_check` is clean, or keep
the draft outside the folder until it is.

**Links.** One row per connection between tasks — this table IS the design:

| from | to | type | protocol | framing | rate |
|---|---|---|---|---|---|
| `Parser.payload` | `Checksum.word` | `u16` | `push` | count = `len` words | ≤ 1 per cycle |
| `Checksum.sum` | `Builder.csum` | `u16` | bare | — | held until next packet |

- *protocol*: `push` (producer never waits), `stream` (consumer can make the producer wait), or
  a bare level. See `cg_handshakes.md`; pick deliberately, both ends must agree.
- *framing*: how the consumer knows a packet ended. Use a count sent first, or a `framed` port
  (`out framed u8 d;` … `d.write(b, isLast)`, read `d.last` in the same cycle as `d.read()`;
  compiler 3.5.0 and later). **Never** end a frame because `available()` went false: a producer
  that pauses mid-frame then looks like two frames, and the first half is processed as if the
  packet were complete.
- *rate*: can the producer send every cycle? Can it pause? The consumer must handle both.

**Shared definitions.** Widths, constants, enums used by more than one task go in ONE `bundle`
file (`bundle Net_Constants { typedef u48 mac; ... }`), never copied into each task.

**Test plan.** For every block: what its own test feeds it and what it asserts. For the top:
two or three end-to-end scenarios with known answers (a real packet with its known checksum, a
program with its known result).

---

## Phase 2 — the status table, your memory

Add a STATUS section to `DESIGN.md` and keep it current. **Re-read it before every step;
rewrite it after every step.** If you lose track, read only `DESIGN.md`, the block in hand and
its test — never the whole project.

| block | file | test | state | checks | note |
|---|---|---|---|---|---|
| Checksum | `Checksum.cg` | `TestChecksum.cg` | LOCKED | 1 | real header → 0xB1E6 |
| Parser | `Parser.cg` | `TestParser.cg` | SIMULATED | 12 | paced input not tried yet |
| Builder | `Builder.cg` | — | TODO | | |

States, in order: `TODO` → `WRITTEN` (cg_check clean) → `SIMULATED` (its test passes) →
`LOCKED` (passes, the test asserts values, and you made it fail once on purpose). Record the
number of checks the run reported: a test that executed **0 checks proved nothing**, even
when it says "passed".

---

## Phase 3 — build bottom-up, one rung at a time

Climb this ladder. **Do not start a rung while the one below has a red test.**

1. **Atoms** — combinational pieces (an ALU, an address decoder, a checksum step). Test every
   case you can enumerate.
2. **Blocks** — one task with state, alone, against its own test network.
3. **Subsystems** — two to four LOCKED blocks wired in a network (the receive path, the
   execution unit), with a test of their own.
4. **Top** — the subsystems together.
5. **Scenarios** — whole programs or packets through the top, checked against known answers.

For each block:

1. `cg_scaffold(kind=...)` for the task, then write it in pieces of about 40 lines, `cg_check`
   after each, with `package_dir` set so the other files of the package resolve.
2. Write its test: a network `TestParser` in the same folder that instantiates ONLY this block, drives it, and
   `assert`s the values that come out (the `properties { test: { terminate: "mon.finished" } }`
   + monitor-task shape of `cg_context.md`). Give the test **exactly ONE monitor task** -- the one
   holding `finished` -- and read every output there, in the order the block produces them. With
   several monitor tasks the simulator can end the run when the first one finishes and skip the
   others' checks, and still report a pass. Run it with
   `cg_simulate(path="src/TestParser.cg", package_dir="src")`.
3. **Make the test fail once on purpose**: change one constant in the block, confirm the test
   goes red, change it back. A test that cannot fail cannot protect you.
4. Mark it LOCKED in STATUS. From now on, do not edit a locked block casually: if it must
   change, re-run its own test before going on.

Name a test network `TestXxx` (capital T) and it also runs on the Verilog simulator
(`cg_simulate(..., simulator="iverilog")`); do that at least once per subsystem — the
simulator and the generated hardware can disagree, and only the second one ships.

---

## Phase 4 — integration: one seam at a time

- Add ONE locked block to the growing network, re-run, then the next. Never wire five at once.
- Before connecting two blocks, read their row in the Links table and check both ends against
  it: width, protocol, framing. Fix the table first if it was wrong, then both blocks, then
  both blocks' tests — in that order.
- Drive every block's test **both back-to-back and paced** (a value every cycle, and a value
  every few cycles with pauses). A block that only ever saw back-to-back input will meet a
  pausing producer at integration: a block can pass every unpaced test and break the first time
  its input pauses mid-frame.
- Mind latency: if two paths meet (data and its checksum), count the cycles on each; the shorter
  one needs a FIFO or a held value. Write the counts in DESIGN.md.

**When the top fails and every block passes on its own, the bug is at a seam.** Bisect:

1. Pick the seam in the middle of the chain. Replace everything upstream of it with a small
   source task that replays the values the upstream SHOULD produce (from the Links table or a
   passing block test).
2. Passes → the bug is upstream of the seam; fails → downstream. Repeat on that half.
3. At the failing seam, compare the two ends with the Links table: width, protocol, framing,
   who waits. Fix the table, then the code.

Do not "fix" a top-level failure by editing a locked block until a smaller test reproduces the
failure in that block.

---

## Keeping each step small enough to finish

- One block per step. Load `DESIGN.md`, that block, its test — nothing else.
- A change to an interface touches three places: the Links table, both blocks, both tests.
  Do them in one step, and re-run both tests.
- Never rewrite a whole file to fix one diagnostic; fix the reported line (`cg_context.md`).
- After every step, update STATUS **before** doing anything else. If the session ends there,
  the next one starts from STATUS.
- When you report progress, quote the test, its check count and its `verified.sha256`, not
  "it works".

---

## Checklist — print it at the start of each step

- [ ] I re-read STATUS. I know which block I am on and which rung.
- [ ] Everything below this rung is LOCKED (green, asserting, failed once on purpose).
- [ ] This block matches its row(s) in the Links table.
- [ ] `cg_check` clean with `package_dir`; its own test passes with checks > 0.
- [ ] Tried paced AND back-to-back input where the block takes a stream.
- [ ] Updated STATUS (state, check count, note).
