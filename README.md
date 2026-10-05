# 8-Bit RISC Processor: Single-Cycle and 3-Stage Pipelined

An 8-bit RISC processor in Verilog HDL, built as **two microarchitectures that share one ISA**:

- **`processor`** is a single-cycle core with CPI = 1.
- **`processor_pipe`** is a 3-stage pipeline (IF / ID / EX) with operand forwarding, early jump resolution and branch flushing.

**ISA:**
- 16-bit instructions, 8-bit datapath.
- 4 general-purpose registers.
- 25 instructions: 15 ALU operations, load/store (direct and register-indirect), load-immediate, JMP / BEQ / BNE, HLT and NOP.
- Five status flags (ZF, PF, CF, OF, AF).
- 256 × 16 instruction ROM, 256 × 8 data RAM, memory-mapped I/O.

**Verification:**
- Both cores are checked against an instruction-level reference model with self-checking testbenches (Icarus Verilog / ModelSim).
- The ALU is verified exhaustively.

**Board:** the Quartus II 13.0 SP1 project targets the Altera DE2 (Cyclone II **EP2C35F672C6**). Both cores run side by side on the board.

```
risc8/
├── rtl/
│   ├── processor.v        single-cycle core
│   ├── processor_pipe.v   3-stage pipelined core
│   ├── decoder.v          instruction decoder (shared)
│   ├── alu.v              15 operations, 5 flags (shared)
│   ├── register_file.v    4 x 8, 2 read ports, 1 write port (shared)
│   ├── instr_rom.v        256 x 16 instruction ROM ($readmemh)
│   └── data_mem.v         256 x 8 RAM + I/O ports at 0xFE / 0xFF
├── board/          DE2 wrapper (step/run, 7-segment, LEDs)
├── mem/            program.asm -> program.hex (demo program)
├── tools/asm.py    two-pass assembler (labels, .equ, all mnemonics)
├── tb/             testbenches, reference model, directed hazard program
├── sim/            run_iverilog.sh, run_modelsim.do
└── quartus/        processor.qpf / .qsf (DE2 pins) / de2_top.sdc
```

## Instruction set

```
R-type   [15:11] opcode | [10:9] Rd | [8:7] Rs | [6:0] 0
I-type   [15:11] opcode | [10:9] Rd | [8]   0  | [7:0] imm8
```

| Opcode | Instruction | Operation | Flags |
|---|---|---|---|
| 00 | `ADD Rd, Rs` | Rd ← Rd + Rs | Z P C O A |
| 01 | `SUB Rd, Rs` | Rd ← Rd − Rs | Z P C(borrow) O A |
| 02 | `AND Rd, Rs` | Rd ← Rd & Rs | Z P, C=O=A=0 |
| 03 | `OR  Rd, Rs` | Rd ← Rd \| Rs | Z P, C=O=A=0 |
| 04 | `XOR Rd, Rs` | Rd ← Rd ^ Rs | Z P, C=O=A=0 |
| 05 | `NOT Rd` | Rd ← ~Rd | Z P, C=O=A=0 |
| 06 | `CMP Rd, Rs` | flags ← Rd − Rs (no write) | Z P C O A |
| 07 | `LSL Rd` | Rd ← Rd << 1 | Z P, C=old b7, O=b7^b6 |
| 08 | `LSR Rd` | Rd ← Rd >> 1 | Z P, C=old b0, O=old b7 |
| 09 | `ROR Rd` | rotate right | Z P, C=old b0 |
| 0A | `ROL Rd` | rotate left | Z P, C=old b7 |
| 0B | `INC Rd` | Rd ← Rd + 1 | Z P C O A |
| 0C | `DEC Rd` | Rd ← Rd − 1 | Z P C O A |
| 0D | `MUL Rd, Rs` | Rd ← low byte of Rd × Rs | Z P, C=O=(high byte ≠ 0) |
| 0E | `DIV Rd, Rs` | Rd ← Rd / Rs | Z P, O=1 on ÷0 (Rd ← 0) |
| 0F | `NOP` | — | — |
| 10 | `LDI Rd, imm` | Rd ← imm | — |
| 11 | `LD  Rd, [addr]` | Rd ← M[addr] | — |
| 12 | `ST  Rd, [addr]` | M[addr] ← Rd | — |
| 13 | `LDR Rd, [Rs]` | Rd ← M[Rs] | — |
| 14 | `STR Rd, [Rs]` | M[Rs] ← Rd | — |
| 15 | `JMP addr` | PC ← addr | — |
| 16 | `BEQ addr` | if ZF: PC ← addr | — |
| 17 | `BNE addr` | if !ZF: PC ← addr | — |
| 18 | `HLT` | stop until reset | — |
| 19–1F | — | executed as NOP | — |

**Flags:**
- **ZF**: zero.
- **PF**: even parity.
- **CF**: carry, borrow, or the bit shifted out.
- **OF**: signed overflow.
- **AF**: carry or borrow out of bit 3.

Only ALU instructions change the flags, so `CMP` → `BEQ` works even with `LDI`/`JMP` in between.

**Memory map (data):**
- `00–FD`: RAM.
- `FE`: output port (LEDs).
- `FF`: input port (switches).

**Reset:** PC = 0; registers, flags, RAM and the output port are all cleared.

## Microarchitecture

### Single-cycle (`processor.v`)

`IMEM[PC]` → decode → read Rd/Rs → ALU or memory → write-back + flags + next PC, all within one clock. The next PC is `PC+1`, the jump/branch target, or `PC` for HLT.

### 3-stage pipeline (`processor_pipe.v`)

```
   IF                    ID                           EX
 +------+  IF/ID   +------------------+  ID/EX  +------------------------------+
 | PC   |--------->| decode, read Rd, |-------->| ALU / data memory / I/O      |
 | IMEM |  instr   | Rs, resolve JMP  |  opA,   | write-back, flags            |
 +------+  pc      +------------------+  opB    | resolve BEQ / BNE / HLT      |
    ^                  ^      ^                 +------------------------------+
    |                  |      +-------- bypass (EX result -> ID operands) ----+
    +---- JMP target --+                                                      |
    +---- branch target (flush IF + ID) ---------------------------------------+
```

All architectural state (registers, flags, memory, output port) is written only in EX and in program order, so the pipeline retires the same instruction stream as the single-cycle core.

| Hazard | Case | Handling | Cost |
|---|---|---|---|
| RAW, register | instruction in ID reads Rd/Rs written by the instruction in EX | bypass EX write-back value into the ID operand (`fwd_a`, `fwd_b`), only for registers the instruction actually reads | 0 cycles |
| RAW, load-use | `LD` followed by a use | loads complete in EX (combinational data memory), so the bypass covers them | 0 cycles |
| Flags | `CMP` / ALU op followed by `BEQ`/`BNE` | flags are written at the end of EX; the branch reaches EX a cycle later | 0 cycles |
| Control, `JMP` | target known in ID | squash the instruction in IF | 1 bubble |
| Control, `BEQ`/`BNE` | predicted not-taken, resolved in EX | if taken, squash IF and ID | 2 bubbles |
| `HLT` | reaches EX | squash ID, freeze PC and EX until reset | — |

Pipeline trace for the start of the demo program (from `tb_cpu -DPIPE`):

```
 cyc | IF | ID | EX | hazard
   5 | IF 04 | ID 03 | EX 02 |
   6 | IF 05 | ID 04 | EX 03 | fwd           CMP R1,R2 gets R2 from LDI R2 in EX
   9 | IF 08 | ID 07 | EX 06 | fwd           STR R0,[R3] gets R0 from ADD R0,R1
  13 | IF 0c | ID 0b | EX 0a |     flush IF+ID   BNE loop taken
  14 | IF 06 | ID -- | EX -- |                   two bubbles
  15 | IF 07 | ID 06 | EX -- |
```

### Performance (demo program, sum 1..10)

| Core | Instructions | Cycles | CPI |
|---|---|---|---|
| single-cycle | 57 | 57 | 1.00 |
| 3-stage pipeline | 57 | 77 | 1.35 (9 taken-branch flushes × 2 bubbles, +2 fill) |

The pipeline's benefit is a shorter critical path per stage, so it can run at a higher clock frequency. Here, though, the 8-bit multiplier/divider still sits in one stage, and the board runs both cores from a clock enable, so fmax was not the goal. Splitting MUL/DIV across cycles is the obvious next step.

## Verification

Run `./sim/run_iverilog.sh`, or `do run_modelsim.do` in ModelSim with `sim/` as the working directory. Every testbench prints **PASS** or **FAIL** by itself.

| Testbench | What it checks | Result |
|---|---|---|
| `tb_alu` | **Exhaustive:** 16 ops × 256 × 256 = 1,048,576 vectors. Result + 5 flags against an independent integer model. | PASS |
| `tb_cpu` (single-cycle) | Instruction-level reference model stepped on every retirement. Each retirement checks PC and instruction; every clock checks registers, flags, output port and the stored byte; full RAM is compared after each program. **Programs:** demo (golden results), directed hazard program, and 300 random 256-word programs with random input port, random clock-enable and mid-run resets (≈104k instructions). | PASS |
| `tb_cpu -DPIPE` (pipeline) | The same testbench and the same programs. ≈70k instructions retired, 6.8k forwards, 2.5k branch flushes, 2.8k jump squashes exercised. | PASS |
| `tb_de2_top` | Board wrapper. Step mode decodes the 7-segment outputs for both cores; run mode checks that both reach HLT with LEDR = 0x37. Also passes on the Yosys gate-level netlist. | PASS |

**The tests catch real bugs.** Each of these deliberately injected faults makes `tb_cpu -DPIPE` FAIL:
- removing the Rd bypass;
- removing the Rs bypass;
- not flushing on a taken branch;
- not squashing after JMP;
- forwarding from a bubble.

**Synthesis check:** Yosys synthesis of the full board design infers no latches.

## Running on the DE2 board

1. **Open the project.** In Quartus II 13.0 SP1, open `quartus/processor.qpf`. The top level is `de2_top`, and all 106 pins are already assigned.
2. **Compile.** Choose Processing → Start Compilation. Then check that TimeQuest reports no negative slack.
3. **Prepare the board.** Set the DE2's RUN/PROG switch to **RUN**. Connect the USB-Blaster port.
4. **Program the FPGA.** Open Tools → Programmer, select `output_files/processor.sof` in JTAG mode, and click Start.

| Control | Function |
|---|---|
| KEY[0] | reset |
| KEY[1] | one clock step (both cores) |
| SW[17] | 0 = step, 1 = run (~2 clocks/s) |
| SW[16] | display single-cycle (0) or pipelined (1) core |
| SW[15:14] | register shown on HEX1-0 |
| SW[7:0] | input port (0xFF) |

| Display | Shows |
|---|---|
| HEX7-6 | PC |
| HEX5-2 | instruction in the last stage (`----` = bubble) |
| HEX1-0 | register |
| LEDR[7:0] | output port |
| LEDR[17] | HLT |
| LEDG[0..4] | ZF PF CF OF AF |
| LEDG[5] | forwarding |
| LEDG[6] | flush |

**Demo:**
1. Set SW[7:0] = `00001010` (N = 10) and press KEY[0].
2. Set SW[17] = 1 to run.
3. Both cores end with LEDR = `0011 0111` (0x37 = 55) and LEDR[17] on.
4. With SW[16] = 1 and step mode, LEDG[6] lights and HEX5-2 show `----` on every taken `BNE`.

**To run your own program:** write `mem/program.asm`, run `python3 tools/asm.py mem/program.asm mem/program.hex`, and recompile.

## Version history

- **v2:**
  - 16-bit instruction word.
  - LDI, LD/ST, LDR/STR, JMP, BEQ/BNE and HLT.
  - Data memory with memory-mapped I/O.
  - 3-stage pipelined core with forwarding and flushing.
  - Instruction-level reference model and random-program verification of both cores.
- **v1:**
  - Single-cycle core, 8-bit instructions, 15 ALU instructions.
  - Corrected the original lab design:
    - register file wired into the datapath;
    - edge-triggered clocking instead of latch-inferring `always @(a)` blocks;
    - decode of the current (not previous) opcode;
    - rotate directions, AF formula and CMP write-back;
    - DE2 pin assignments.
