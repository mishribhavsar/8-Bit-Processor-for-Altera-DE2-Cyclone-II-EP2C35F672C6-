`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// alu.v  --  8-bit ALU, 15 operations + NOP, five status flags
//
//   A = Rd (destination / first operand), B = Rs (source / second operand)
//
//   Flags (all computed from the current operation):
//     ZF  zero      : result == 0
//     PF  parity    : 1 when the result has an even number of 1s (x86 style)
//     CF  carry     : carry-out (ADD/INC), borrow (SUB/CMP/DEC),
//                     bit shifted/rotated out (shifts/rotates),
//                     high byte non-zero (MUL); 0 for logic ops and DIV
//     OF  overflow  : signed overflow (ADD/SUB/CMP/INC/DEC),
//                     sign change (LSL), original sign (LSR),
//                     high byte non-zero (MUL), divide-by-zero (DIV)
//     AF  auxiliary : carry/borrow between bit 3 and bit 4 (ADD/SUB/CMP/INC/DEC)
// -----------------------------------------------------------------------------
module alu (
    input      [7:0] a,          // Rd
    input      [7:0] b,          // Rs
    input      [3:0] op,         // operation select (= opcode)
    output reg [7:0] result,
    output reg       zf,
    output reg       pf,
    output reg       cf,
    output reg       of,
    output reg       af
);
    localparam OP_ADD = 4'h0, OP_SUB = 4'h1, OP_AND = 4'h2, OP_OR  = 4'h3,
               OP_XOR = 4'h4, OP_NOT = 4'h5, OP_CMP = 4'h6, OP_LSL = 4'h7,
               OP_LSR = 4'h8, OP_ROR = 4'h9, OP_ROL = 4'hA, OP_INC = 4'hB,
               OP_DEC = 4'hC, OP_MUL = 4'hD, OP_DIV = 4'hE, OP_NOP = 4'hF;

    // Shared adder/subtractor: ADD, SUB, CMP, INC, DEC all use one 9-bit adder
    reg  [7:0]  add_b;
    reg         sub;
    wire [8:0]  sum = sub ? ({1'b0, a} - {1'b0, add_b})
                          : ({1'b0, a} + {1'b0, add_b});
    wire [15:0] prod = a * b;

    always @(*) begin
        // operand for the adder
        case (op)
            OP_INC, OP_DEC: add_b = 8'd1;
            default:        add_b = b;
        endcase
        sub = (op == OP_SUB) || (op == OP_CMP) || (op == OP_DEC);

        // defaults
        result = 8'h00;
        cf = 1'b0; of = 1'b0; af = 1'b0;

        case (op)
            OP_ADD, OP_INC,
            OP_SUB, OP_CMP, OP_DEC: begin
                result = sum[7:0];
                cf     = sum[8];                               // carry / borrow
                of     = sub ? ((a[7] != add_b[7]) && (sum[7] != a[7]))
                             : ((a[7] == add_b[7]) && (sum[7] != a[7]));
                af     = a[4] ^ add_b[4] ^ sum[4];             // carry into bit 4
            end
            OP_AND: result = a & b;
            OP_OR : result = a | b;
            OP_XOR: result = a ^ b;
            OP_NOT: result = ~a;
            OP_LSL: begin result = {a[6:0], 1'b0}; cf = a[7]; of = a[7] ^ a[6]; end
            OP_LSR: begin result = {1'b0, a[7:1]}; cf = a[0]; of = a[7];        end
            OP_ROR: begin result = {a[0], a[7:1]}; cf = a[0];                   end
            OP_ROL: begin result = {a[6:0], a[7]}; cf = a[7];                   end
            OP_MUL: begin
                result = prod[7:0];
                cf     = |prod[15:8];
                of     = |prod[15:8];
            end
            OP_DIV: begin
                if (b == 8'd0) begin
                    result = 8'h00;
                    of     = 1'b1;                             // divide-by-zero
                end else
                    result = a / b;
            end
            default: result = 8'h00;                           // NOP
        endcase

        // CMP only sets flags; its "result" is the difference (not written back)
        zf = (result == 8'h00);
        pf = ~(^result);
    end
endmodule
