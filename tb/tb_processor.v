// -----------------------------------------------------------------------------
// tb_processor.v  --  self-checking testbench for the single-cycle core
//
//   A reference model (PC, R0-R3, flag register) runs in lock-step with the
//   DUT. Before every clock edge the testbench checks the fetched instruction
//   and the ALU output; after every edge it checks PC, all four registers and
//   all five flags.
//
//   Test 1  demo program (mem/program.hex), R0=0x5A R1=0x3C, prints a trace,
//           then checks final state against hand-computed golden values
//   Test 2  200 random 256-byte programs, random reset values, random clock
//           enable, random mid-run resets  (~60k instructions)
//   Test 3  hold: en = 0 must freeze all architectural state
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_processor;
    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg         en  = 1'b0;
    reg  [7:0]  init_r0 = 8'h00, init_r1 = 8'h00;
    wire [7:0]  pc_out, instr, alu_result;
    wire        zf, pf, cf, of, af;
    wire [31:0] regs_flat;

    processor #(.PROGRAM_FILE("../mem/program.hex")) dut (
        .clk(clk), .rst(rst), .en(en),
        .init_r0(init_r0), .init_r1(init_r1),
        .pc_out(pc_out), .instr(instr), .alu_result(alu_result),
        .zf(zf), .pf(pf), .cf(cf), .of(of), .af(af),
        .regs_flat(regs_flat)
    );

    `include "ref_model.vh"

    // ---------------- reference model state ----------------
    reg [7:0] rom   [0:255];     // testbench copy of the program
    reg [7:0] m_r   [0:3];
    reg [7:0] m_pc;
    reg [4:0] m_flags;           // {AF, OF, CF, PF, ZF}

    integer errors = 0, checks = 0, instrs = 0;

    task model_reset;
        begin
            m_pc = 0; m_flags = 0;
            m_r[0] = init_r0; m_r[1] = init_r1; m_r[2] = 8'h0F; m_r[3] = 8'h01;
        end
    endtask

    task fail(input [8*40-1:0] what, input [31:0] got, input [31:0] exp);
        begin
            errors = errors + 1;
            if (errors <= 20)
                $display("  ERROR @%0t %0s: got %h expected %h (pc=%h instr=%h)",
                         $time, what, got, exp, m_pc, rom[m_pc]);
        end
    endtask

    task check_state;
        begin
            checks = checks + 1;
            if (pc_out    !== m_pc)                              fail("PC",    pc_out, m_pc);
            if (regs_flat !== {m_r[3], m_r[2], m_r[1], m_r[0]})  fail("REGS",  regs_flat, {m_r[3], m_r[2], m_r[1], m_r[0]});
            if ({af, of, cf, pf, zf} !== m_flags)                fail("FLAGS", {af, of, cf, pf, zf}, m_flags);
        end
    endtask

    // one clock cycle: check combinational outputs, step model, clock DUT, check state
    reg [7:0]  ir;
    reg [3:0]  op;
    reg [12:0] r;
    reg [7:0]  last_pc, last_ir, last_alu;
    task cycle(input do_en, input do_rst);
        begin
            en = do_en; rst = do_rst;
            #4;                                         // let comb. logic settle
            ir = rom[m_pc]; op = ir[7:4];
            r  = ref_alu(op, m_r[ir[1:0]], m_r[ir[3:2]]);
            if (!do_rst) begin
                checks = checks + 1;
                if (instr      !== ir)     fail("INSTR", instr, ir);
                if (alu_result !== r[7:0]) fail("ALU",   alu_result, r[7:0]);
            end
            // model next state
            if (do_rst) model_reset;
            else if (do_en) begin
                if (op != 4'hF && op != 4'h6) m_r[ir[1:0]] = r[7:0];   // write-back
                if (op != 4'hF)               m_flags      = r[12:8];  // flags
                m_pc   = m_pc + 1;
                instrs = instrs + 1;
            end
            last_pc = pc_out; last_ir = instr; last_alu = alu_result;
            #1 clk = 1'b1;                              // posedge at t+5
            #4 check_state;
            #1 clk = 1'b0;
        end
    endtask

    task load_random_program;
        integer n;
        begin
            for (n = 0; n < 256; n = n + 1) begin
                rom[n] = $random;
                dut.u_rom.mem[n] = rom[n];
            end
        end
    endtask

    // -------------------------------- tests --------------------------------
    integer t, c;
    reg [7:0] snap_pc; reg [31:0] snap_regs; reg [4:0] snap_flags;

    initial begin
        $readmemh("../mem/program.hex", rom);

        // ---------- Test 1: demo program with a printed trace ----------
        $display("\n=== Test 1: demo program  (R0=5A R1=3C R2=0F R3=01) ===");
        init_r0 = 8'h5A; init_r1 = 8'h3C;
        cycle(0, 1);
        $display(" PC | instr | ALU | R0 R1 R2 R3 | A O C P Z");
        for (c = 0; c < 17; c = c + 1) begin
            cycle(1, 0);
            $display(" %h |  %h   | %h  | %h %h %h %h | %b %b %b %b %b",
                     last_pc, last_ir, last_alu,
                     regs_flat[7:0], regs_flat[15:8], regs_flat[23:16], regs_flat[31:24],
                     af, of, cf, pf, zf);
        end
        // golden values worked out by hand for this program and these inputs
        // (see README "Demo trace"): R0=00 R1=0D R2=10 R3=00, flags O=1 Z=1 P=1
        if (regs_flat !== 32'h00_10_0D_00) fail("GOLDEN REGS",  regs_flat, 32'h00100D00);
        if ({af, of, cf, pf, zf} !== 5'b01011) fail("GOLDEN FLAGS", {af, of, cf, pf, zf}, 5'b01011);
        $display("Test 1 done, errors so far: %0d", errors);

        // ---------- Test 2: random programs ----------
        $display("\n=== Test 2: 200 random programs, random enable and resets ===");
        for (t = 0; t < 200; t = t + 1) begin
            load_random_program;
            init_r0 = $random; init_r1 = $random;
            cycle(0, 1);
            for (c = 0; c < 300; c = c + 1) begin
                if (($random & 63) == 0) begin           // occasional mid-run reset
                    init_r0 = $random; init_r1 = $random;
                    cycle($random, 1);
                end else
                    cycle(($random & 7) != 0, 0);        // en high ~87% of cycles
            end
        end
        $display("Test 2 done, errors so far: %0d", errors);

        // ---------- Test 3: en = 0 holds state ----------
        $display("\n=== Test 3: clock enable low freezes state ===");
        snap_pc = pc_out; snap_regs = regs_flat; snap_flags = {af, of, cf, pf, zf};
        for (c = 0; c < 50; c = c + 1) cycle(0, 0);
        if (pc_out !== snap_pc || regs_flat !== snap_regs || {af, of, cf, pf, zf} !== snap_flags)
            fail("HOLD", 0, 1);
        $display("Test 3 done, errors so far: %0d", errors);

        if (errors == 0)
            $display("\ntb_processor: PASS  (%0d instructions executed, %0d checks)", instrs, checks);
        else
            $display("\ntb_processor: FAIL  (%0d errors)", errors);
        $finish;
    end
endmodule
