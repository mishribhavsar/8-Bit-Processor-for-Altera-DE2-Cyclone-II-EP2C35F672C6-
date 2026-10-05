`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// decoder.v  --  instruction decoder (shared by the single-cycle and the
//                pipelined core; the only module that knows the opcodes)
//
//   16-bit instruction, 8-bit datapath
//     R-type : [15:11] opcode  [10:9] Rd  [8:7] Rs  [6:0] 0
//     I-type : [15:11] opcode  [10:9] Rd  [8]   0   [7:0] imm8
//
//   opcode  mnemonic        operation
//   00-0E   ALU ops         Rd <- Rd op Rs / op Rd   (CMP: flags only)
//   0F      NOP
//   10      LDI Rd, imm     Rd <- imm
//   11      LD  Rd, [imm]   Rd <- M[imm]
//   12      ST  Rd, [imm]   M[imm] <- Rd
//   13      LDR Rd, [Rs]    Rd <- M[Rs]
//   14      STR Rd, [Rs]    M[Rs] <- Rd
//   15      JMP imm         PC <- imm
//   16      BEQ imm         if ZF==1: PC <- imm
//   17      BNE imm         if ZF==0: PC <- imm
//   18      HLT             PC <- PC (stop)
//   19-1F   (unused)        executed as NOP
// -----------------------------------------------------------------------------
module decoder (
    input  [15:0] instr,
    output [3:0]  alu_op,
    output [1:0]  rd,
    output [1:0]  rs,
    output [7:0]  imm,
    output reg    reg_write,   // write Rd
    output reg    flag_write,  // update flag register
    output reg [1:0] wb_sel,   // 0 = ALU, 1 = imm, 2 = memory
    output reg    mem_write,
    output reg    addr_reg,    // memory address: 0 = imm, 1 = Rs
    output reg    jump,
    output reg    beq,
    output reg    bne,
    output reg    halt,
    output reg    rd_used,     // instruction reads Rd   (for forwarding)
    output reg    rs_used      // instruction reads Rs
);
    localparam OP_CMP = 5'h06, OP_NOP = 5'h0F,
               OP_LDI = 5'h10, OP_LD  = 5'h11, OP_ST  = 5'h12,
               OP_LDR = 5'h13, OP_STR = 5'h14, OP_JMP = 5'h15,
               OP_BEQ = 5'h16, OP_BNE = 5'h17, OP_HLT = 5'h18;

    wire [4:0] op = instr[15:11];

    assign alu_op = op[3:0];
    assign rd     = instr[10:9];
    assign rs     = instr[8:7];
    assign imm    = instr[7:0];

    always @(*) begin
        reg_write = 1'b0; flag_write = 1'b0; wb_sel = 2'd0;
        mem_write = 1'b0; addr_reg = 1'b0;
        jump = 1'b0; beq = 1'b0; bne = 1'b0; halt = 1'b0;
        rd_used = 1'b0; rs_used = 1'b0;

        if (op[4] == 1'b0) begin                      // 00-0F: ALU group
            if (op == OP_NOP) begin
                // nothing
            end else begin
                flag_write = 1'b1;
                reg_write  = (op != OP_CMP);
                rd_used    = 1'b1;
                // one-operand ops (NOT, LSL, LSR, ROR, ROL, INC, DEC) ignore Rs
                rs_used    = !(op == 5'h05 || (op >= 5'h07 && op <= 5'h0C));
            end
        end else begin
            case (op)
                OP_LDI: begin reg_write = 1'b1; wb_sel = 2'd1;                 end
                OP_LD : begin reg_write = 1'b1; wb_sel = 2'd2;                 end
                OP_ST : begin mem_write = 1'b1; rd_used = 1'b1;                end
                OP_LDR: begin reg_write = 1'b1; wb_sel = 2'd2; addr_reg = 1'b1; rs_used = 1'b1; end
                OP_STR: begin mem_write = 1'b1; addr_reg = 1'b1; rd_used = 1'b1; rs_used = 1'b1; end
                OP_JMP: jump = 1'b1;
                OP_BEQ: beq  = 1'b1;
                OP_BNE: bne  = 1'b1;
                OP_HLT: halt = 1'b1;
                default: ;                                // unused -> NOP
            endcase
        end
    end
endmodule
