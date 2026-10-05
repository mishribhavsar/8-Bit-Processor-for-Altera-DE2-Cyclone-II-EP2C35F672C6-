`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// processor.v  --  single-cycle 8-bit processor core
//
//   Every enabled clock edge completes one instruction:
//     fetch (ROM[PC]) -> decode -> register read -> ALU -> write Rd + flags, PC+1
//   All of it is combinational between the PC/register/flag registers, so
//   CPI = 1. `en` is a clock enable: the whole design runs on one clock and
//   the board top-level pulses `en` for single-step / slow-run modes.
// -----------------------------------------------------------------------------
module processor #(
    parameter       PROGRAM_FILE = "../mem/program.hex",
    parameter [7:0] R2_INIT      = 8'h0F,
    parameter [7:0] R3_INIT      = 8'h01
) (
    input         clk,
    input         rst,          // synchronous, active high
    input         en,           // execute one instruction on this clock edge
    input  [7:0]  init_r0,      // R0 value loaded at reset
    input  [7:0]  init_r1,      // R1 value loaded at reset
    output [7:0]  pc_out,       // address of the instruction being executed
    output [7:0]  instr,        // instruction being executed
    output [7:0]  alu_result,   // ALU output for the current instruction
    output        zf, pf, cf, of, af,   // flag register
    output [31:0] regs_flat     // {R3, R2, R1, R0}
);
    // ---- datapath wires ----------------------------------------------------
    wire [3:0] alu_op;
    wire [1:0] rs, rd;
    wire       reg_write, flag_write;
    wire [7:0] rd_data, rs_data;
    wire       alu_zf, alu_pf, alu_cf, alu_of, alu_af;

    // ---- program counter ---------------------------------------------------
    pc u_pc (
        .clk (clk),
        .rst (rst),
        .en  (en),
        .pc  (pc_out)
    );

    // ---- instruction memory (256 x 8 ROM) ----------------------------------
    instr_rom #(.PROGRAM_FILE(PROGRAM_FILE)) u_rom (
        .addr  (pc_out),
        .instr (instr)
    );

    // ---- control unit ------------------------------------------------------
    control_unit u_cu (
        .instr      (instr),
        .alu_op     (alu_op),
        .rs         (rs),
        .rd         (rd),
        .reg_write  (reg_write),
        .flag_write (flag_write)
    );

    // ---- register file (4 x 8) ---------------------------------------------
    register_file #(.R2_INIT(R2_INIT), .R3_INIT(R3_INIT)) u_rf (
        .clk       (clk),
        .rst       (rst),
        .en        (en),
        .init_r0   (init_r0),
        .init_r1   (init_r1),
        .rd_addr   (rd),
        .rs_addr   (rs),
        .we        (reg_write),
        .wdata     (alu_result),
        .rd_data   (rd_data),
        .rs_data   (rs_data),
        .regs_flat (regs_flat)
    );

    // ---- ALU -----------------------------------------------------------------
    alu u_alu (
        .a      (rd_data),
        .b      (rs_data),
        .op     (alu_op),
        .result (alu_result),
        .zf     (alu_zf),
        .pf     (alu_pf),
        .cf     (alu_cf),
        .of     (alu_of),
        .af     (alu_af)
    );

    // ---- flag register -------------------------------------------------------
    reg [4:0] flags;   // {AF, OF, CF, PF, ZF}
    always @(posedge clk) begin
        if (rst)
            flags <= 5'b00000;
        else if (en && flag_write)
            flags <= {alu_af, alu_of, alu_cf, alu_pf, alu_zf};
    end
    assign {af, of, cf, pf, zf} = flags;
endmodule
