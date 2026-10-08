// -----------------------------------------------------------------------------
// tb_muldiv.v  --  exhaustive check of the iterative MUL/DIV unit
//   2 ops x 256 x 256 = 131,072 operations, result + 5 flags compared with the
//   ALU reference model, latency checked to be exactly 9 cycles (load + 8 iterations).
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_muldiv;
    reg        clk = 0, rst = 1, en = 1, flush = 0, start = 0, is_div = 0, ack = 0;
    reg  [7:0] a = 0, b = 0;
    wire       busy, done;
    wire [7:0] result;
    wire [4:0] flags;
    wire [2:0] tag;

    muldiv dut (.clk(clk), .rst(rst), .en(en), .flush(flush), .start(start), .is_div(is_div),
                .a(a), .b(b), .tag_in(3'd5), .ack(ack), .busy(busy), .done(done),
                .result(result), .flags(flags), .tag(tag));

    always #5 clk = ~clk;
    `include "ref_model.vh"

    integer i, j, k, lat, errors = 0, ops = 0;
    reg [12:0] exp;

    initial begin
        @(negedge clk) rst = 0;
        for (k = 0; k < 2; k = k + 1)
            for (i = 0; i < 256; i = i + 1)
                for (j = 0; j < 256; j = j + 1) begin
                    @(negedge clk);
                    a = i; b = j; is_div = k; start = 1;
                    @(negedge clk); start = 0; lat = 1;
                    a = $random; b = $random;           // operands must be latched
                    while (!done) begin @(negedge clk); lat = lat + 1; end
                    exp = ref_alu(k ? 4'hE : 4'hD, i[7:0], j[7:0]);
                    ops = ops + 1;
                    if ({flags, result} !== exp || lat != 9 || tag !== 3'd5) begin
                        errors = errors + 1;
                        if (errors <= 10)
                            $display("MISMATCH %s %h,%h: got %h/%b lat %0d, exp %h/%b",
                                     k ? "DIV" : "MUL", i, j, result, flags, lat, exp[7:0], exp[12:8]);
                    end
                    ack = 1; @(negedge clk); ack = 0;
                    if (done || busy) begin errors = errors + 1; $display("ack did not free the unit"); end
                end
        if (errors == 0) $display("tb_muldiv: PASS  (%0d operations, 9-cycle issue-to-result latency, result + 5 flags)", ops);
        else             $display("tb_muldiv: FAIL  (%0d errors)", errors);
        $finish;
    end
endmodule
