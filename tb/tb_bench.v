// -----------------------------------------------------------------------------
// tb_bench.v  --  CPI comparison of the three cores on the same programs
//   For each benchmark and input N: the reference model computes the expected
//   final state, then each core runs to HLT; output port and registers must
//   match the model, and cycles / instructions give the CPI.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_bench;
    reg        clk = 0, rst = 1, en = 1;
    reg  [7:0] io_in = 8'd20;

    wire [7:0]  out_s, out_p, out_o;
    wire [31:0] regs_s, regs_p, regs_o;
    wire        rv_s, rv_p, rv_o, h_s, h_p, h_o;
    wire [7:0]  u8a, u8b, u8c, u8d, u8e, u8f;
    wire [15:0] u16a, u16b, u16c;
    wire [14:0] uflags;
    wire [8:0]  udbg;

    processor u_s (.clk(clk), .rst(rst), .en(en), .io_in(io_in), .io_out(out_s),
        .pc_out(u8a), .retire_valid(rv_s), .retire_pc(u8b), .retire_instr(u16a), .halted(h_s),
        .ex_valid(udbg[0]), .dbg_fwd(udbg[1]), .dbg_flush(udbg[2]),
        .zf(uflags[0]), .pf(uflags[1]), .cf(uflags[2]), .of(uflags[3]), .af(uflags[4]), .regs_flat(regs_s));
    processor_pipe u_p (.clk(clk), .rst(rst), .en(en), .io_in(io_in), .io_out(out_p),
        .pc_out(u8c), .retire_valid(rv_p), .retire_pc(u8d), .retire_instr(u16b), .halted(h_p),
        .ex_valid(udbg[3]), .dbg_fwd(udbg[4]), .dbg_flush(udbg[5]),
        .zf(uflags[5]), .pf(uflags[6]), .cf(uflags[7]), .of(uflags[8]), .af(uflags[9]), .regs_flat(regs_p));
`ifdef NO_FLAG_RENAME
    processor_ooo #(.FLAG_RENAME(0)) u_o (
`else
    processor_ooo u_o (
`endif.clk(clk), .rst(rst), .en(en), .io_in(io_in), .io_out(out_o),
        .pc_out(u8e), .retire_valid(rv_o), .retire_pc(u8f), .retire_instr(u16c), .halted(h_o),
        .ex_valid(udbg[6]), .dbg_fwd(udbg[7]), .dbg_flush(udbg[8]),
        .zf(uflags[10]), .pf(uflags[11]), .cf(uflags[12]), .of(uflags[13]), .af(uflags[14]), .regs_flat(regs_o));

    always #5 clk = ~clk;

    `include "ref_model.vh"
    `include "ref_cpu.vh"

    integer k, errors = 0;
    integer n_ret, cyc_s, cyc_p, cyc_o, ret_s, ret_p, ret_o;
    integer done_s, done_p, done_o, c;

    task run(input [8*32-1:0] name, input [8*64-1:0] file, input [7:0] n);
        begin
            $readmemh(file, m_rom);
            for (k = 0; k < 256; k = k + 1) begin
                u_s.MEM_inst.mem[k] = m_rom[k]; u_p.MEM_inst.mem[k] = m_rom[k]; u_o.MEM_inst.mem[k] = m_rom[k];
            end
            io_in = n;
            // reference: run the model to HLT
            model_reset; n_ret = 0;
            while (!m_halted && n_ret < 5000) begin model_step(io_in); n_ret = n_ret + 1; end
            n_ret = n_ret - 1;                       // HLT not counted
            // cores
            @(negedge clk) rst = 1; @(negedge clk) rst = 0;
            cyc_s = 0; cyc_p = 0; cyc_o = 0; ret_s = 0; ret_p = 0; ret_o = 0;
            done_s = 0; done_p = 0; done_o = 0;
            for (c = 0; c < 20000 && !(done_s && done_p && done_o); c = c + 1) begin
                @(posedge clk); #1;
            end
            if (out_s !== m_out || out_p !== m_out || out_o !== m_out ||
                regs_s !== {m_r[3], m_r[2], m_r[1], m_r[0]} ||
                regs_p !== {m_r[3], m_r[2], m_r[1], m_r[0]} ||
                regs_o !== {m_r[3], m_r[2], m_r[1], m_r[0]} ||
                ret_s != n_ret || ret_p != n_ret || ret_o != n_ret) begin
                errors = errors + 1;
                $display("  ERROR %0s: out %h/%h/%h exp %h, retired %0d/%0d/%0d exp %0d",
                         name, out_s, out_p, out_o, m_out, ret_s, ret_p, ret_o, n_ret);
            end
            $display(" %-12s N=%3d | %5d instr | single %5d cyc CPI %0d.%02d | pipe %5d cyc CPI %0d.%02d | OoO %5d cyc CPI %0d.%02d | OoO speed-up vs pipe %0d.%02dx",
                     name, n, n_ret,
                     cyc_s, cyc_s / n_ret, (cyc_s * 100 / n_ret) % 100,
                     cyc_p, cyc_p / n_ret, (cyc_p * 100 / n_ret) % 100,
                     cyc_o, cyc_o / n_ret, (cyc_o * 100 / n_ret) % 100,
                     cyc_p / cyc_o, (cyc_p * 100 / cyc_o) % 100);
        end
    endtask

    // count cycles until each core's HLT reaches the point of retiring
    always @(posedge clk) if (!rst) begin
        if (!done_s) begin if (h_s && rv_s) done_s = 1; else begin cyc_s = cyc_s + 1; if (rv_s) ret_s = ret_s + 1; end end
        if (!done_p) begin if (h_p && rv_p) done_p = 1; else begin cyc_p = cyc_p + 1; if (rv_p) ret_p = ret_p + 1; end end
        if (!done_o) begin if (h_o && rv_o) done_o = 1; else begin cyc_o = cyc_o + 1; if (rv_o) ret_o = ret_o + 1; end end
    end

    initial begin
`ifdef NO_FLAG_RENAME
        $display("\n*** OoO core built with FLAG_RENAME = 0 (ablation) ***");
`endif
        $display("\n=== CPI comparison (single-cycle has a 1-cycle combinational MUL/DIV;");
        $display("    pipeline and OoO use the 9-cycle iterative MUL/DIV unit) ===");
        run("alu_loop",   "../bench/alu_loop.hex",   8'd20);
        run("alu_loop",   "../bench/alu_loop.hex",   8'd100);
        run("mul_loop",   "../bench/mul_loop.hex",   8'd20);
        run("muldiv_mix", "../bench/muldiv_mix.hex", 8'd20);
        run("mul_loop",   "../bench/mul_loop.hex",   8'd100);
        run("muldiv_mix", "../bench/muldiv_mix.hex", 8'd100);
        if (errors == 0) $display("tb_bench: PASS  (all cores match the reference model)");
        else             $display("tb_bench: FAIL  (%0d)", errors);
        $finish;
    end
endmodule
