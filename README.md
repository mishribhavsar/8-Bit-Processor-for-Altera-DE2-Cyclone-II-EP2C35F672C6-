# 8-Bit RISC Processor: Single-Cycle, Pipelined and Out-of-Order

An 8-bit RISC processor in Verilog HDL, built as **three microarchitectures of one ISA**. The three cores run side by side on an Altera DE2 board.

| Core | File | What it is |
|---|---|---|
| Single-cycle | `rtl/processor.v` | CPI = 1, combinational MUL/DIV |
| 3-stage pipeline | `rtl/processor_pipe.v` | IF / ID / EX, forwarding, early JMP resolution, branch flush, stall on the multi-cycle MUL/DIV unit |
| **Out-of-order** | `rtl/processor_ooo.v` | Tomasulo + reorder buffer, **register renaming that includes the FLAGS register**, 3 reservation stations, common data bus, static BTFN prediction, precise recovery |

**Headline result:** on a multiply-bound loop, the out-of-order core runs **1.67× faster** than the in-order pipeline (CPI 2.82 → 1.68). It reaches the throughput limit of its single 9-cycle multiply/divide unit.

**Why flag renaming matters:** turn it off (an ablation, `FLAG_RENAME = 0`) and the out-of-order core becomes **slower than the in-order pipeline**. With it on, the core is 1.44–1.88× faster. The five x86-style condition flags make every ALU instruction a producer of a new flags value, so renaming FLAGS is what lets out-of-order execution pay off with this ISA.

- **ISA:**
  - 16-bit instructions, 8-bit datapath, 4 registers.
  - 25 instructions: 15 ALU operations, load/store (direct and register-indirect), LDI, JMP/BEQ/BNE, HLT, NOP.
  - 5 flags (ZF, PF, CF, OF, AF).
  - 256 × 16 instruction ROM, 256 × 8 data RAM, memory-mapped I/O.
- **Verification:**
  - All three cores are checked against one instruction-level reference model at every retired instruction.
  - Each runs directed tests plus 300 random programs.
  - The ALU and the MUL/DIV unit are verified exhaustively.
- **Tools:** Icarus Verilog / ModelSim, Quartus II 13.0 SP1, Cyclone II **EP2C35F672C6**.

```
risc8/
├── rtl/
│   ├── processor.v        single-cycle core
│   ├── processor_pipe.v   3-stage pipelined core
│   ├── processor_ooo.v    out-of-order core (Tomasulo + ROB + flag renaming)
│   ├── muldiv.v           iterative MUL/DIV unit (9 cycles)
│   ├── decoder.v          instruction decoder (shared)
│   ├── alu.v              15 operations, 5 flags (shared)
│   ├── register_file.v    4 x 8 (shared)
│   ├── instr_rom.v        256 x 16 ROM
│   └── data_mem.v         256 x 8 RAM + I/O at 0xFE / 0xFF
├── bench/          benchmark programs (alu_loop, mul_loop, muldiv_mix)
├── board/          DE2 wrapper running all three cores
├── docs/ooo_design.md   how the out-of-order core works, step by step
├── mem/            program.asm -> program.hex (board demo)
├── tools/asm.py    two-pass assembler
├── tb/             testbenches, reference model, directed hazard program
├── sim/            run_iverilog.sh, run_modelsim.do
└── quartus/        processor.qpf / .qsf (DE2 pins) / de2_top.sdc
```

## Results

All numbers come from `tb_bench`, which runs the three cores on the same program and checks each against the reference model.

The single-cycle core uses a combinational multiply/divide (CPI = 1, but a very long critical path). The pipeline and the out-of-order core share the same 9-cycle iterative unit, so their comparison is like-for-like.

| Benchmark (N) | Instr. | Pipeline CPI | OoO CPI | OoO speed-up | OoO CPI, flag renaming **off** |
|---|---|---|---|---|---|
| `alu_loop` (20) | 107 | 1.37 | **1.27** | 1.08× | 2.02 |
| `mul_loop` (100) | 598 | 2.82 | **1.68** | **1.67×** | 3.16 |
| `muldiv_mix` (100) | 895 | 3.21 | **2.23** | 1.43× | 3.22 |

**What the numbers mean:**
- **`mul_loop`:** the out-of-order core needs about 10 cycles per iteration. That's the throughput limit of the single multiply/divide unit (9 cycles plus the CDB handshake), so the core keeps that unit busy all the time. The pipeline needs about 17 cycles per iteration.
- **Flag renaming off:** `CMP` → `BNE` forces each branch to wait until the compare commits. Loop overhead then can't overlap the multiply, and the core falls behind the pipeline.
- **`alu_loop`:** no multiplies, so the gain comes only from static prediction (backward branches predicted taken). It removes most of the pipeline's taken-branch flushes.

## Instruction set

```
R-type   [15:11] opcode | [10:9] Rd | [8:7] Rs | [6:0] 0
I-type   [15:11] opcode | [10:9] Rd | [8]   0  | [7:0] imm8
```

| Opcode | Instruction | Operation | Flags |
|---|---|---|---|
| 00 | `ADD Rd, Rs` | Rd ← Rd + Rs | Z P C O A |
| 01 | `SUB Rd, Rs` | Rd ← Rd − Rs | Z P C(borrow) O A |
| 02–04 | `AND` / `OR` / `XOR Rd, Rs` | bitwise | Z P, C=O=A=0 |
| 05 | `NOT Rd` | Rd ← ~Rd | Z P, C=O=A=0 |
| 06 | `CMP Rd, Rs` | flags ← Rd − Rs | Z P C O A |
| 07 / 08 | `LSL` / `LSR Rd` | shift by 1 | Z P C O |
| 09 / 0A | `ROR` / `ROL Rd` | rotate by 1 | Z P C |
| 0B / 0C | `INC` / `DEC Rd` | ± 1 | Z P C O A |
| 0D | `MUL Rd, Rs` | Rd ← low byte of Rd × Rs | Z P, C=O=(high byte ≠ 0) |
| 0E | `DIV Rd, Rs` | Rd ← Rd / Rs | Z P, O=1 on ÷0 (Rd ← 0) |
| 0F | `NOP` | — | — |
| 10 | `LDI Rd, imm` | Rd ← imm | — |
| 11 / 12 | `LD` / `ST Rd, [addr]` | Rd ↔ M[addr] | — |
| 13 / 14 | `LDR` / `STR Rd, [Rs]` | Rd ↔ M[Rs] | — |
| 15 | `JMP addr` | PC ← addr | — |
| 16 / 17 | `BEQ` / `BNE addr` | branch on ZF | — |
| 18 | `HLT` | stop until reset | — |

**Memory map:**
- `00–FD`: RAM.
- `FE`: output port (LEDs).
- `FF`: input port (switches).

**Reset** clears PC, registers, flags, RAM and the output port.

## Microarchitectures

### Single-cycle
Fetch, decode, operand read, ALU or memory, write-back and next PC all happen in one clock.

### 3-stage pipeline

| Hazard | Handling | Cost |
|---|---|---|
| RAW (register, incl. load-use) | EX → ID bypass, only for registers the instruction reads | 0 |
| Flags (`CMP` → `BEQ`) | flags written at the end of EX, read by the branch a cycle later | 0 |
| `JMP` | resolved in ID, squash IF | 1 bubble |
| `BEQ`/`BNE` taken | predicted not-taken, resolved in EX, squash IF + ID | 2 bubbles |
| `MUL`/`DIV` | 9-cycle unit, whole pipeline stalls | 8 stall cycles |

### Out-of-order (Tomasulo + ROB)

```
 fetch -> dispatch --------------------------------------------> ROB (8) --> commit
           | rename (RAT: R0-R3 + FLAGS)                          ^  in order
           v                                                      |
   RS_ALU (4) --> ALU (1 cyc) ----\                               |
   RS_MD  (2) --> MUL/DIV (9 cyc) --> CDB (1/cycle, oldest first) +--> wake up RS
   RS_LS  (4) --> load/store -----/
```

- **Dispatch (in order):**
  - allocate a ROB entry;
  - rename the destination register and/or FLAGS to that ROB tag;
  - read each operand from the register file, the ROB, or the CDB in that same cycle, otherwise record the tag it is waiting for;
  - place the instruction in a reservation station.
- **JMP and BTFN prediction:** JMP and backward branches (predicted taken) redirect fetch at dispatch.
- **Issue (out of order):** each reservation station sends its oldest ready instruction to its unit.
- **Write-back:** one CDB broadcast per cycle, given to the oldest finished result. It marks the ROB entry ready and wakes up the reservation stations waiting on that tag.
- **Flag renaming:**
  - Every flag-setting instruction allocates a new FLAGS version; BEQ/BNE wait on that tag.
  - Back-to-back ALU instructions no longer serialise on the flags (no WAW conflict), and branches wake up as soon as their compare executes.
- **Memory ordering:**
  - Stores write memory at commit.
  - A load issues only after every older store has committed, so no store-to-load forwarding is needed.
- **Commit (in order):**
  - The head of the ROB updates the register file, flags and memory.
  - A mispredicted branch flushes the ROB, reservation stations, rename table and fetch, then redirects.
  - HLT stops the core.

`docs/ooo_design.md` walks through one loop iteration cycle by cycle.

## Verification

Run `./sim/run_iverilog.sh` (about 40 s), or `do run_modelsim.do` from `sim/` in ModelSim.

| Testbench | What it checks | Result |
|---|---|---|
| `tb_alu` | All 16 ops × 256 × 256 (1,048,576 vectors), result + 5 flags | PASS |
| `tb_muldiv` | All 2 ops × 256 × 256 (131,072 operations), result + flags + exact latency | PASS |
| `tb_cpu` (×3 cores) | Reference model stepped on every retirement: PC, instruction, registers, flags, output port, stored byte, full RAM per program; a liveness check catches deadlocks. **Programs:** demo, directed hazard program, 300 random 256-word programs with random clock enable and resets | PASS ×3 |
| `tb_bench` | All three cores on 3 benchmarks must match the model; reports CPI (also built with `FLAG_RENAME = 0`) | PASS |
| `tb_de2_top` | Board wrapper: 7-segment readback in step mode, all cores reach HLT with LEDR = 0x37. Also passes on the Yosys gate-level netlist. | PASS |

**The tests catch real bugs.** Each of these injected faults makes the corresponding test FAIL or deadlock.
- **Out-of-order core:**
  - no flag renaming;
  - loads bypassing older stores;
  - missing CDB wake-up;
  - missing same-cycle CDB capture at dispatch;
  - RAT freed without a tag check;
  - no mispredict recovery;
  - CDB starvation.
- **Pipeline:**
  - missing Rd/Rs bypass;
  - no branch flush;
  - no JMP squash;
  - no MUL/DIV stall.

**Synthesis check:** Yosys synthesis of the full board design (three cores) infers no latches.

**Testbench note:** in random tests the out-of-order core gets a fixed input-port value per program. It reads the switches when the load *executes* rather than when it commits, which is normal for memory-mapped input without side effects.

## Running on the DE2 board

1. **Open the project.** In Quartus II 13.0 SP1, open `quartus/processor.qpf`. The top level is `de2_top`, and all 106 pins are assigned.
2. **Compile.** Choose Processing → Start Compilation. Then check that TimeQuest reports no negative slack.
3. **Prepare the board.** Set the RUN/PROG switch to **RUN**. Connect the USB-Blaster port.
4. **Program the FPGA.** Open Tools → Programmer, select `output_files/processor.sof` in JTAG mode, and click Start.

| Control | Function |
|---|---|
| KEY[0] | reset |
| KEY[1] | one clock step (all cores) |
| SW[17] | 0 = step, 1 = run (~2 clocks/s) |
| SW[16:15] | displayed core: 00 single-cycle, 01 pipeline, 1x out-of-order |
| SW[14:13] | register on HEX1-0 |
| SW[7:0] | input port |

| Display | Shows |
|---|---|
| HEX7-6 | PC |
| HEX5-2 | last-stage instruction / ROB head (`----` if empty) |
| LEDR[7:0] | output port |
| LEDR[17] | HLT |
| LEDG[0..4] | ZF PF CF OF AF |
| LEDG[5] | forward / CDB |
| LEDG[6] | flush |

**Demo:** set SW[7:0] = 10, press KEY[0], then set SW[17] = 1. All three cores finish with LEDR = 0x37 (55).

## Version history

- **v3:**
  - Out-of-order core (Tomasulo + ROB + flag renaming, BTFN prediction).
  - Iterative MUL/DIV unit; the pipeline stalls on it.
  - Benchmark suite with CPI comparison and the flag-renaming ablation.
  - Board runs all three cores.
- **v2:**
  - 16-bit ISA with load/store, branches, HLT and memory-mapped I/O.
  - 3-stage pipeline with forwarding and flushing.
  - Instruction-level reference model and random-program verification.
- **v1:**
  - Corrected the original single-cycle lab design: register file wired in; edge-triggered clocking; current-opcode decode; rotate, AF and CMP fixes.
  - Self-checking testbenches and DE2 pin assignments.
