`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// processor.v  --  single-cycle core (CPI = 1)
//
//   Every enabled clock edge completes one instruction:
//     fetch IMEM[PC] -> decode -> read Rd/Rs -> ALU / memory -> write-back,
//     flags, next PC (PC+1, jump/branch target, or PC for HLT)
//   `en` is a clock enable; the board pulses it for step / slow-run modes.
//
//   Port list is identical to processor_pipe.v so the same testbench and
//   board wrapper drive both cores.
// -----------------------------------------------------------------------------
module processor #(
    parameter PROGRAM_FILE = "../mem/program.hex"
) (
    input         clk,
    input         rst,            // synchronous, active high
    input         en,             // clock enable
    input  [7:0]  io_in,          // read at address 0xFF
    output [7:0]  io_out,         // written at address 0xFE
    // ---- debug / observation ----
    output [7:0]  pc_out,         // fetch PC
    output        retire_valid,   // an instruction completes on this edge
    output [7:0]  retire_pc,
    output [15:0] retire_instr,
    output        halted,
    output        ex_valid,       // last stage holds a real instruction (not a bubble)
    output        dbg_fwd,        // a bypass is active this cycle (pipeline only)
    output        dbg_flush,      // a flush is happening this cycle (pipeline only)         // instruction completing is HLT
    output        zf, pf, cf, of, af,
    output [31:0] regs_flat       // {R3, R2, R1, R0}
);
    // ---------------- fetch ----------------
    reg  [7:0]  pc;
    wire [15:0] instr;

    instr_rom #(.PROGRAM_FILE(PROGRAM_FILE)) u_imem (.addr(pc), .instr(instr));

    // ---------------- decode ----------------
    wire [3:0] alu_op;
    wire [1:0] rd, rs, wb_sel;
    wire [7:0] imm;
    wire       reg_write, flag_write, mem_write, addr_reg, jump, beq, bne, halt;
    wire       rd_used, rs_used;    // only used by the pipelined core

    decoder u_dec (
        .instr(instr), .alu_op(alu_op), .rd(rd), .rs(rs), .imm(imm),
        .reg_write(reg_write), .flag_write(flag_write), .wb_sel(wb_sel),
        .mem_write(mem_write), .addr_reg(addr_reg),
        .jump(jump), .beq(beq), .bne(bne), .halt(halt),
        .rd_used(rd_used), .rs_used(rs_used)
    );

    // ---------------- register file ----------------
    wire [7:0] rd_val, rs_val, wb_data;

    register_file u_rf (
        .clk(clk), .rst(rst), .we(en & reg_write),
        .waddr(rd), .wdata(wb_data),
        .raddr_a(rd), .raddr_b(rs),
        .rdata_a(rd_val), .rdata_b(rs_val),
        .regs_flat(regs_flat)
    );

    // ---------------- ALU ----------------
    wire [7:0] alu_y;
    wire       a_zf, a_pf, a_cf, a_of, a_af;

    alu u_alu (
        .a(rd_val), .b(rs_val), .op(alu_op), .result(alu_y),
        .zf(a_zf), .pf(a_pf), .cf(a_cf), .of(a_of), .af(a_af)
    );

    // ---------------- data memory ----------------
    wire [7:0] mem_addr = addr_reg ? rs_val : imm;
    wire [7:0] mem_rdata;

    data_mem u_dmem (
        .clk(clk), .rst(rst), .we(en & mem_write),
        .addr(mem_addr), .wdata(rd_val), .rdata(mem_rdata),
        .io_in(io_in), .io_out(io_out)
    );

    assign wb_data = (wb_sel == 2'd1) ? imm :
                     (wb_sel == 2'd2) ? mem_rdata : alu_y;

    // ---------------- flags ----------------
    reg [4:0] flags;                        // {AF, OF, CF, PF, ZF}
    always @(posedge clk) begin
        if (rst)                     flags <= 5'b00000;
        else if (en && flag_write)   flags <= {a_af, a_of, a_cf, a_pf, a_zf};
    end
    assign {af, of, cf, pf, zf} = flags;

    // ---------------- next PC ----------------
    wire taken = jump | (beq & zf) | (bne & ~zf);
    always @(posedge clk) begin
        if (rst)        pc <= 8'h00;
        else if (en)    pc <= halt ? pc : (taken ? imm : pc + 8'd1);
    end

    assign pc_out       = pc;
    assign retire_valid = en;
    assign retire_pc    = pc;
    assign retire_instr = instr;
    assign halted       = halt;
    assign ex_valid     = 1'b1;
    assign dbg_fwd      = 1'b0;
    assign dbg_flush    = 1'b0;
endmodule
