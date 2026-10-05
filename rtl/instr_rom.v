`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// instr_rom.v  --  256 x 16 instruction ROM, combinational read
//   Contents: hex file from tools/asm.py (256 lines, 4 hex digits each).
//   The path is relative to the tool's working directory; quartus/ and sim/
//   both sit next to mem/, so "../mem/program.hex" works everywhere.
// -----------------------------------------------------------------------------
module instr_rom #(
    parameter PROGRAM_FILE = "../mem/program.hex"
) (
    input  [7:0]  addr,
    output [15:0] instr
);
    reg [15:0] mem [0:255];

    initial $readmemh(PROGRAM_FILE, mem);

    assign instr = mem[addr];
endmodule
