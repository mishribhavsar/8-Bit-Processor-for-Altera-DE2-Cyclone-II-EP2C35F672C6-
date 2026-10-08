// -----------------------------------------------------------------------------
// tb_trace_ooo.v  --  prints a cycle-by-cycle event trace of the out-of-order
//   core (dispatch / issue / CDB / commit / flush) for a short program run.
//   Usage: iverilog ... -DTRACE_FILE=\"../bench/mul_loop.hex\" tb_trace_ooo.v
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`ifndef TRACE_FILE
  `define TRACE_FILE "../bench/mul_loop.hex"
`endif
module tb_trace_ooo;
    reg clk = 0, rst = 1;
    reg [7:0] io_in = 8'd4;
    wire [7:0] io_out, pc_out, rpc; wire [15:0] rir; wire rv, h, ev, fw, fl, zf, pf, cf, of, af;
    wire [31:0] regs;

    processor_ooo dut (.clk(clk), .rst(rst), .en(1'b1), .io_in(io_in), .io_out(io_out),
        .pc_out(pc_out), .retire_valid(rv), .retire_pc(rpc), .retire_instr(rir), .halted(h),
        .ex_valid(ev), .dbg_fwd(fw), .dbg_flush(fl),
        .zf(zf), .pf(pf), .cf(cf), .of(of), .af(af), .regs_flat(regs));

    always #5 clk = ~clk;

    integer cyc = 0, k;
    reg [15:0] rom [0:255];

    initial begin
        $readmemh(`TRACE_FILE, rom);
        for (k = 0; k < 256; k = k + 1) dut.u_imem.mem[k] = rom[k];
        @(negedge clk) rst = 0;
        $display("cyc | dispatch (pc:instr ->tag)   | issue                     | CDB      | commit      | ROB");
        repeat (45) begin
            @(posedge clk); #0;
        end
        $finish;
    end

    always @(negedge clk) if (!rst) begin
        cyc = cyc + 1;
        $write("%3d | ", cyc);
        if (dut.d_fire) $write("%h:%h ->t%0d%s            | ", dut.fb_pc, dut.fb_instr, dut.tail,
                               dut.d_redir ? " redir" : "      ");
        else            $write("%-28s| ", dut.fb_valid ? "(stall)" : "-");
        $write("%s%s%s",
               dut.alu_issue ? "ALU:t" : "     ", dut.alu_issue ? "0" + dut.ra_tag[dut.ra_sel] : " ",
               "  ");
        $write("%s%s  ", dut.md_issue ? "MD:t" : "    ", dut.md_issue ? "0" + dut.rm_tag[dut.rm_sel] : " ");
        $write("%s%s         | ", dut.ls_issue ? "LS:t" : "    ", dut.ls_issue ? "0" + dut.rl_tag[dut.rl_sel] : " ");
        if (dut.cdb_v) $write("t%0d=%h    | ", dut.cdb_tag, dut.cdb_val); else $write("         | ");
        if (dut.c_fire) $write("t%0d pc %h%s | ", dut.head, dut.rob_pc[dut.head], dut.flush ? " FLUSH" : "      ");
        else            $write("            | ");
        $display("%0d", dut.count);
    end
endmodule
