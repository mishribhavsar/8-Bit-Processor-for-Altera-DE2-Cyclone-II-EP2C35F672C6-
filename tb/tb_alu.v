// -----------------------------------------------------------------------------
// tb_alu.v  --  exhaustive self-checking ALU testbench
//   16 opcodes x 256 x 256 operand pairs = 1,048,576 vectors.
//   Every vector checks the 8-bit result and all five flags against the
//   reference model; the run ends with PASS or FAIL.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_alu;
    reg  [7:0] a, b;
    reg  [3:0] op;
    wire [7:0] result;
    wire       zf, pf, cf, of, af;

    alu dut (.a(a), .b(b), .op(op), .result(result),
             .zf(zf), .pf(pf), .cf(cf), .of(of), .af(af));

    `include "ref_model.vh"

    integer i, j, k, errors, checks;
    reg [12:0] exp;
    reg [12:0] got;

    initial begin
        errors = 0; checks = 0;
        for (k = 0; k < 16; k = k + 1)
            for (i = 0; i < 256; i = i + 1)
                for (j = 0; j < 256; j = j + 1) begin
                    op = k; a = i; b = j;
                    #1;
                    exp = ref_alu(op, a, b);
                    got = {af, of, cf, pf, zf, result};
                    checks = checks + 1;
                    if (got !== exp) begin
                        errors = errors + 1;
                        if (errors <= 10)
                            $display("MISMATCH op=%h a=%h b=%h : got res=%h AOCPZ=%b  exp res=%h AOCPZ=%b",
                                     op, a, b, got[7:0], got[12:8], exp[7:0], exp[12:8]);
                    end
                end
        if (errors == 0)
            $display("tb_alu: PASS  (%0d vectors, 16 opcodes x 256 x 256, result + 5 flags)", checks);
        else
            $display("tb_alu: FAIL  (%0d of %0d vectors mismatched)", errors, checks);
        $finish;
    end
endmodule
