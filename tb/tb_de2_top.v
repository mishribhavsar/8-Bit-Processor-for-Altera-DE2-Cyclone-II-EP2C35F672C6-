// -----------------------------------------------------------------------------
// tb_de2_top.v  --  board-level smoke test (step mode)
//   Holds KEY[0] for reset with SW = 3C_5A, presses KEY[1] five times and
//   checks PC, registers and what HEX7..HEX0 / LEDG show.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_de2_top;
    reg         CLOCK_50 = 1'b0;
    reg  [3:0]  KEY = 4'hF;
    reg  [17:0] SW  = {2'b00, 8'h3C, 8'h5A};
    wire [8:0]  LEDG;
    wire [17:0] LEDR;
    wire [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7;

    de2_top dut (.CLOCK_50(CLOCK_50), .KEY(KEY), .SW(SW), .LEDG(LEDG), .LEDR(LEDR),
                 .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3),
                 .HEX4(HEX4), .HEX5(HEX5), .HEX6(HEX6), .HEX7(HEX7));

    always #10 CLOCK_50 = ~CLOCK_50;           // 50 MHz

    // inverse of seg7_hex, so the test reads the displays like a person would
    function [3:0] unseg; input [6:0] s;
        case (s)
            7'b1000000: unseg = 4'h0; 7'b1111001: unseg = 4'h1; 7'b0100100: unseg = 4'h2;
            7'b0110000: unseg = 4'h3; 7'b0011001: unseg = 4'h4; 7'b0010010: unseg = 4'h5;
            7'b0000010: unseg = 4'h6; 7'b1111000: unseg = 4'h7; 7'b0000000: unseg = 4'h8;
            7'b0010000: unseg = 4'h9; 7'b0001000: unseg = 4'hA; 7'b0000011: unseg = 4'hB;
            7'b1000110: unseg = 4'hC; 7'b0100001: unseg = 4'hD; 7'b0000110: unseg = 4'hE;
            default:    unseg = 4'hF;
        endcase
    endfunction

    integer i, errors = 0;
    reg [31:0] hex;
    task press_step; begin
        KEY[1] = 1'b0; #3_000_000;              // 3 ms pressed
        KEY[1] = 1'b1; #3_000_000;              // 3 ms released
    end endtask

    // count executed instructions to prove one press = one instruction
    integer steps = 0;
    always @(posedge CLOCK_50) if (dut.step_en) steps = steps + 1;

    initial begin
        KEY[0] = 1'b0; #1_000;                  // reset
        KEY[0] = 1'b1; #1_000;
        for (i = 0; i < 5; i = i + 1) press_step;

        hex = {unseg(HEX7), unseg(HEX6), unseg(HEX5), unseg(HEX4),
               unseg(HEX3), unseg(HEX2), unseg(HEX1), unseg(HEX0)};
        $display("after 5 presses: HEX7..0 = %h  LEDG = %b  steps = %0d", hex, LEDG, steps);
        // PC=05, instr=44 (XOR R0,R1), R0=95, R1=0D  (see demo trace)
        if (hex !== 32'h05_44_95_0D) begin errors = errors + 1; $display("  ERROR: display"); end
        if (steps != 5)              begin errors = errors + 1; $display("  ERROR: step count"); end
        if (LEDR[7:0] !== 8'h98)     begin errors = errors + 1; $display("  ERROR: LEDR preview"); end

        SW[16] = 1'b1; #100;                    // show R2/R3
        if ({unseg(HEX3), unseg(HEX2), unseg(HEX1), unseg(HEX0)} !== 16'h0F_01) begin
            errors = errors + 1; $display("  ERROR: R2/R3 display"); end

        if (errors == 0) $display("tb_de2_top: PASS");
        else             $display("tb_de2_top: FAIL (%0d)", errors);
        $finish;
    end
endmodule
