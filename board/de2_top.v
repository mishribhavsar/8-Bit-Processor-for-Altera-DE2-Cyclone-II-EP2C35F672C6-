`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// de2_top.v  --  board wrapper for the Altera DE2 (Cyclone II EP2C35F672C6)
//
//   All three cores (single-cycle, 3-stage pipeline, out-of-order) run side
//   by side on the same program, clock enable and input port, so you can
//   step them together and compare.
//
//   Controls
//     KEY[0]      reset (hold)
//     KEY[1]      single step: one clock for all cores
//     SW[17]      0 = step mode (KEY[1]),  1 = run mode (~2 clocks/s)
//     SW[16:15]   displays show  00: single-cycle  01: pipelined  1x: out-of-order
//     SW[14:13]   register shown on HEX1-0 (R0..R3)
//     SW[7:0]     input port (address 0xFF)
//
//   Displays (for the selected core)
//     HEX7-6      PC (fetch address)
//     HEX5-2      instruction in the last stage (OoO: ROB head), "----" if empty
//     HEX1-0      selected register
//     LEDR[7:0]   output port (address 0xFE)
//     LEDR[16:15] selected core           LEDR[17]  HLT reached
//     LEDG[0..4]  ZF PF CF OF AF
//     LEDG[5]     forwarding (pipe) / CDB broadcast (OoO)
//     LEDG[6]     flush (pipe) / mispredict recovery (OoO)
//     LEDG[7]     run mode            LEDG[8]  blinks on every clock step
// -----------------------------------------------------------------------------
module de2_top #(
    parameter TICK_DIV = 50_000,        // 1 kHz key sampling at 50 MHz
    parameter RUN_DIV  = 25_000_000     // ~2 Hz in run mode
) (
    input         CLOCK_50,
    input  [3:0]  KEY,                  // active low
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
    reg [31:0] tick_cnt = 0;
    wire       tick = (tick_cnt == TICK_DIV - 1);
    always @(posedge CLOCK_50) tick_cnt <= tick ? 0 : tick_cnt + 1;

    // ---------------- KEY[1] step ----------------
    reg [1:0] key1_sync = 2'b11;
    reg       key1_q = 1'b1, key1_qq = 1'b1;
    always @(posedge CLOCK_50) begin
        key1_sync <= {key1_sync[0], KEY[1]};
        if (tick) begin
            key1_q  <= key1_sync[1];
            key1_qq <= key1_q;
        end
    end
    wire step_pulse = tick & key1_qq & ~key1_q;      // one cycle per press

    // ---------------- run mode ----------------
    reg [31:0] run_cnt = 0;
    wire       run_tick = (run_cnt == RUN_DIV - 1);
    always @(posedge CLOCK_50) run_cnt <= run_tick ? 0 : run_cnt + 1;

    reg [2:0] sw_sync0 = 0, sw_sync1 = 0;            // synchronise the mode switches
    always @(posedge CLOCK_50) begin
        sw_sync0 <= SW[17:15];
        sw_sync1 <= sw_sync0;
    end
    wire       run_mode = sw_sync1[2];
    wire [1:0] sel      = sw_sync1[1] ? 2'd2 : {1'b0, sw_sync1[0]};   // 0 single, 1 pipe, 2 OoO

    wire step_en = ~rst & (run_mode ? run_tick : step_pulse);

    // ---------------- the three cores ----------------
    wire [7:0]  out_s, out_p, out_o, pc_s, pc_p, pc_o, rpc_s, rpc_p, rpc_o;
    wire [15:0] ir_s, ir_p, ir_o;
    wire        rv_s, rv_p, rv_o, h_s, h_p, h_o, ev_s, ev_p, ev_o;
    wire        fw_s, fw_p, fw_o, fl_s, fl_p, fl_o;
    wire [4:0]  fl5_s, fl5_p, fl5_o;                 // {AF, OF, CF, PF, ZF}
    wire [31:0] regs_s, regs_p, regs_o;

    processor #(.PROGRAM_FILE("../mem/program.hex")) u_sc (
        .clk(CLOCK_50), .rst(rst), .en(step_en), .io_in(SW[7:0]), .io_out(out_s),
        .pc_out(pc_s), .retire_valid(rv_s), .retire_pc(rpc_s), .retire_instr(ir_s),
        .halted(h_s), .ex_valid(ev_s), .dbg_fwd(fw_s), .dbg_flush(fl_s),
        .zf(fl5_s[0]), .pf(fl5_s[1]), .cf(fl5_s[2]), .of(fl5_s[3]), .af(fl5_s[4]),
        .regs_flat(regs_s)
    );

    processor_pipe #(.PROGRAM_FILE("../mem/program.hex")) u_pl (
        .clk(CLOCK_50), .rst(rst), .en(step_en), .io_in(SW[7:0]), .io_out(out_p),
        .pc_out(pc_p), .retire_valid(rv_p), .retire_pc(rpc_p), .retire_instr(ir_p),
        .halted(h_p), .ex_valid(ev_p), .dbg_fwd(fw_p), .dbg_flush(fl_p),
        .zf(fl5_p[0]), .pf(fl5_p[1]), .cf(fl5_p[2]), .of(fl5_p[3]), .af(fl5_p[4]),
        .regs_flat(regs_p)
    );

    processor_ooo #(.PROGRAM_FILE("../mem/program.hex")) u_oo (
        .clk(CLOCK_50), .rst(rst), .en(step_en), .io_in(SW[7:0]), .io_out(out_o),
        .pc_out(pc_o), .retire_valid(rv_o), .retire_pc(rpc_o), .retire_instr(ir_o),
        .halted(h_o), .ex_valid(ev_o), .dbg_fwd(fw_o), .dbg_flush(fl_o),
        .zf(fl5_o[0]), .pf(fl5_o[1]), .cf(fl5_o[2]), .of(fl5_o[3]), .af(fl5_o[4]),
        .regs_flat(regs_o)
    );

    // ---------------- display mux ----------------
    wire [7:0]  pc    = (sel == 2'd2) ? pc_o   : (sel == 2'd1) ? pc_p   : pc_s;
    wire [15:0] ir    = (sel == 2'd2) ? ir_o   : (sel == 2'd1) ? ir_p   : ir_s;
    wire        valid = (sel == 2'd2) ? ev_o   : (sel == 2'd1) ? ev_p   : ev_s;
    wire [7:0]  out   = (sel == 2'd2) ? out_o  : (sel == 2'd1) ? out_p  : out_s;
    wire [4:0]  flags = (sel == 2'd2) ? fl5_o  : (sel == 2'd1) ? fl5_p  : fl5_s;
    wire [31:0] regs  = (sel == 2'd2) ? regs_o : (sel == 2'd1) ? regs_p : regs_s;
    wire        halt  = (sel == 2'd2) ? h_o    : (sel == 2'd1) ? h_p    : h_s;
    wire        fwd   = (sel == 2'd2) ? fw_o   : (sel == 2'd1) & fw_p;
    wire        flush = (sel == 2'd2) ? fl_o   : (sel == 2'd1) & fl_p;

    reg [7:0] reg_show;
    always @(*) begin
        case (SW[14:13])
            2'd0: reg_show = regs[7:0];
            2'd1: reg_show = regs[15:8];
            2'd2: reg_show = regs[23:16];
            default: reg_show = regs[31:24];
        endcase
    end

    // ---------------- activity LED ----------------
    reg [22:0] blink = 0;
    always @(posedge CLOCK_50)
        if (step_en)          blink <= 23'd5_000_000;
        else if (blink != 0)  blink <= blink - 23'd1;

    assign LEDG = {(blink != 0), run_mode, flush, fwd, flags};
    assign LEDR = {halt, sel, 7'd0, out};

    // ---------------- 7-segment ----------------
    localparam [6:0] DASH = 7'b0111111;
    wire [6:0] s7, s6, s5, s4, s3, s2, s1, s0;
    seg7_hex h7 (.hex(pc[7:4]),        .seg(s7));
    seg7_hex h6 (.hex(pc[3:0]),        .seg(s6));
    seg7_hex h5 (.hex(ir[15:12]),      .seg(s5));
    seg7_hex h4 (.hex(ir[11:8]),       .seg(s4));
    seg7_hex h3 (.hex(ir[7:4]),        .seg(s3));
    seg7_hex h2 (.hex(ir[3:0]),        .seg(s2));
    seg7_hex h1 (.hex(reg_show[7:4]),  .seg(s1));
    seg7_hex h0 (.hex(reg_show[3:0]),  .seg(s0));

    assign HEX7 = s7;
    assign HEX6 = s6;
    assign HEX5 = valid ? s5 : DASH;
    assign HEX4 = valid ? s4 : DASH;
    assign HEX3 = valid ? s3 : DASH;
    assign HEX2 = valid ? s2 : DASH;
    assign HEX1 = s1;
    assign HEX0 = s0;
endmodule
