// -----------------------------------------------------------------------------
// ref_model.vh  --  behavioural reference model of the ALU (testbench only)
//
//   Written independently of rtl/alu.v: it works on integers and range
//   checks instead of bit tricks, so a shared misunderstanding is unlikely.
//   Returns {AF, OF, CF, PF, ZF, result[7:0]}  (13 bits)
// -----------------------------------------------------------------------------
function integer sgn8;            // two's-complement value of an 8-bit word
    input [7:0] v;
    begin
        sgn8 = (v > 127) ? v - 256 : v;
    end
endfunction

function [12:0] ref_alu;
    input [3:0] op;
    input [7:0] a, b;
    integer ua, ub, t, s, k, ones;
    reg [7:0] res;
    reg zf, pf, cf, of, af;
    begin
        ua = a; ub = b;
        res = 0; cf = 0; of = 0; af = 0;
        case (op)
            4'h0, 4'hB: begin                         // ADD, INC
                if (op == 4'hB) ub = 1;
                t   = ua + ub;
                res = t % 256;
                cf  = (t > 255);
                s   = sgn8(a) + sgn8(ub[7:0]);
                of  = (s > 127) || (s < -128);
                af  = ((ua % 16) + (ub % 16)) > 15;
            end
            4'h1, 4'h6, 4'hC: begin                   // SUB, CMP, DEC
                if (op == 4'hC) ub = 1;
                t   = ua - ub;
                res = (t + 256) % 256;
                cf  = (ua < ub);
                s   = sgn8(a) - sgn8(ub[7:0]);
                of  = (s > 127) || (s < -128);
                af  = (ua % 16) < (ub % 16);
            end
            4'h2: res = a & b;
            4'h3: res = a | b;
            4'h4: res = a ^ b;
            4'h5: res = 255 - ua;                     // NOT
            4'h7: begin                               // LSL
                res = (ua * 2) % 256;
                cf  = (ua >= 128);
                of  = (ua >= 128) != (res >= 128);    // sign changed
            end
            4'h8: begin                               // LSR
                res = ua / 2;
                cf  = ua % 2;
                of  = (ua >= 128);
            end
            4'h9: begin                               // ROR
                res = ua / 2 + (ua % 2) * 128;
                cf  = ua % 2;
            end
            4'hA: begin                               // ROL
                res = (ua * 2) % 256 + ua / 128;
                cf  = (ua >= 128);
            end
            4'hD: begin                               // MUL
                t   = ua * ub;
                res = t % 256;
                cf  = (t > 255);
                of  = (t > 255);
            end
            4'hE: begin                               // DIV
                if (ub == 0) begin res = 0; of = 1; end
                else         res = ua / ub;
            end
            default: res = 0;                         // NOP
        endcase
        zf   = (res == 0);
        ones = 0;
        for (k = 0; k < 8; k = k + 1) ones = ones + res[k];
        pf   = (ones % 2 == 0);
        ref_alu = {af, of, cf, pf, zf, res};
    end
endfunction
