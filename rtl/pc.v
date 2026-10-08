`timescale 1ns/1ps
// 8-bit program counter: loads pc_next when enabled
module pc (
    input            clk,
    input            rst,
    input            pc_enable,
    input      [7:0] pc_next,
    output reg [7:0] PC
);
    always @(posedge clk) begin
        if (rst)
            PC <= 8'h00;
        else if (pc_enable)
            PC <= pc_next;
    end
endmodule
