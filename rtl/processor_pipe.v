`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// processor_pipe.v  --  3-stage pipelined core (same ISA as processor.v)
//
//   IF : fetch IMEM[PC]                               -> IF/ID register
//   ID : decode, read Rd/Rs (with forwarding),
//        resolve JMP                                   -> ID/EX register
//   EX : ALU / memory access / write-back / flags,
//        resolve BEQ, BNE, HLT
//
//   Hazards
//   - Data (RAW): an instruction in ID that reads a register written by the
//     instruction in EX gets the EX write-back value through a bypass
//     (fwd_a / fwd_b). Loads also complete in EX (combinational data memory),
//     so there is no load-use stall.
//   - Flags: written at the end of EX; a BEQ/BNE reaches EX one cycle later,
//     so it always sees up-to-date flags. No bypass needed.
//   - Control: branches are predicted not-taken.
//       JMP       resolved in ID -> squash the instruction in IF   (1 bubble)
//       BEQ/BNE   resolved in EX -> squash IF and ID if taken      (2 bubbles)
//       HLT       when it reaches EX the pipeline stops (younger instruction
//                 squashed, HLT held in EX) until reset
//
//   Writes to architectural state (registers, flags, memory) happen only in
//   EX, in program order, so retirement order = program order.
// -----------------------------------------------------------------------------
module processor_pipe #(
    parameter PROGRAM_FILE = "../mem/program.hex"
) (
    input         clk,
    input         rst,
    input         en,
    input  [7:0]  io_in,
    output [7:0]  io_out,
    output [7:0]  pc_out,
    output        retire_valid,
    output [7:0]  retire_pc,
    output [15:0] retire_instr,
    output        halted,
    output        ex_valid,       // last stage holds a real instruction (not a bubble)
    output        dbg_fwd,        // a bypass is active this cycle (pipeline only)
    output        dbg_flush,      // a flush is happening this cycle (pipeline only)
    output        zf, pf, cf, of, af,
    output [31:0] regs_flat
);
    // =========================== IF ==========================================
    reg  [7:0]  pc_f;
    wire [15:0] instr_f;

    instr_rom #(.PROGRAM_FILE(PROGRAM_FILE)) u_imem (.addr(pc_f), .instr(instr_f));

    // IF/ID pipeline register
    reg         valid_d;
    reg  [7:0]  pc_d;
    reg  [15:0] instr_d;

    // =========================== ID ==========================================
    wire [3:0] alu_op_d;
    wire [1:0] rd_d, rs_d, wb_sel_d;
    wire [7:0] imm_d;
    wire       reg_write_d, flag_write_d, mem_write_d, addr_reg_d;
    wire       jump_d, beq_d, bne_d, halt_d, rd_used_d, rs_used_d;

    decoder u_dec_id (
        .instr(instr_d), .alu_op(alu_op_d), .rd(rd_d), .rs(rs_d), .imm(imm_d),
        .reg_write(reg_write_d), .flag_write(flag_write_d), .wb_sel(wb_sel_d),
        .mem_write(mem_write_d), .addr_reg(addr_reg_d),
        .jump(jump_d), .beq(beq_d), .bne(bne_d), .halt(halt_d),
        .rd_used(rd_used_d), .rs_used(rs_used_d)
    );

    wire [7:0] rf_a, rf_b;          // register file read data
    wire [7:0] wb_data_e;           // EX-stage write-back value (bypass source)
    wire       rf_we_e;             // EX stage writes a register this cycle
    wire [1:0] rd_e;

    // EX -> ID bypass
    wire fwd_a = rf_we_e && rd_used_d && (rd_e == rd_d);
    wire fwd_b = rf_we_e && rs_used_d && (rd_e == rs_d);
    wire [7:0] opa_d = fwd_a ? wb_data_e : rf_a;
    wire [7:0] opb_d = fwd_b ? wb_data_e : rf_b;

    // ID/EX pipeline register
    reg         valid_e;
    reg  [7:0]  pc_e;
    reg  [15:0] instr_e;
    reg  [7:0]  opa_e, opb_e;

    // =========================== EX ==========================================
    wire [3:0] alu_op_e;
    wire [1:0] rs_e, wb_sel_e;
    wire [7:0] imm_e;
    wire       reg_write_e, flag_write_e, mem_write_e, addr_reg_e;
    wire       jump_e, beq_e, bne_e, halt_e, rd_used_e, rs_used_e;

    decoder u_dec_ex (
        .instr(instr_e), .alu_op(alu_op_e), .rd(rd_e), .rs(rs_e), .imm(imm_e),
        .reg_write(reg_write_e), .flag_write(flag_write_e), .wb_sel(wb_sel_e),
        .mem_write(mem_write_e), .addr_reg(addr_reg_e),
        .jump(jump_e), .beq(beq_e), .bne(bne_e), .halt(halt_e),
        .rd_used(rd_used_e), .rs_used(rs_used_e)
    );

    wire [7:0] alu_y;
    wire       a_zf, a_pf, a_cf, a_of, a_af;

    alu u_alu (
        .a(opa_e), .b(opb_e), .op(alu_op_e), .result(alu_y),
        .zf(a_zf), .pf(a_pf), .cf(a_cf), .of(a_of), .af(a_af)
    );

    wire [7:0] mem_addr = addr_reg_e ? opb_e : imm_e;
    wire [7:0] mem_rdata;

    data_mem u_dmem (
        .clk(clk), .rst(rst), .we(en & valid_e & mem_write_e),
        .addr(mem_addr), .wdata(opa_e), .rdata(mem_rdata),
        .io_in(io_in), .io_out(io_out)
    );

    assign wb_data_e = (wb_sel_e == 2'd1) ? imm_e :
                       (wb_sel_e == 2'd2) ? mem_rdata : alu_y;
    assign rf_we_e   = valid_e & reg_write_e;

    register_file u_rf (
        .clk(clk), .rst(rst), .we(en & rf_we_e),
        .waddr(rd_e), .wdata(wb_data_e),
        .raddr_a(rd_d), .raddr_b(rs_d),
        .rdata_a(rf_a), .rdata_b(rf_b),
        .regs_flat(regs_flat)
    );

    reg [4:0] flags;                                  // {AF, OF, CF, PF, ZF}
    always @(posedge clk) begin
        if (rst)                                 flags <= 5'b00000;
        else if (en && valid_e && flag_write_e)  flags <= {a_af, a_of, a_cf, a_pf, a_zf};
    end
    assign {af, of, cf, pf, zf} = flags;

    // =========================== control hazards =============================
    wire br_taken_e = valid_e & ((beq_e & zf) | (bne_e & ~zf));
    wire flush_e    = br_taken_e;                             // squash IF + ID
    wire [7:0] target_e = imm_e;
    wire flush_d    = valid_d & jump_d & ~flush_e;            // squash IF
    wire halt_now   = valid_e & halt_e;

    reg halted_r;                                             // HLT has retired
    always @(posedge clk) begin
        if (rst)                         halted_r <= 1'b0;
        else if (en && halt_now)         halted_r <= 1'b1;
    end

    // =========================== pipeline registers ==========================
    always @(posedge clk) begin
        if (rst) begin
            pc_f    <= 8'h00;
            valid_d <= 1'b0;  pc_d <= 8'h00; instr_d <= 16'h0000;
            valid_e <= 1'b0;  pc_e <= 8'h00; instr_e <= 16'h0000;
            opa_e   <= 8'h00; opb_e <= 8'h00;
        end else if (en && halt_now) begin
            valid_d <= 1'b0;                                  // squash; freeze PC and EX
        end else if (en) begin
            // PC
            if (flush_e)      pc_f <= target_e;
            else if (flush_d) pc_f <= imm_d;
            else              pc_f <= pc_f + 8'd1;

            // IF -> ID
            valid_d <= ~(flush_e | flush_d);
            pc_d    <= pc_f;
            instr_d <= instr_f;

            // ID -> EX
            valid_e <= valid_d & ~flush_e;
            pc_e    <= pc_d;
            instr_e <= instr_d;
            opa_e   <= opa_d;
            opb_e   <= opb_d;
        end
    end

    // =========================== observation =================================
    assign pc_out       = pc_f;
    assign retire_valid = en & valid_e & ~halted_r;
    assign retire_pc    = pc_e;
    assign retire_instr = instr_e;
    assign halted       = halt_now;
    assign ex_valid     = valid_e;
    assign dbg_fwd      = valid_d & (fwd_a | fwd_b);
    assign dbg_flush    = flush_e | flush_d;
endmodule
