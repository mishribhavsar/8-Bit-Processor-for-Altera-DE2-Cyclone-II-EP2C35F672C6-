`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// instr_rom.v  --  256 x 8 instruction ROM, combinational read
//   Contents come from a hex file (one byte per line, 256 lines) produced by
//   tools/asm.py. The path is relative to the tool's working directory;
//   both quartus/ and sim/ sit next to mem/, so "../mem/program.hex" works
//   for Quartus, ModelSim and Icarus alike.
// -----------------------------------------------------------------------------
module instr_rom #(
    parameter PROGRAM_FILE = "../mem/program.hex"
) (
    input  [7:0] addr,
    output [7:0] instr
);
    reg [7:0] mem [0:255];

    initial $readmemh(PROGRAM_FILE, mem);

    assign instr = mem[addr];
endmodule
