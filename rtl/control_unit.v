`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// control_unit.v  --  combinational instruction decoder
//
//   Instruction format (8 bits):   [7:4] opcode   [3:2] Rs   [1:0] Rd
//
//   Two-operand ops : Rd <- Rd op Rs
//   One-operand ops : Rd <- op Rd          (Rs field ignored)
//   CMP             : flags <- Rd - Rs     (no register write)
//   NOP             : nothing changes except PC
// -----------------------------------------------------------------------------
module control_unit (
    input  [7:0] instr,
    output [3:0] alu_op,
    output [1:0] rs,
    output [1:0] rd,
    output reg   reg_write,
    output reg   flag_write
);
    localparam OP_CMP = 4'h6, OP_NOP = 4'hF;

    wire [3:0] opcode = instr[7:4];

    assign alu_op = opcode;          // ALU select encoding == opcode encoding
    assign rs     = instr[3:2];
    assign rd     = instr[1:0];

    always @(*) begin
        case (opcode)
            OP_NOP: begin reg_write = 1'b0; flag_write = 1'b0; end
            OP_CMP: begin reg_write = 1'b0; flag_write = 1'b1; end
            default:begin reg_write = 1'b1; flag_write = 1'b1; end
        endcase
    end
endmodule
