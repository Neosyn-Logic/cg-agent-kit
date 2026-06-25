# The C⏚ RV32I reference core — patterns for building a CPU in Cg

This is reference knowledge for the **RISC-V RV32I core written in C⏚**, the
Tier-4 integration design in the `cg-ip-cores/RISC-V/` tree. It is a worked,
fully-verified example of a non-trivial processor in Cg, and — more usefully for
an LLM — a set of **reusable patterns** for expressing CPU-shaped hardware in
C⏚. Read this when asked to build or extend a processor, an instruction
decoder, a datapath, a stack machine, or any control-heavy design in Cg.

The core is *reference IP*: it gates the compiler, it is not a product feature.
Everything here is proven on **both backends** — the bytecode simulator
(value-asserting) and the Verilog backend (`iverilog -t null` elaboration).

---

## What the design is

A complete **single-cycle RV32IM integer core** with a **loadable program**.

- One task, `Rv32iCpu`, holds the whole datapath. The full RV32I base ISA is
  implemented: ALU reg/imm, LUI, AUIPC, all branches (BEQ/BNE/BLT/BGE/BLTU/BGEU),
  JAL/JALR, and the complete load/store width set (LW/LH/LHU/LB/LBU, SW/SH/SB).
  Plus the **M extension** (MUL/MULH/MULHSU/MULHU, DIV/DIVU/REM/REMU). FENCE/
  FENCE.I and CSR accesses are non-trapping no-ops (Zifencei/Zicsr: in-order core,
  no CSR file → CSRs read 0, writes dropped); ECALL/EBREAK halt.
- The program is **streamed in at run time** over an `in push u32 prog` boot
  port — first word = program length, then that many instruction words — so
  there is exactly *one* copy of the datapath and a new test program is just
  data fed by a small ROM driver task. (No per-program core copy; no baked-in
  instruction-memory block to regenerate.)
- Harvard memory: word-addressed `imem` (filled by the boot stream) and
  word-addressed `dmem` (1024 B, enough for a recursion stack). Every store
  pulses `(obs_addr, obs_data)` so a testbench can observe results.

Programs proven on it:
- **Rv32iCore_test** — instruction self-test: iterative Fibonacci + shift /
  compare / logic / load / LUI / jal+ret + sub-word load/store + full branch
  coverage (incl. the signed-vs-unsigned contrast) + AUIPC. 42 asserted stores.
- **Rv32iSort_test** — an in-place bubble sort (nested loops, `lbu`/`sb`).
- **Rv32iRecFib_test** — recursive `fib(0..7)` with a real stack (per-frame
  `ra`/`s0` spill, `sp` grows down, re-entrant calls). Exercises the full
  RISC-V calling convention — the basis for running compiled C.
- **Rv32iMemcpy / Rv32iStrlen / Rv32iGcd / Rv32iCrc8 / Rv32iMulDiv** — a library
  of small real programs (block copy, string length, Euclid's GCD by
  subtraction, bitwise CRC-8, and the M-extension mul/div/rem). Each is just a
  ROM driver + checker on the one core — no datapath copy.

---

## Reusable C⏚ patterns (the part that generalises)

### 1. Single-cycle datapath ⇒ ONE monolithic task, not a network
C⏚ ports are **synchronous**: a port read sees the value written on the
*previous* cycle. So spreading a single-cycle datapath across a task network
makes it inherently multi-cycle/pipelined. Keep fetch→decode→execute→writeback
in one `loop()` operating on **local variables**; the only sequential state is
`pc`, the register file, `imem`, and `dmem` (task fields). This gives true
single-cycle semantics. (A *pipelined* CPU is the opposite choice — then a task
network is the right tool, and the cross-task latency is the pipeline.)

### 2. Shift by a runtime amount ⇒ barrel-shifter mux tree
C⏚ has no shift-by-a-variable. Build it from literal power-of-two shifts gated
by each bit of the shift amount:
```
u32 x = a;
if (shamt[0]) { x = x << 1;  }
if (shamt[1]) { x = x << 2;  }
if (shamt[2]) { x = x << 4;  }
if (shamt[3]) { x = x << 8;  }
if (shamt[4]) { x = x << 16; }   // x = a << shamt, shamt in 0..31
```
Same shape for right shifts; for arithmetic right shift do it on an `i32` so the
sign extends. `cg_suggest_for_error` maps a "shift by a variable" rejection to
the BarrelShift recipe.

### 3. Unsigned compare ⇒ widen to one extra bit
A full-width compare in C⏚ is **signed** by default, so `a < b` on `u32`
mis-handles values with the top bit set. Widen both sides by one bit so the MSB
is a value bit, not a sign bit:
```
wb_val = ((u33) a < (u33) op2) ? 1 : 0;   // SLTU / BLTU (unsigned)
wb_val = ((i32) a < (i32) op2) ? 1 : 0;   // SLT  / BLT  (signed)
```
This is exactly what distinguishes `BLT -1,1` (taken) from `BLTU -1,1` (not
taken). The pattern: for unsigned semantics on N-bit data, compute in `u(N+1)`.

### 4. Sub-word load ⇒ barrel lane-select + sign/zero extend
Memory is word-addressed. Select the addressed byte/half by barrel-shifting it
down to bit 0 (the `offset*8` shift is itself a runtime value → mux tree), then
narrow + extend with a cast:
```
u2 lbo = (u2)(addr & 0x3);
u32 lsh = word;
if (lbo[0]) { lsh = lsh >> 8;  }
if (lbo[1]) { lsh = lsh >> 16; }
wb = (u32)(i32)(i8) lsh;   // LB  sign-extend    (mirror the i12 immediate idiom)
wb = (u32)(u8) lsh;        // LBU zero-extend
```
`(i8)`/`(u8)`/`(i16)`/`(u16)` narrowing casts work — they take the low N bits;
`(i32)` then sign-extends. Same idiom as `i12 immI = (i12)(inst >> 20)`.

### 5. Sub-word store ⇒ read-modify-write with a barrelled mask
Word-addressed RAM can't write a single byte directly. Barrel the data *and* a
same-width mask into the addressed lane, then merge over the existing word:
```
u32 data = (u32)(u8) b;  u32 mask = 0xFF;
if (sbo[0]) { data = data << 8;  mask = mask << 8;  }
if (sbo[1]) { data = data << 16; mask = mask << 16; }
dmem[addr >> 2] = (word & ~mask) | data;   // other bytes survive
```

### 6. Multiply ⇒ wide product; divide ⇒ unrolled shift-subtract (no `/`)
C⏚ **rejects `/` and `%`** (there is no hardware divider) — `cg_suggest_for_error`
points a division rejection at the bit-serial divide recipes. For a *multiply*,
compute in a double-width type and take the slice:
```
wb = (u32)((u64) a * (u64) b);              // low 32 (MUL)
i64 p = (i64)(i32) a * (i64)(i32) b;        // signed; (u32)(p >> 32) = high 32 (MULH)
```
For a *divide*, do a combinational restoring division — a constant-bound loop
(unrolls) on unsigned magnitudes using only `<<1`/`>>31`, then fix up signs:
```
u32 uq = 0; u32 ur = 0; u6 k = 0;
for (k = 0; k < 32; k = k + 1) {
    ur = (u32)((ur << 1) | ((ua >> 31) & 1));   // bring down next bit
    ua = (u32)(ua << 1);  uq = (u32)(uq << 1);
    if ((u33) ur >= (u33) ub) { ur = (u32)(ur - ub); uq = (u32)(uq | 1); }
}
// signed: negate uq if operand signs differ; remainder takes the dividend's sign
```
Avoid `>> k`/`<< k` with the loop index even though the loop unrolls — stick to
literal shifts so it can never degrade to a (rejected) shift-by-variable.

### 7. Loadable program ⇒ count-prefixed boot stream over a push port
To decouple a program/config blob from the datapath (so one core runs many
programs), add an `in push u32 prog` and a load phase that runs before the main
work:
```
if (!loaded) {
    if (prog.available()) {
        u32 w = prog.read();
        if (!gotCount) { progCount = w; gotCount = true; }
        else { imem[loadIdx] = w; loadIdx = loadIdx + 1;
               if (loadIdx == progCount) { loaded = true; } }
    }
} else if (!halted) { /* ... execute ... */ }
```
The producer is a small ROM driver task with `out push u32 prog` that writes the
count then the words, one per cycle. Wire it in the network with
`cpu.reads(rom.prog)`. Producer and consumer stay in 1:1 lockstep (one word per
cycle each), so the push channel is lossless.

### 8. Testbench: lossless per-cycle capture, then deferred asserts
A single-cycle producer can emit an event (store) on consecutive cycles. But
`assert` lowers to **FSM fence states**, so a checker that asserts inline spans
>1 cycle and *drops back-to-back events*. The fix: capture losslessly into
arrays in a one-cycle combinational branch (reads + array writes only, no
assert), and defer all assertions until capture is complete (by then the program
has halted, so check timing no longer matters):
```
if (n < N) { if (dut.obs.available()) { rec[n] = dut.obs.read(); n = n + 1; } }
else       { /* all captured — assert rec[0..N] now */ }
```

### 9. Trace-noisy programs ⇒ address-filtered checker
If a program makes many intermediate stores you don't want to predict (sort
swaps, recursion stack spills), write results to a dedicated **result region**
and have the checker record only stores in that address range (it still reads
every pulse each cycle to stay lossless, just discards the rest):
```
if (dut.obs_addr.available()) {
    u32 addr = dut.obs_addr.read(); u32 data = dut.obs_data.read();
    if (addr < 32) { rec_a[n] = addr; rec_d[n] = data; n = n + 1; }  // results only
}
```

---

## How to add a new program (no datapath change)

1. Write it in `tools/<name>.s` (RISC-V asm; the in-repo `tools/rvasm.py`
   supports the instruction subset + labels + pseudo-ops the demos use).
2. Assemble: `python3 tools/rvasm.py tools/<name>.s` → ready-to-paste
   `imem[i] = 0x...;` lines (correct-by-construction encodings).
3. New test network `Rv32i<Name>_test.cg`: a `rom` driver task whose `mem[]` is
   those words (paste the rvasm output; change `imem` → `mem`), a
   `cpu = new Rv32iCpu()`, and a `checker` task. Wire `cpu.reads(rom.prog)` and
   `checker.reads(cpu.obs_addr, cpu.obs_data)`.
4. Verify with `cg_simulate` (bytecode, value-asserting) and add it to
   `run_tier_atoms.sh`.

GOTCHA from experience: never regex-replace a `mem[...]`/`imem[...]` init block
by matching a contiguous run of `imem\[...\]` lines — an interior comment breaks
the run and you leave a stale tail that overwrites later entries. Write the
block fresh, and after generating grep for duplicate `mem[i] =` assignments.

---

## Files and the gate

```
cg-ip-cores/RISC-V/
  src/com/neosyn/riscv/
    alu/ALU.cg                cpu/Rv32iCpu.cg            (the loadable core)
    decode/ImmDecode.cg       cpu/Rv32iCore_test.cg      (instruction self-test)
    regfile/RegisterFile.cg   cpu/Rv32iSort_test.cg      (bubble sort)
                              cpu/Rv32iRecFib_test.cg    (recursive Fibonacci)
  tools/rvasm.py  fib_selftest.s  sort_demo.s  recfib.s
  run_tier_atoms.sh           (Tier 0/1 atoms + Tier 4 CPU programs + Verilog elab)
```
Regression gate: `bash run_tier_atoms.sh` — bytecode-simulates every atom and
CPU program (value-asserting) and elaborates the generated Verilog with iverilog.
