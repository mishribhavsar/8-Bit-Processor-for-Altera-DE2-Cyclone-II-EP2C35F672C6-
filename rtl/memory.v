`timescale 1ns/1ps
// Instruction ROM: 256 x 16, loaded from a hex file made by tools/asm.py
module memory #(
    parameter PROGRAM_FILE = "../mem/program.hex"
) (
    input  [7:0]  addr,
    output [15:0] instr
);
    reg [15:0] mem [0:255];

    initial $readmemh(PROGRAM_FILE, mem);

    assign instr = mem[addr];
endmodule
