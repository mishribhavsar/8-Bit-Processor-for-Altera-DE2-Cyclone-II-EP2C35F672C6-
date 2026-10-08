`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// data_mem.v  --  256 x 8 data memory with memory-mapped I/O
//
//   0x00-0xFD  RAM            combinational read, write on clock edge
//   0xFE       OUT port       read/write; drives io_out (LEDs on the board)
//   0xFF       IN  port       read only; returns io_in (switches on the board)
//
//   Separate read and write addresses: the in-order cores tie them together;
//   the out-of-order core reads for a load while a store commits elsewhere.
//   Combinational read is what lets LD complete in one cycle (single-cycle
//   core) and in the EX stage (pipelined core) without a load-use stall.
//   On Cyclone II this is built from logic cells, since M4K blocks only
//   support registered reads. Synchronous reset clears RAM and OUT.
// -----------------------------------------------------------------------------
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
