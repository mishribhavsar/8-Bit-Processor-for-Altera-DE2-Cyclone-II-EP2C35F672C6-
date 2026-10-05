`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// register_file.v  --  4 x 8-bit register file
//   two combinational read ports, one synchronous write port
//   synchronous reset loads R0/R1 from inputs (switches on the board),
//   R2/R3 from parameters (there is no load-immediate instruction)
// -----------------------------------------------------------------------------
module register_file #(
    parameter [7:0] R2_INIT = 8'h0F,
    parameter [7:0] R3_INIT = 8'h01
) (
    input            clk,
    input            rst,        // synchronous, active high
    input            en,         // clock enable (one instruction per enable)
    input      [7:0] init_r0,
    input      [7:0] init_r1,
    input      [1:0] rd_addr,    // read port A / write address
    input      [1:0] rs_addr,    // read port B
    input            we,
    input      [7:0] wdata,
    output     [7:0] rd_data,
    output     [7:0] rs_data,
    output    [31:0] regs_flat   // {R3, R2, R1, R0} for debug / display
);
    reg [7:0] r0, r1, r2, r3;

    always @(posedge clk) begin
        if (rst) begin
            r0 <= init_r0;
            r1 <= init_r1;
            r2 <= R2_INIT;
            r3 <= R3_INIT;
        end else if (en && we) begin
            case (rd_addr)
                2'd0: r0 <= wdata;
                2'd1: r1 <= wdata;
                2'd2: r2 <= wdata;
                2'd3: r3 <= wdata;
            endcase
        end
    end

    assign rd_data = (rd_addr == 2'd0) ? r0 : (rd_addr == 2'd1) ? r1 :
                     (rd_addr == 2'd2) ? r2 : r3;
    assign rs_data = (rs_addr == 2'd0) ? r0 : (rs_addr == 2'd1) ? r1 :
                     (rs_addr == 2'd2) ? r2 : r3;
    assign regs_flat = {r3, r2, r1, r0};
endmodule
