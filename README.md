# 8-Bit Single-Cycle RISC Processor on FPGA

A single-cycle 8-bit processor in Verilog HDL. It has a program counter, a 256 × 8 instruction ROM, a control unit, a 4 × 8 register file, and an ALU with 15 arithmetic, logic and shift instructions plus NOP. A flag register holds five status flags (ZF, PF, CF, OF, AF).

It is verified with self-checking testbenches (Icarus Verilog / ModelSim) and comes with a Quartus II 13.0 SP1 project for the Altera DE2 board (Cyclone II **EP2C35F672C6**).

```
risc8/
├── rtl/            processor core (synthesisable Verilog-2001)
│   ├── processor.v       top of the core: wires the datapath together
│   ├── pc.v              8-bit program counter
│   ├── instr_rom.v       256 x 8 instruction ROM ($readmemh)
│   ├── control_unit.v    instruction decoder
│   ├── register_file.v   4 x 8 registers, 2 read ports, 1 write port
│   └── alu.v             15 operations, 5 flags
├── board/          DE2 wrapper: step/run control, 7-segment, LEDs
├── mem/            program.asm (source) and program.hex (ROM image)
├── tools/asm.py    assembler: .asm -> .hex
├── tb/             self-checking testbenches + reference model
├── sim/            run_iverilog.sh, run_modelsim.do
└── quartus/        processor.qpf / .qsf (DE2 pin assignments) / .sdc
```

## Architecture

```
          +------+     +-----------+  instr  +--------------+
   +----->|  PC  |---->| 256x8 ROM |-------->| Control unit |
   |      +------+     +-----------+         +--------------+
   |  +1     |                                  | rd rs | alu_op, reg_write, flag_write
   +---------+                                  v       v
                      +------------------+  Rd  +-------+  result  +----------------+
                      |  Register file   |----->|       |--------->| write-back (Rd)|
                      |  R0 R1 R2 R3     |  Rs  |  ALU  |          +----------------+
                      |                  |----->|       |--flags-->  Flag register
                      +------------------+      +-------+           {AF OF CF PF ZF}
```

**Single-cycle (CPI = 1).** Fetch, decode, register read, ALU and write-back are all combinational between the clocked elements (PC, registers, flags). Every enabled clock edge finishes one instruction. The whole design runs on `CLOCK_50`, and `en` is a clock enable. There are no divided or gated clocks.

## Instruction set

Format: `[7:4] opcode | [3:2] Rs | [1:0] Rd`. A two-operand op computes `Rd ← Rd op Rs`; a one-operand op computes `Rd ← op Rd`.

| Opcode | Mnemonic | Operation | Flags affected |
|---|---|---|---|
| 0 | `ADD Rd, Rs` | Rd ← Rd + Rs | Z P C O A |
| 1 | `SUB Rd, Rs` | Rd ← Rd − Rs | Z P C(borrow) O A |
| 2 | `AND Rd, Rs` | Rd ← Rd & Rs | Z P, C=O=A=0 |
| 3 | `OR  Rd, Rs` | Rd ← Rd \| Rs | Z P, C=O=A=0 |
| 4 | `XOR Rd, Rs` | Rd ← Rd ^ Rs | Z P, C=O=A=0 |
| 5 | `NOT Rd` | Rd ← ~Rd | Z P, C=O=A=0 |
| 6 | `CMP Rd, Rs` | flags ← Rd − Rs (no write) | Z P C O A |
| 7 | `LSL Rd` | Rd ← Rd << 1 | Z P, C=old b7, O=b7^b6 |
| 8 | `LSR Rd` | Rd ← Rd >> 1 | Z P, C=old b0, O=old b7 |
| 9 | `ROR Rd` | rotate right | Z P, C=old b0 |
| A | `ROL Rd` | rotate left | Z P, C=old b7 |
| B | `INC Rd` | Rd ← Rd + 1 | Z P C O A |
| C | `DEC Rd` | Rd ← Rd − 1 | Z P C O A |
| D | `MUL Rd, Rs` | Rd ← low byte of Rd × Rs | Z P, C=O=(high byte ≠ 0) |
| E | `DIV Rd, Rs` | Rd ← Rd / Rs | Z P, O=1 on divide by 0 (Rd ← 0) |
| F | `NOP` | — | unchanged |

**Flags:**
- **ZF**: result is zero.
- **PF**: even parity (an even number of 1s).
- **CF**: carry, borrow, or the bit shifted out.
- **OF**: signed overflow.
- **AF**: carry or borrow out of bit 3.

**Reset:**
- PC = 00 and flags = 0.
- R0 ← `SW[7:0]` and R1 ← `SW[15:8]`.
- R2 = 0F and R3 = 01. There is no load-immediate instruction, so reset values are the only way to get operands in.

**Running past the end:** the PC wraps from FF to 00. Unused ROM words are NOP.

## Verification

Run `./sim/run_iverilog.sh`, or `do run_modelsim.do` in ModelSim with `sim/` as the working directory. Every testbench prints **PASS** or **FAIL** by itself, so you never have to judge a waveform by eye.

| Testbench | What it checks | Result |
|---|---|---|
| `tb_alu` | **Exhaustive:** 16 opcodes × 256 × 256 = 1,048,576 vectors. Result + all 5 flags compared against an independent integer reference model. | PASS |
| `tb_processor` | Lock-step reference model of PC, R0–R3 and flags, checked every cycle. Demo program with a printed trace and golden final state. 200 random 256-byte programs with random clock-enable and mid-run resets (≈51k instructions, ≈119k checks). Clock-enable-low hold test. | PASS |
| `tb_de2_top` | Board wrapper. Reset, 5 presses of KEY[1], then it decodes the 7-segment outputs and checks PC, instruction, registers, LEDs and one-instruction-per-press. | PASS |

**The testbenches catch real bugs.** Swapped ROR/ROL, the old AF formula, inverted parity, and CMP writing back each make them FAIL.

**The synthesised netlist was checked too.** The design was synthesised with Yosys: no latches inferred. The resulting gate-level netlist also passes `tb_de2_top`.

### Demo trace (`mem/program.asm`, R0=5A, R1=3C)

Flags are listed as A O C P Z.

```
 PC | instr | ALU | R0 R1 R2 R3 | A O C P Z
 00 |  04   | 96  | 96 3c 0f 01 | 1 1 0 1 0   ADD R0,R1  (signed overflow, half-carry)
 01 |  1c   | 95  | 95 3c 0f 01 | 0 0 0 1 0   SUB R0,R3
 02 |  64   | 59  | 95 3c 0f 01 | 1 1 0 1 0   CMP R0,R1  (flags only)
 03 |  29   | 0c  | 95 0c 0f 01 | 0 0 0 1 0   AND R1,R2
 04 |  3d   | 0d  | 95 0d 0f 01 | 0 0 0 0 0   OR  R1,R3
 05 |  44   | 98  | 98 0d 0f 01 | 0 0 0 0 0   XOR R0,R1
 06 |  50   | 67  | 67 0d 0f 01 | 0 0 0 0 0   NOT R0
 07 |  70   | ce  | ce 0d 0f 01 | 0 1 0 0 0   LSL R0
 08 |  80   | 67  | 67 0d 0f 01 | 0 1 0 0 0   LSR R0
 09 |  a1   | 1a  | 67 1a 0f 01 | 0 0 0 0 0   ROL R1
 0a |  91   | 0d  | 67 0d 0f 01 | 0 0 0 0 0   ROR R1
 0b |  d4   | 3b  | 3b 0d 0f 01 | 0 1 1 0 0   MUL R0,R1  (0x67*0x0D = 0x53B)
 0c |  e4   | 04  | 04 0d 0f 01 | 0 0 0 0 0   DIV R0,R1  (0x3B/0x0D = 4)
 0d |  b2   | 10  | 04 0d 10 01 | 1 0 0 0 0   INC R2     (half-carry)
 0e |  c3   | 00  | 04 0d 10 00 | 0 0 0 1 1   DEC R3     (zero)
 0f |  ec   | 00  | 00 0d 10 00 | 0 1 0 1 1   DIV R0,R3  (divide by zero)
```

## Running on the DE2 board

1. **Open the project.** In Quartus II 13.0 SP1, open `quartus/processor.qpf`. The top level is `de2_top`, and all 106 pins are already assigned.
2. **Compile.** Choose Processing → Start Compilation. Then check that TimeQuest reports no negative slack.
3. **Prepare the board.** Set the DE2's RUN/PROG switch to **RUN**. Connect the USB-Blaster port.
4. **Program the FPGA.** Open Tools → Programmer, select `output_files/processor.sof` in JTAG mode, and click Start.

| Control | Function |
|---|---|
| KEY[0] | reset (loads R0, R1 from switches, PC ← 0) |
| KEY[1] | execute one instruction |
| SW[17] | 0 = step with KEY[1], 1 = run at ~2 instructions/s |
| SW[16] | HEX3-0 show R0 R1 (0) or R2 R3 (1) |
| SW[15:8] / SW[7:0] | reset values of R1 / R0 |

| Display | Shows |
|---|---|
| HEX7-6 | PC |
| HEX5-4 | instruction at PC |
| HEX3-0 | two registers |
| LEDR[7:0] | ALU output of the instruction at PC |
| LEDG[0..4] | ZF PF CF OF AF |
| LEDG[8] | blinks on each instruction |

**Demo:** set SW[15:8] = 0x3C (`0011 1100`) and SW[7:0] = 0x5A (`0101 1010`). Press KEY[0], then step with KEY[1]. The board should follow the trace above.

**To run your own program:** edit `mem/program.asm`, run `python3 tools/asm.py mem/program.asm mem/program.hex`, and recompile.

## Changes from the first version

- **Register file added to the datapath.** It was commented out before, and operand B was a constant 0x0F.
- **Proper clocking.** The `always @(a)` / `always @(clk, PC)` blocks driven by a toggled clock would synthesise to latches and a free-running PC. They are replaced by edge-triggered registers plus combinational logic, with a clock enable.
- **Control-unit timing fixed.** The control unit decoded the *previous* opcode (non-blocking `opcode <=` read in the same block). It is now purely combinational.
- **Rotate directions fixed.** RR and RL were swapped.
- **AF corrected.** It is now the carry into bit 4: `a[4] ^ b[4] ^ sum[4]`.
- **CMP no longer writes back.** It only sets flags.
- **Flags held in a register,** updated only by flag-setting instructions.
- **DE2 board added.** New board wrapper, pin assignments and timing constraints. The old `.qsf` had none.
