`timescale 1ns/1ps
// Data memory: 256 x 8, combinational read, write on clock edge
//   0xFE = output port (LEDs), 0xFF = input port (switches)
module data_mem (
    input            clk,
    input            rst,
    input            we,          // already qualified with the clock enable
    input      [7:0] waddr,
    input      [7:0] wdata,
    input      [7:0] raddr,
    output     [7:0] rdata,
    input      [7:0] io_in,
    output reg [7:0] io_out
);
    reg [7:0] mem [0:253];
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 254; i = i + 1) mem[i] <= 8'h00;
            io_out <= 8'h00;
        end else if (we) begin
            if (waddr == 8'hFE)      io_out     <= wdata;
            else if (waddr != 8'hFF) mem[waddr] <= wdata;
        end
    end

    assign rdata = (raddr == 8'hFF) ? io_in  :
                   (raddr == 8'hFE) ? io_out : mem[raddr];
endmodule
