`timescale 1ns/1ps
// Iterative MUL/DIV unit: shift-add multiply / restoring divide, 8 iterations
// start -> busy -> done (held until ack). Flags match the ALU.
module muldiv (
    input            clk,
    input            rst,
    input            en,          // clock enable
    input            flush,
    input            start,
    input            is_div,
    input      [7:0] a,           // Rd (multiplicand / dividend)
    input      [7:0] b,           // Rs (multiplier   / divisor)
    input      [2:0] tag_in,
    input            ack,         // result consumed
    output           busy,        // cannot accept a new operation
    output reg       done,
    output reg [7:0] result,
    output reg [4:0] flags,       // {AF, OF, CF, PF, ZF}
    output reg [2:0] tag
);
    reg        running, div_q;
    reg [3:0]  cnt;
    reg [15:0] acc, mcand;        // multiply
    reg [7:0]  mplier;
    reg [8:0]  rem;               // divide
    reg [7:0]  quo, dvsr;

    assign busy = running | done;

    // one restoring-division step
    wire [8:0] rem_sh  = {rem[7:0], quo[7]};
    wire       ge      = (rem_sh >= {1'b0, dvsr});
    wire [8:0] rem_nxt = ge ? rem_sh - {1'b0, dvsr} : rem_sh;

    // final values (valid when cnt == 7, i.e. on the last iteration)
    wire [15:0] prod_fin = mplier[0] ? acc + mcand : acc;
    wire [7:0]  quo_fin  = {quo[6:0], ge};

    function [4:0] mk_flags;      // {AF, OF, CF, PF, ZF}
        input [7:0] r;
        input       c, o;
        mk_flags = {1'b0, o, c, ~(^r), (r == 8'h00)};
    endfunction

    always @(posedge clk) begin
        if (rst || flush) begin
            running <= 1'b0; done <= 1'b0; cnt <= 4'd0;
        end else if (en) begin
            if (done && ack)
                done <= 1'b0;
            if (start && !running && !done) begin
                running <= 1'b1; div_q <= is_div; cnt <= 4'd0; tag <= tag_in;
                acc <= 16'd0; mcand <= {8'd0, a}; mplier <= b;
                rem <= 9'd0; quo <= a; dvsr <= b;
            end else if (running) begin
                cnt <= cnt + 4'd1;
                if (!div_q) begin
                    acc    <= prod_fin;
                    mcand  <= {mcand[14:0], 1'b0};
                    mplier <= {1'b0, mplier[7:1]};
                end else begin
                    rem <= rem_nxt;
                    quo <= quo_fin;
                end
                if (cnt == 4'd7) begin
                    running <= 1'b0;
                    done    <= 1'b1;
                    if (!div_q) begin
                        result <= prod_fin[7:0];
                        flags  <= mk_flags(prod_fin[7:0], |prod_fin[15:8], |prod_fin[15:8]);
                    end else if (dvsr == 8'd0) begin
                        result <= 8'h00;
                        flags  <= mk_flags(8'h00, 1'b0, 1'b1);
                    end else begin
                        result <= quo_fin;
                        flags  <= mk_flags(quo_fin, 1'b0, 1'b0);
                    end
                end
            end
        end
    end
endmodule
