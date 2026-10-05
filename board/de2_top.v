`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// de2_top.v  --  board wrapper for the Altera DE2 (Cyclone II EP2C35F672C6)
//
//   Controls
//     KEY[0]      reset (hold)  - loads R0 <- SW[7:0], R1 <- SW[15:8], PC <- 0
//     KEY[1]      single-step   - executes exactly one instruction per press
//     SW[17]      0 = step mode (KEY[1]),  1 = run mode (~2 instructions/s)
//     SW[16]      HEX3-0 show  0: R0 R1   1: R2 R3
//     SW[15:8]    R1 reset value
//     SW[7:0]     R0 reset value
//
//   Displays
//     HEX7-6      PC (address of the next instruction to execute)
//     HEX5-4      instruction at PC
//     HEX3-2      R0 (or R2)        HEX1-0  R1 (or R3)
//     LEDR[7:0]   ALU output for the instruction at PC (value it will write)
//     LEDG[0..4]  ZF PF CF OF AF    (flag register)
//     LEDG[7]     run mode          LEDG[8] blinks on every executed instruction
//
//   The core runs on CLOCK_50 and advances only when `step_en` pulses for
//   one clock - no divided or gated clocks.
// -----------------------------------------------------------------------------
module de2_top (
    input         CLOCK_50,
    input  [3:0]  KEY,          // active low, pressed = 0
    input  [17:0] SW,
    output [8:0]  LEDG,
    output [17:0] LEDR,
    output [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7
);
    // ---------------- reset synchroniser ----------------
    reg [1:0] rst_sync = 2'b11;
    always @(posedge CLOCK_50) rst_sync <= {rst_sync[0], ~KEY[0]};
    wire rst = rst_sync[1];

    // ---------------- 1 kHz sample tick (debounce) ----------------
    reg [15:0] ms_cnt = 16'd0;
    wire       ms_tick = (ms_cnt == 16'd49_999);
    always @(posedge CLOCK_50) ms_cnt <= ms_tick ? 16'd0 : ms_cnt + 16'd1;

    // ---------------- KEY[1] step: sync, sample at 1 kHz, edge detect ----------------
    reg [1:0] key1_sync = 2'b11;
    reg       key1_q = 1'b1, key1_qq = 1'b1;
    always @(posedge CLOCK_50) begin
        key1_sync <= {key1_sync[0], KEY[1]};
        if (ms_tick) begin
            key1_q  <= key1_sync[1];
            key1_qq <= key1_q;
        end
    end
    // one CLOCK_50-cycle pulse on the press (1 -> 0 transition)
    wire step_pulse = ms_tick & key1_qq & ~key1_q;

    // ---------------- run mode: ~2 Hz tick ----------------
    reg [24:0] run_cnt = 25'd0;
    wire       run_tick = (run_cnt == 25'd24_999_999);
    always @(posedge CLOCK_50) run_cnt <= run_tick ? 25'd0 : run_cnt + 25'd1;

    reg [1:0] mode_sync = 2'b00;
    always @(posedge CLOCK_50) mode_sync <= {mode_sync[0], SW[17]};
    wire run_mode = mode_sync[1];

    wire step_en = ~rst & (run_mode ? run_tick : step_pulse);

    // ---------------- processor core ----------------
    wire [7:0]  pc, instr, alu_result;
    wire        zf, pf, cf, of, af;
    wire [31:0] regs;

    processor #(.PROGRAM_FILE("../mem/program.hex")) u_core (
        .clk        (CLOCK_50),
        .rst        (rst),
        .en         (step_en),
        .init_r0    (SW[7:0]),
        .init_r1    (SW[15:8]),
        .pc_out     (pc),
        .instr      (instr),
        .alu_result (alu_result),
        .zf(zf), .pf(pf), .cf(cf), .of(of), .af(af),
        .regs_flat  (regs)
    );

    // ---------------- activity LED: stretch each step to ~100 ms ----------------
    reg [22:0] blink = 23'd0;
    always @(posedge CLOCK_50)
        if (step_en)        blink <= 23'd5_000_000;
        else if (blink != 0) blink <= blink - 23'd1;

    // ---------------- LEDs ----------------
    assign LEDG = {(blink != 0), run_mode, 2'b00, af, of, cf, pf, zf};
    assign LEDR = {10'd0, alu_result};

    // ---------------- 7-segment displays ----------------
    wire [7:0] show_a = SW[16] ? regs[23:16] : regs[7:0];    // R2 : R0
    wire [7:0] show_b = SW[16] ? regs[31:24] : regs[15:8];   // R3 : R1

    seg7_hex h7 (.hex(pc[7:4]),     .seg(HEX7));
    seg7_hex h6 (.hex(pc[3:0]),     .seg(HEX6));
    seg7_hex h5 (.hex(instr[7:4]),  .seg(HEX5));
    seg7_hex h4 (.hex(instr[3:0]),  .seg(HEX4));
    seg7_hex h3 (.hex(show_a[7:4]), .seg(HEX3));
    seg7_hex h2 (.hex(show_a[3:0]), .seg(HEX2));
    seg7_hex h1 (.hex(show_b[7:4]), .seg(HEX1));
    seg7_hex h0 (.hex(show_b[3:0]), .seg(HEX0));
endmodule
