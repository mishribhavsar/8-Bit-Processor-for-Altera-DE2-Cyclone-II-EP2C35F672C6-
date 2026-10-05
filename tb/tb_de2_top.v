// -----------------------------------------------------------------------------
// tb_de2_top.v  --  board-level test of the DE2 wrapper
//   Uses short debounce/run dividers so a full program run fits in simulation.
//   1) step mode: reset with SW[7:0] = 10, press KEY[1] five times, read the
//      7-segment displays back for both cores
//   2) run mode: run 100 clocks so the demo program finishes, check LEDR = 0x37 (sum 1..10)
//      and the HLT LED for both cores
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_de2_top;
    reg         CLOCK_50 = 1'b0;
    reg  [3:0]  KEY = 4'hF;
    reg  [17:0] SW  = 18'd10;              // input port = 10, step mode, single-cycle view
    wire [8:0]  LEDG;
    wire [17:0] LEDR;
    wire [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7;

    de2_top #(.TICK_DIV(50), .RUN_DIV(200)) dut (
        .CLOCK_50(CLOCK_50), .KEY(KEY), .SW(SW), .LEDG(LEDG), .LEDR(LEDR),
        .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3),
        .HEX4(HEX4), .HEX5(HEX5), .HEX6(HEX6), .HEX7(HEX7));

    always #10 CLOCK_50 = ~CLOCK_50;

    // read a 7-segment digit back; '-' for the bubble dash
    function [7:0] unseg; input [6:0] s;
        case (s)
            7'b1000000: unseg = "0"; 7'b1111001: unseg = "1"; 7'b0100100: unseg = "2";
            7'b0110000: unseg = "3"; 7'b0011001: unseg = "4"; 7'b0010010: unseg = "5";
            7'b0000010: unseg = "6"; 7'b1111000: unseg = "7"; 7'b0000000: unseg = "8";
            7'b0010000: unseg = "9"; 7'b0001000: unseg = "A"; 7'b0000011: unseg = "B";
            7'b1000110: unseg = "C"; 7'b0100001: unseg = "D"; 7'b0000110: unseg = "E";
            7'b0001110: unseg = "F"; 7'b0111111: unseg = "-";
            default:    unseg = "?";
        endcase
    endfunction

    function [63:0] display; input dummy;
        display = {unseg(HEX7), unseg(HEX6), unseg(HEX5), unseg(HEX4),
                   unseg(HEX3), unseg(HEX2), unseg(HEX1), unseg(HEX0)};
    endfunction

    integer i, errors = 0, steps = 0;
    always @(posedge CLOCK_50) if (dut.step_en) steps = steps + 1;

    task press_step; begin
        KEY[1] = 1'b0; #5_000;             // 5 us pressed  (5 sample ticks)
        KEY[1] = 1'b1; #5_000;
    end endtask

    task expect_display(input [63:0] exp, input [8*20-1:0] what); begin
        if (display(0) !== exp) begin
            errors = errors + 1;
            $display("  ERROR %0s: display %s expected %s", what, display(0), exp);
        end else
            $display("  %-20s HEX7..0 = %s", what, display(0));
    end endtask

    initial begin
        KEY[0] = 1'b0; #1_000; KEY[0] = 1'b1; #1_000;

        // ---- step mode ----
        for (i = 0; i < 5; i = i + 1) press_step;
        if (steps != 5) begin errors = errors + 1; $display("  ERROR: %0d steps for 5 presses", steps); end

        // single-cycle: PC=05, instruction BEQ done (B00B), R0 = 00
        SW[16] = 1'b0; SW[15:14] = 2'd0; #200;
        expect_display("05B00B00", "single-cycle");
        // pipelined after 5 clocks: fetching 05, EX holds pc 03 (LDI R2,0 = 8400)
        SW[16] = 1'b1; #200;
        expect_display("05840000", "pipelined");
        // R3 = 0x20 (table pointer) in the single-cycle core
        SW[16] = 1'b0; SW[15:14] = 2'd3; #200;
        expect_display("05B00B20", "single-cycle R3");

        // ---- run mode until both cores reach HLT ----
        SW[17] = 1'b1;
        while (steps < 100) @(posedge CLOCK_50);   // demo needs 57 (single) / 77 (pipelined) clocks
        #10_000;
        SW[17] = 1'b0; #200;
        SW[16] = 1'b0; #200;
        if (LEDR[7:0] !== 8'h37 || !LEDR[17]) begin
            errors = errors + 1; $display("  ERROR: single-cycle LEDR = %h", LEDR); end
        SW[16] = 1'b1; #200;
        if (LEDR[7:0] !== 8'h37 || !LEDR[17]) begin
            errors = errors + 1; $display("  ERROR: pipelined LEDR = %h", LEDR); end
        $display("  run mode: both cores halted with LEDR[7:0] = %h (sum 1..10 = 0x37)", LEDR[7:0]);

        if (errors == 0) $display("tb_de2_top: PASS");
        else             $display("tb_de2_top: FAIL (%0d)", errors);
        $finish;
    end
endmodule
