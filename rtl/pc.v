`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// pc.v  --  8-bit program counter (256-word address space, wraps 0xFF -> 0x00)
// -----------------------------------------------------------------------------
module pc (
    input            clk,
    input            rst,     // synchronous, active high
    input            en,      // advance one instruction
    output reg [7:0] pc
);
    always @(posedge clk) begin
        if (rst)     pc <= 8'h00;
        else if (en) pc <= pc + 8'd1;
    end
endmodule
