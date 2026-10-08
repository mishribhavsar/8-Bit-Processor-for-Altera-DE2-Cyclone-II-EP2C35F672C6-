# Out-of-Order Core: How It Works

This explains `rtl/processor_ooo.v` from the ground up, then walks through a real simulation trace. Everything here comes from the RTL and from `tb/tb_trace_ooo.v`, so you can rerun it and see the same thing.

## 1. Why out-of-order at all

The MUL/DIV unit takes 9 cycles. In the 3-stage pipeline, a `MUL` sits in EX for 9 cycles and **everything behind it waits**, even instructions that have nothing to do with the multiply (like `INC R1` for the loop counter).

An out-of-order core lets independent instructions go ahead while the multiply runs. It still updates registers and memory in program order, so software can't tell the difference.

## 2. The parts

| Structure | Size | Job |
|---|---|---|
| Fetch buffer | 1 | holds the next instruction to dispatch |
| **RAT** (register alias table) | 5 entries: R0–R3 **and FLAGS** | for each architectural register: "the latest value comes from ROB entry *t*", or "the register file is up to date" |
| **ROB** (reorder buffer) | 8 entries, circular (head/tail) | every in-flight instruction in program order; holds its result until commit |
| **RS_ALU** | 4 | ALU ops, CMP, BEQ/BNE |
| **RS_MD** | 2 | MUL, DIV |
| **RS_LS** | 4 | LD, LDR, ST, STR |
| **CDB** (common data bus) | 1 result / cycle | broadcasts `(tag, value, flags)` to the ROB and all reservation stations |
| Architectural state | register file, flags register, data memory | changed only at commit |

Each reservation-station entry stores, for each source operand, **either the value or the ROB tag it is waiting for** (`ready`, `value`, `tag`). Branches have a third operand: FLAGS.

## 3. One instruction's life

1. **Dispatch (in order, 1 per cycle).**
   - **Allocate:** the instruction gets ROB entry `tail`. If it writes a register, `RAT[Rd] = tail`. If it sets flags, `RAT[FLAGS] = tail`.
   - **Read operands:** for each source, look up the RAT.
     - not renamed → read the register file;
     - renamed and that ROB entry is ready → read the ROB;
     - renamed and that tag is on the CDB right now → take it from the CDB;
     - otherwise → store the tag and wait.
   - **Place:** it goes into a free reservation-station entry.
   - **Instructions with nothing to execute** (LDI, NOP, JMP, HLT) are marked complete in the ROB straight away.
   - **Dispatch stalls** if the ROB is full or the needed reservation station is full.
2. **Wake-up.** Every cycle, each RS entry compares its waiting tags with the CDB tag. On a match it copies the value.
3. **Issue (out of order).** Each reservation station picks its **oldest ready** entry (age = tag − head) and sends it to its unit.
4. **Execute.**
   - **ALU:** 1 cycle. For a branch it computes taken / not taken from the flags operand.
   - **MUL/DIV:** 9 cycles, one operation at a time.
   - **Load/store:** loads read memory; stores only compute address and data.
5. **Write-back.** Finished results wait in a small output register for the CDB. When several units are ready, the **oldest** one wins. The CDB marks the ROB entry ready and wakes up its consumers.
6. **Commit (in order, 1 per cycle).** When the ROB head is ready:
   - it writes the register file, flags or memory;
   - it frees its RAT entry, if that entry still points at it;
   - head advances.

## 4. Flag renaming

Every ALU instruction in this ISA sets all five flags. Without renaming, FLAGS would be one shared register written by almost every instruction, which causes two problems:
- each `BEQ`/`BNE` would have to wait until *every* older flag-setter has finished;
- consecutive ALU instructions would conflict on who writes FLAGS last (WAW).

With FLAGS in the RAT:
- **Every flag-setter produces a new FLAGS version,** tagged with its ROB entry.
- **A branch depends only on the specific instruction** whose flags it reads (normally the `CMP` just before it). It wakes up as soon as that `CMP` executes, not when it commits.
- **WAW on flags disappears,** because each version lives in its own ROB entry.

**Measured:** `FLAG_RENAME = 0` makes branches wait until no flag-setter is in flight. The core then becomes slower than the in-order pipeline, while renaming gives a 1.44–1.88× speed-up over that setting (see README).

## 5. Control flow and recovery

- **JMP** is resolved at dispatch: fetch redirects and the fetch buffer is squashed (1 bubble).
- **BEQ/BNE use static BTFN prediction:** a backward target is predicted taken (loops), a forward target not taken.
  - A predicted-taken branch redirects fetch at dispatch.
  - The actual direction is computed in the ALU.
- **A misprediction is handled at commit.** When the branch reaches the ROB head with a wrong prediction, it clears the ROB, all reservation stations, the RAT, the unit outputs and the MUL/DIV unit, then redirects fetch.
  - This is simple and always precise: nothing younger than the branch has touched architectural state.
- **HLT** stops fetch when dispatched and stops the core when it commits. A HLT on a wrong path is cleared by the flush.

## 6. Memory ordering

- **Stores** write memory only at commit, which keeps exceptions and branch recovery precise.
- **A load issues only when no older store is still in the ROB.** This is conservative, but it means loads never need to compare addresses against stores or take data forwarded from them.

## 7. Trace: `mul_loop` with N = 4

Program:

```
03 loop: LDI R2, 7     
04       MUL R2, R1    ; 9-cycle unit
05       ADD R0, R2    ; needs the MUL result
06       INC R1        ; independent
07       CMP R1, R3    ; new FLAGS version
08       BNE loop      ; waits only on that CMP
```

From `tb_trace_ooo` (t = ROB tag, CDB = broadcast value):

```
cyc | dispatch (pc:instr ->tag) | issue          | CDB    | commit     | ROB entries
  4 | 03:8407 ->t3              |                |        | t0 pc 00   | 3     LDI R2,7   (ready at dispatch)
  5 | 04:6c80 ->t4              |                |        | t1 pc 01   | 3     MUL R2,R1
  6 | 05:0100 ->t5              | MD:t4          |        | t2 pc 02   | 3     MUL starts (9 cycles)
  7 | 06:5a00 ->t6              |                |        | t3 pc 03   | 3     INC R1
  8 | 07:3380 ->t7              | ALU:t6         |        |            | 3     INC runs while MUL busy
  9 | 08:b803 ->t0 redir        |                | t6=02  |            | 4     BNE predicted taken -> fetch loop
 10 | -                         | ALU:t7         |        |            | 5     CMP runs (got R1 from INC via CDB)
 11 | 03:8407 ->t1              |                | t7=fe  |            | 5     next iteration LDI; CMP flags on CDB
 12 | 04:6c80 ->t2              | ALU:t0         |        |            | 6     next MUL dispatched (R2 renamed!); BNE resolved
 13 | 05:0100 ->t3              |                | t0=00  |            | 7     next ADD dispatched
 14 | (stall: ROB full)         |                |        |            | 8
 15 | (stall)                   |                | t4=07  |            | 8     MUL result 7*1 on CDB
 16 | (stall)                   | ALU:t5  MD:t2  |        | t4 pc 04   | 8     ADD runs; next MUL starts at once
```

**What to notice:**
- **Cycles 8–12:** `INC`, `CMP` and `BNE` from iteration 1 execute while the `MUL` is still running. In the pipeline they would all wait.
- **Cycle 12:** the `BNE` is woken by the `CMP`'s FLAGS tag, without waiting for the `CMP` to commit. That is flag renaming at work.
- **Cycle 12:** iteration 2's `MUL R2, R1` is dispatched while iteration 1's `MUL` still owns the old `R2`. Renaming gives each one its own ROB entry, so there is no WAR/WAW stall.
- **Cycle 16:** the next `MUL` issues the moment the unit frees up, so the multiplier never sits idle. That's why the loop runs at the unit's throughput limit, about 10 cycles per iteration.
- **Cycles 14–15:** the ROB is full (8 entries). A bigger ROB wouldn't help here, because the multiplier is the bottleneck.

## 8. Design choices and limitations

| Choice | Why | Cost |
|---|---|---|
| Single CDB, oldest first | simple; oldest-first avoids starving the instruction the ROB head is waiting for | at most 1 result per cycle |
| Branch recovery at commit | always precise, no checkpoints of the rename table needed | larger mispredict penalty than recovering at execute |
| Conservative load ordering | no load–store address comparison or forwarding logic | loads behind stores wait |
| Static BTFN prediction | free (just compare the target with the PC); right for loop branches | wrong on forward taken branches |
| Unpipelined 9-cycle MUL/DIV | small area | one MUL/DIV at a time |
| 1-wide dispatch / commit | fits a Cyclone II easily | IPC ≤ 1 |

**Natural next steps:**
- recover from mispredictions at execute instead of commit;
- a 2-bit dynamic branch predictor;
- store-to-load forwarding;
- a pipelined multiplier;
- 2-wide dispatch.

## 9. Questions you should be able to answer

1. **Why is a ROB needed if Tomasulo already handles dependencies?** Precise state: registers and memory change in program order, so a mispredicted branch can be undone and HLT stops at the exact instruction.
2. **What is in the RAT after a flush?** Every entry points back to the architectural register file. All in-flight work was younger than the branch and is discarded.
3. **Why check `RAT[r] == head` before freeing at commit?** A younger instruction may already have renamed `r`. Freeing it would make later readers use the stale register-file value. (The test catches this bug.)
4. **Why capture from the CDB during dispatch?** If the producer broadcasts in the same cycle a consumer dispatches, the consumer would otherwise wait for a broadcast that has already happened, and the core deadlocks. (The test catches this as a deadlock.)
5. **Why must loads wait for older stores?** A store's address may not be known yet, and memory is only written at commit. Reading too early could return stale data. (The test catches this bug.)
6. **What limits `mul_loop` to about 10 cycles per iteration?** The single unpipelined MUL/DIV unit: 9 cycles plus the CDB handshake. ROB size and dispatch width are not the limit.
7. **What does flag renaming buy, in numbers?** It's the difference between CPI 3.16 and 1.68 on `mul_loop`, which is 1.88×.
