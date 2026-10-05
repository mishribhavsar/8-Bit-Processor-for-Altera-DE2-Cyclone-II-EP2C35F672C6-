`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// register_file.v  --  4 x 8-bit register file (R0-R3)
//   two combinational read ports, one synchronous write port,
//   synchronous reset to 0 (use LDI to load constants)
// -----------------------------------------------------------------------------
module register_file (
    input         clk,
    input         rst,        // synchronous, active high
    input         we,         // already qualified with the clock enable
    input  [1:0]  waddr,
    input  [7:0]  wdata,
    input  [1:0]  raddr_a,
    input  [1:0]  raddr_b,
    output [7:0]  rdata_a,
    output [7:0]  rdata_b,
    output [31:0] regs_flat   // {R3, R2, R1, R0} for debug / display
);
    reg [7:0] r0, r1, r2, r3;

    always @(posedge clk) begin
        if (rst) begin
            r0 <= 8'h00; r1 <= 8'h00; r2 <= 8'h00; r3 <= 8'h00;
        end else if (we) begin
            case (waddr)
                2'd0: r0 <= wdata;
                2'd1: r1 <= wdata;
                2'd2: r2 <= wdata;
                2'd3: r3 <= wdata;
            endcase
        end
    end

    assign rdata_a = (raddr_a == 2'd0) ? r0 : (raddr_a == 2'd1) ? r1 :
                     (raddr_a == 2'd2) ? r2 : r3;
    assign rdata_b = (raddr_b == 2'd0) ? r0 : (raddr_b == 2'd1) ? r1 :
                     (raddr_b == 2'd2) ? r2 : r3;
    assign regs_flat = {r3, r2, r1, r0};
endmodule
