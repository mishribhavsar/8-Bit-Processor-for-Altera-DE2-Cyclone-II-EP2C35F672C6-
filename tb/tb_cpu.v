// -----------------------------------------------------------------------------
// tb_cpu.v  --  self-checking testbench for both cores
//   compile plain        -> tests processor      (single-cycle)
//   compile with -DPIPE  -> tests processor_pipe (3-stage pipeline)
//
//   An instruction-level reference model (ref_cpu.vh) steps once for every
//   instruction the DUT retires. Each retirement checks PC and instruction;
//   after every clock edge registers, flags, output port and the stored-to
//   memory byte are compared; full data memory is compared after each program.
//
//   Test 1  demo program (sum 1..10): trace, golden results, CPI
//   Test 2  directed hazard program (tb/programs/hazards.hex): golden results
//   Test 3  300 random programs, random input port, random clock enable,
//           random mid-run resets
//   Test 4  en = 0 freezes all state
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
`ifdef PIPE
  `define DUT_MODULE processor_pipe
  `define DUT_NAME   "processor_pipe (3-stage)"
`else
  `define DUT_MODULE processor
  `define DUT_NAME   "processor (single-cycle)"
`endif

module tb_cpu;
    reg         clk = 1'b0, rst = 1'b1, en = 1'b0;
    reg  [7:0]  io_in = 8'h00;
    wire [7:0]  io_out, pc_out, retire_pc;
    wire [15:0] retire_instr;
    wire        retire_valid, halted, zf, pf, cf, of, af;
    wire [31:0] regs_flat;

    `DUT_MODULE #(.PROGRAM_FILE("../mem/program.hex")) dut (
        .clk(clk), .rst(rst), .en(en), .io_in(io_in), .io_out(io_out),
        .pc_out(pc_out), .retire_valid(retire_valid), .retire_pc(retire_pc),
        .retire_instr(retire_instr), .halted(halted),
        .zf(zf), .pf(pf), .cf(cf), .of(of), .af(af), .regs_flat(regs_flat)
    );

    `include "ref_model.vh"
    `include "ref_cpu.vh"

    integer errors = 0, checks = 0;
    integer cycles = 0, retired = 0, n_fwd = 0, n_flush_e = 0, n_flush_d = 0;
    reg     trace = 0;
    integer k;

    task fail(input [8*24-1:0] what, input [31:0] got, input [31:0] exp);
        begin
            errors = errors + 1;
            if (errors <= 20)
                $display("  ERROR @%0t %0s: got %h expected %h (model pc=%h)",
                         $time, what, got, exp, m_pc);
        end
    endtask

    task check_state;
        begin
            checks = checks + 1;
            if (regs_flat !== {m_r[3], m_r[2], m_r[1], m_r[0]})
                fail("REGS", regs_flat, {m_r[3], m_r[2], m_r[1], m_r[0]});
            if ({af, of, cf, pf, zf} !== m_flags) fail("FLAGS", {af, of, cf, pf, zf}, m_flags);
            if (io_out !== m_out)                 fail("IO_OUT", io_out, m_out);
            if (m_last_was_st && m_last_st_addr < 8'hFE &&
                dut.u_dmem.mem[m_last_st_addr] !== m_mem[m_last_st_addr])
                fail("STORE", dut.u_dmem.mem[m_last_st_addr], m_mem[m_last_st_addr]);
        end
    endtask

    task check_memory;
        begin
            for (k = 0; k < 254; k = k + 1)
                if (dut.u_dmem.mem[k] !== m_mem[k]) fail("DMEM", k, m_mem[k]);
        end
    endtask

    // one clock: retire check + model step before the edge, state check after
    task cycle(input do_en, input do_rst);
        begin
            en = do_en; rst = do_rst;
            #4;
            m_last_was_st = 0;
            if (do_rst) begin
                model_reset;
            end else if (do_en) begin
                cycles = cycles + 1;
`ifdef PIPE
                if (dut.valid_d && (dut.fwd_a || dut.fwd_b)) n_fwd = n_fwd + 1;
                if (dut.flush_e) n_flush_e = n_flush_e + 1;
                if (dut.flush_d) n_flush_d = n_flush_d + 1;
                if (trace)
                    $display(" %3d | IF %h | ID %s | EX %s | %s%s",
                             cycles, dut.pc_f,
                             dut.valid_d ? hex2(dut.pc_d) : "--",
                             dut.valid_e ? hex2(dut.pc_e) : "--",
                             (dut.valid_d && (dut.fwd_a || dut.fwd_b)) ? "fwd " : "    ",
                             dut.flush_e ? "flush IF+ID" : dut.flush_d ? "flush IF" : "");
`endif
                if (retire_valid) begin
                    checks = checks + 1;
                    if (retire_pc    !== m_pc)        fail("RETIRE_PC", retire_pc, m_pc);
                    if (retire_instr !== m_rom[m_pc]) fail("RETIRE_INSTR", retire_instr, m_rom[m_pc]);
                    model_step(io_in);
                    retired = retired + 1;
                end
            end
            #1 clk = 1'b1;
            #4 check_state;
            #1 clk = 1'b0;
        end
    endtask

    function [15:0] hex2;               // 2 hex digits as a string
        input [7:0] v;
        reg [7:0] h, l;
        begin
            h = (v[7:4] < 10) ? "0" + v[7:4] : "a" + v[7:4] - 10;
            l = (v[3:0] < 10) ? "0" + v[3:0] : "a" + v[3:0] - 10;
            hex2 = {h, l};
        end
    endfunction

    task load_program(input [8*64-1:0] file);
        begin
            $readmemh(file, m_rom);
            for (k = 0; k < 256; k = k + 1) dut.u_imem.mem[k] = m_rom[k];
        end
    endtask

    task load_random_program;
        reg [15:0] w;
        begin
            for (k = 0; k < 256; k = k + 1) begin
                w = $random;
                // keep HLT rare so programs run long enough to be interesting
                if (w[15:11] == 5'h18 && ($random & 3) != 0) w[15:11] = 5'h0F;
                m_rom[k] = w;
                dut.u_imem.mem[k] = w;
            end
        end
    endtask

    task stats_reset; begin cycles = 0; retired = 0; n_fwd = 0; n_flush_e = 0; n_flush_d = 0; end endtask

    // run until HLT retires (plus a few cycles), return with en low
    task run_to_halt(input integer max_cycles);
        integer c;
        begin
            c = 0;
            while (!(halted && retire_valid) && c < max_cycles) begin
                cycle(1, 0); c = c + 1;
            end
            if (c >= max_cycles) fail("NO_HALT", c, max_cycles);
        end
    endtask

    integer t, c, cyc_demo, ret_demo;
    reg [7:0] snap_pc; reg [31:0] snap_regs; reg [4:0] snap_flags;
    reg [7:0] exp_table [0:9];

    initial begin
        $display("\n##### %s #####", `DUT_NAME);

        // ---------------- Test 1: demo program ----------------
        $display("\n=== Test 1: demo program, N = 10 (sum 1..10) ===");
        load_program("../mem/program.hex");
        io_in = 8'd10;
        cycle(0, 1);
        stats_reset;
`ifdef PIPE
        $display(" cyc | IF | ID | EX | hazard");
        trace = 1;
        for (c = 0; c < 16; c = c + 1) cycle(1, 0);
        trace = 0;
        $display(" ...");
`endif
        run_to_halt(500);
        cyc_demo = cycles; ret_demo = retired;
        exp_table[0] = 8'h0A; exp_table[1] = 8'h13; exp_table[2] = 8'h1B; exp_table[3] = 8'h22;
        exp_table[4] = 8'h28; exp_table[5] = 8'h2D; exp_table[6] = 8'h31; exp_table[7] = 8'h34;
        exp_table[8] = 8'h36; exp_table[9] = 8'h37;
        if (io_out !== 8'h37) fail("GOLDEN OUT", io_out, 8'h37);
        if (regs_flat !== 32'h2A_00_00_37) fail("GOLDEN REGS", regs_flat, 32'h2A000037);
        for (k = 0; k < 10; k = k + 1)
            if (dut.u_dmem.mem[8'h20 + k] !== exp_table[k]) fail("GOLDEN TABLE", k, exp_table[k]);
        check_memory;
        $display(" OUT = %h, R0..R3 = %h %h %h %h", io_out,
                 regs_flat[7:0], regs_flat[15:8], regs_flat[23:16], regs_flat[31:24]);
        $display(" %0d instructions in %0d cycles  ->  CPI = %0d.%02d   (forwards %0d, IF+ID flushes %0d, IF flushes %0d)",
                 ret_demo, cyc_demo, cyc_demo / ret_demo, (cyc_demo * 100 / ret_demo) % 100,
                 n_fwd, n_flush_e, n_flush_d);
        $display("Test 1 done, errors so far: %0d", errors);

        // ---------------- Test 2: directed hazards ----------------
        $display("\n=== Test 2: directed hazard program ===");
        load_program("../tb/programs/hazards.hex");
        cycle(0, 1);
        stats_reset;
        run_to_halt(500);
        if (io_out !== 8'hA5) fail("HAZARD OUT", io_out, 8'hA5);
        if (regs_flat !== 32'hA5_10_10_00) fail("HAZARD REGS", regs_flat, 32'hA5101000);
        if (dut.u_dmem.mem[8'h10] !== 8'h20) fail("HAZARD MEM", dut.u_dmem.mem[8'h10], 8'h20);
        check_memory;
        $display(" OUT = %h (A5 = pass)  forwards %0d, IF+ID flushes %0d, IF flushes %0d",
                 io_out, n_fwd, n_flush_e, n_flush_d);
        $display("Test 2 done, errors so far: %0d", errors);

        // ---------------- Test 3: random programs ----------------
        $display("\n=== Test 3: 300 random programs ===");
        stats_reset;
        for (t = 0; t < 300; t = t + 1) begin
            load_random_program;
            cycle(0, 1);
            for (c = 0; c < 400; c = c + 1) begin
                io_in = $random;
                if (($random & 127) == 0) cycle($random, 1);          // occasional reset
                else                      cycle(($random & 7) != 0, 0); // en ~87%
            end
            check_memory;
        end
        $display(" %0d instructions retired in %0d enabled cycles (forwards %0d, IF+ID flushes %0d, IF flushes %0d)",
                 retired, cycles, n_fwd, n_flush_e, n_flush_d);
        $display("Test 3 done, errors so far: %0d", errors);

        // ---------------- Test 4: hold ----------------
        $display("\n=== Test 4: clock enable low freezes state ===");
        snap_pc = pc_out; snap_regs = regs_flat; snap_flags = {af, of, cf, pf, zf};
        for (c = 0; c < 50; c = c + 1) cycle(0, 0);
        if (pc_out !== snap_pc || regs_flat !== snap_regs || {af, of, cf, pf, zf} !== snap_flags)
            fail("HOLD", 0, 1);
        $display("Test 4 done, errors so far: %0d", errors);

        if (errors == 0) $display("\ntb_cpu [%s]: PASS  (%0d checks)", `DUT_NAME, checks);
        else             $display("\ntb_cpu [%s]: FAIL  (%0d errors)", `DUT_NAME, errors);
        $finish;
    end
endmodule
