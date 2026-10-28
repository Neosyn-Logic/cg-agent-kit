# Walkthrough — a LARGE design: Neosyn's Intel 8088 CPU

How a ~2,200-line, 24-task C⏚ CPU is organised and built, and the test ladder that made it
converge. Read `cg_large_designs.md` first. (The core's source is a licensed Neosyn product and
is not reproduced here; the structure and the method carry over.)

**What it does.** Runs 8088 programs: it fetches instruction bytes over an 8-bit bus with a
20-bit address, decodes and executes them, and reads and writes memory through the same bus.

---

## 1. Two units and a narrow interface

```
CPU                                   (bus: in data_i; out addr, data_o)
├── ExecutionUnit (EU)                decode and execute
│   ├── InstrDecode                   instruction bytes -> opcode, mod/reg/r_m, immediate, branch info
│   ├── Execute                       the control FSM: sequences each instruction
│   ├── RegisterFile                  itself a small network (two half-register banks, routing)
│   ├── ALU                           combinational
│   ├── Flags
│   ├── ComputeEA                     effective address from mod/r_m + displacement
│   ├── MemRequest                    turns a memory access into a request to the BIU
│   ├── BranchDecode, BranchExec      jumps and conditional branches
│   └── writeback (inline task)
└── BusInterfaceUnit (BIU)            everything that touches the bus
    ├── MemBridge                     EU memory requests -> bus cycles -> the data back
    ├── BranchBridge                  a taken branch -> new fetch address
    ├── BusController                 the bus-cycle FSM: fetch vs data access, segment + offset
    ├── ByteSplitter                  16-bit writes as two byte cycles
    ├── InstructionQueue              prefetched instruction bytes
    ├── BIU_RF                        segment registers
    └── compute_real (inline task)    segment:offset -> 20-bit address
```

The EU and the BIU meet at about ten ports, and the whole design depends on that list being
right. Write it as the Links table first:

| link | protocol | meaning |
|---|---|---|
| BIU `instr` → EU | `stream u8` | instruction bytes; the EU makes the queue wait when it is busy |
| EU `mem_addr`, `mem_is_write` → BIU | `push` | one memory request per instruction that needs one |
| EU `mem_write_data`, `segment` → BIU | bare, held | read by the BIU when it serves the request |
| BIU `eu_data_out` → EU | `push u16` | the data of a read, once the bus cycles are done |
| EU `ip_delta`, `eu_ip` → BIU | `push` / bare | a taken branch: where to fetch next |
| BIU `redirect_done` → EU | `push bool` | the queue was flushed and refilled from the new address |

Each unit can then be built and tested on its own, against a stub of the other side.

## 2. The ladder — five tiers

| tier | what | example tests | rule |
|---|---|---|---|
| 0 — combinational atoms | ALU, address split/route | `ALU_test` (10 cases incl. zero, max, overflow), address sweeps of every input value | every case you can enumerate |
| 1 — sequential atoms | one task with state, alone | `ComputeEA_test`, `MemRequest`, `ByteSplitter`, `InstructionQueue`, `OperDelayed` | a short scenario of a few cycles, values asserted |
| 2 — first networks | RegisterFile, BusInterfaceUnit | write, read, a gap, read again | tests the WIRING of locked atoms |
| 3 — the pipeline | ExecutionUnit with the bus stubbed | `EU_test_mov_imm`, `EU_test_alu_imm`, `EU_test_branch`, `EU_test_zf`, … | one test per instruction class: drive bytes in, assert the memory request and the register end state |
| 4 — the whole CPU | CPU + a memory model + a program | `CPU_test_mov_rev`, `CPU_test_jmp_near`, `Fibonacci_test` and variants | the program's writes to memory, checked value by value |

Tier 4 tests are named after the one thing each exercises (`jmp_near`, `cmp_imm`, `three_way`),
so a red one says where to look. A whole-program test (Fibonacci) comes last: when it fails, the
per-instruction tests below it say which instruction broke.

## 3. Lessons from building it

- **A program test that does not assert values is worse than none.** The first program tests
  ended with `idle(400); finished = true;` — they "passed" whenever the simulation ran 400
  cycles. For about a week, "Fibonacci passes" meant someone had looked at a bus trace once, and
  each fix broke something no test could see. The way out was the ladder above, bottom-up, each
  rung asserting values before the next was touched. Make a program test watch the bus writes
  and assert each `(address, data)` pair; set `finished` only on a full match, so a wrong run
  times out and fails loudly.
- **Make every test fail once on purpose** (change one expected value or one line of the block).
  One block's test turned out to be wrong itself — it passed against wrong behaviour — and only
  running that block alone, then mutating it, showed it.
- **A red composite test is information.** When the Tier 2 RegisterFile test went red while its
  atoms were green, the cause was neither atom: it was how values held between two of them.
  Keep the red test, fix the cause, do not loosen the test.
- **Stub the other unit.** The EU's Tier 3 tests replace the BIU with a task that hands it
  instruction bytes and answers memory requests from a small array. The EU is then tested
  without a single bus cycle — and the BIU separately, against a stub EU.
- **Keep the control FSM in one task** (`Execute`): it sequences every instruction and talks to
  all the datapath blocks. Datapath blocks stay small and combinational where they can (ALU,
  ComputeEA); state lives in few, named places (registers, flags, the queue).

## 4. The same plan for your large design

A CPU, a DMA engine, a protocol stack with a controller: split it into two or three units that
talk through a short, explicit list of ports; write that list first; build each unit bottom-up
against a stub of the others (atoms → sequential atoms → small networks → the unit); then join
the units and run scenarios named after what they exercise, with a whole-application test last.
Expect 20–35 tasks and 30 or more tests. The STATUS table of `cg_large_designs.md` is what keeps that
many pieces straight.
