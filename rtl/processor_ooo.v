`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// processor_ooo.v  --  out-of-order core: Tomasulo + reorder buffer
//                      with renaming of the FLAGS register
//
//   Same ISA and port list as processor.v / processor_pipe.v.
//
//   Front end (in order)
//     fetch buffer -> dispatch: allocate a ROB entry, rename, read operands,
//     place the instruction in a reservation station.
//     JMP and backward BEQ/BNE (static BTFN prediction: backward = taken)
//     redirect fetch at dispatch; HLT stops fetch.
//
//   Execution (out of order)
//     RS_ALU (4)  -> ALU, 1 cycle       ALU ops, CMP, BEQ/BNE resolution
//     RS_MD  (2)  -> muldiv, 9 cycles   MUL, DIV (iterative, one at a time)
//     RS_LS  (4)  -> load/store unit    LD/LDR read memory; ST/STR compute
//                                       address + data (memory written at commit)
//     Each RS issues its oldest ready entry. One common data bus (CDB) per
//     cycle, granted to the oldest finished result; the CDB writes the ROB
//     and wakes up waiting RS entries.
//
//   Renaming
//     RAT has 5 entries: R0-R3 and FLAGS. Every flag-setting instruction is a
//     producer of a new FLAGS version and BEQ/BNE are consumers, so a CMP ->
//     BNE pair is tracked exactly like a register dependency, and flag WAW
//     hazards between back-to-back ALU ops disappear.
//
//   Memory ordering (conservative)
//     Stores write memory only at commit. A load issues only when no older
//     store is still in the ROB, so no store-to-load forwarding is needed.
//
//   Commit (in order, 1 per cycle)
//     Head of the ROB writes the architectural register file / flags /
//     memory. A mispredicted branch flushes ROB, RS, RAT and fetch, then
//     redirects. HLT stops the core.
// -----------------------------------------------------------------------------
module processor_ooo #(
    parameter PROGRAM_FILE = "../mem/program.hex",
    // 1: FLAGS is renamed like a register (default).
    // 0: ablation - a BEQ/BNE may not dispatch while any older flag-setting
    //    instruction is in flight (condition codes treated as serializing).
    parameter FLAG_RENAME  = 1
) (
    input         clk,
    input         rst,
    input         en,
    input  [7:0]  io_in,
    output [7:0]  io_out,
    output [7:0]  pc_out,
    output        retire_valid,
    output [7:0]  retire_pc,
    output [15:0] retire_instr,
    output        halted,
    output        ex_valid,       // ROB not empty (display shows the ROB head)
    output        dbg_fwd,        // CDB broadcast this cycle
    output        dbg_flush,      // mispredict flush this cycle
    output        zf, pf, cf, of, af,
    output [31:0] regs_flat
);
    integer i;

    // ======================= opcodes ========================================
    localparam OP_MUL = 5'h0D, OP_DIV = 5'h0E, OP_NOP = 5'h0F, OP_LDI = 5'h10,
               OP_LD  = 5'h11, OP_ST  = 5'h12, OP_LDR = 5'h13, OP_STR = 5'h14,
               OP_BEQ = 5'h16, OP_BNE = 5'h17;

    // ======================= architectural state ============================
    reg  [4:0]  aflags;                     // committed {AF, OF, CF, PF, ZF}
    reg         halted_r;

    // ======================= front end ======================================
    reg  [7:0]  pc;
    reg         fb_valid;
    reg  [7:0]  fb_pc;
    reg  [15:0] fb_instr;
    reg         stop_fetch;                 // HLT dispatched
    wire [15:0] imem_q;

    instr_rom #(.PROGRAM_FILE(PROGRAM_FILE)) u_imem (.addr(pc), .instr(imem_q));

    wire [3:0] d_alu_op;
    wire [1:0] d_rd, d_rs, d_wb_sel;
    wire [7:0] d_imm;
    wire       d_reg_write, d_flag_write, d_mem_write, d_addr_reg;
    wire       d_jump, d_beq, d_bne, d_halt, d_rd_used, d_rs_used;

    decoder u_dec (
        .instr(fb_instr), .alu_op(d_alu_op), .rd(d_rd), .rs(d_rs), .imm(d_imm),
        .reg_write(d_reg_write), .flag_write(d_flag_write), .wb_sel(d_wb_sel),
        .mem_write(d_mem_write), .addr_reg(d_addr_reg),
        .jump(d_jump), .beq(d_beq), .bne(d_bne), .halt(d_halt),
        .rd_used(d_rd_used), .rs_used(d_rs_used)
    );

    wire [4:0] d_op     = fb_instr[15:11];
    wire       d_is_md  = (d_op == OP_MUL) || (d_op == OP_DIV);
    wire       d_is_br  = d_beq | d_bne;
    wire       d_is_ls  = (d_op >= OP_LD) && (d_op <= OP_STR);
    wire       d_is_alu = ((d_op <= 5'h0E) && !d_is_md) || d_is_br;
    wire       d_none   = !(d_is_md || d_is_ls || d_is_alu);   // LDI, NOP, JMP, HLT, unused
    wire       d_pred   = d_is_br && (d_imm <= fb_pc);          // BTFN
    wire       d_redir  = d_jump | d_pred;

    // ======================= ROB ============================================
    reg         rob_ready   [0:7];
    reg  [7:0]  rob_pc      [0:7];
    reg  [15:0] rob_instr   [0:7];
    reg         rob_wr_reg  [0:7];
    reg  [1:0]  rob_rd      [0:7];
    reg  [7:0]  rob_val     [0:7];
    reg         rob_wr_flg  [0:7];
    reg  [4:0]  rob_flg     [0:7];
    reg         rob_store   [0:7];
    reg  [7:0]  rob_st_addr [0:7];
    reg  [7:0]  rob_st_data [0:7];
    reg         rob_br      [0:7];
    reg         rob_pred    [0:7];
    reg         rob_taken   [0:7];
    reg         rob_halt    [0:7];
    reg  [2:0]  head, tail;
    reg  [3:0]  count;

    // ======================= RAT (R0-R3, FLAGS = 4) ==========================
    reg         rat_busy [0:4];
    reg  [2:0]  rat_tag  [0:4];

    // ======================= reservation stations ===========================
    // operand A = Rd value, B = Rs value, F = flags (branches only)
    reg         ra_busy [0:3];  reg [2:0] ra_tag [0:3];  reg [4:0] ra_op [0:3];
    reg         ra_ar   [0:3];  reg [7:0] ra_av  [0:3];  reg [2:0] ra_aq [0:3];
    reg         ra_br   [0:3];  reg [7:0] ra_bv  [0:3];  reg [2:0] ra_bq [0:3];
    reg         ra_fr   [0:3];  reg [4:0] ra_fv  [0:3];  reg [2:0] ra_fq [0:3];

    reg         rm_busy [0:1];  reg [2:0] rm_tag [0:1];  reg [4:0] rm_op [0:1];
    reg         rm_ar   [0:1];  reg [7:0] rm_av  [0:1];  reg [2:0] rm_aq [0:1];
    reg         rm_br   [0:1];  reg [7:0] rm_bv  [0:1];  reg [2:0] rm_bq [0:1];

    reg         rl_busy [0:3];  reg [2:0] rl_tag [0:3];  reg [4:0] rl_op [0:3];
    reg         rl_ar   [0:3];  reg [7:0] rl_av  [0:3];  reg [2:0] rl_aq [0:3];
    reg         rl_br   [0:3];  reg [7:0] rl_bv  [0:3];  reg [2:0] rl_bq [0:3];
    reg  [7:0]  rl_imm  [0:3];

    // ======================= functional-unit output registers ===============
    reg         alu_o_v;  reg [2:0] alu_o_tag;  reg [7:0] alu_o_val;
    reg  [4:0]  alu_o_flg; reg alu_o_taken;
    reg         ls_o_v;   reg [2:0] ls_o_tag;   reg [7:0] ls_o_val;
    reg  [7:0]  ls_o_addr; reg [7:0] ls_o_data;

    wire        md_busy, md_done;
    wire [7:0]  md_y;
    wire [4:0]  md_flg;
    wire [2:0]  md_tag;

    // ======================= register file (architectural) ==================
    wire [7:0]  arf_a, arf_b;
    wire        c_fire;                     // commit this cycle
    wire [7:0]  arf_unused_a, arf_unused_b;

    register_file u_rf (
        .clk(clk), .rst(rst), .we(c_fire & rob_wr_reg[head]),
        .waddr(rob_rd[head]), .wdata(rob_val[head]),
        .raddr_a(d_rd), .raddr_b(d_rs),
        .rdata_a(arf_a), .rdata_b(arf_b),
        .regs_flat(regs_flat)
    );

    // age of a ROB tag relative to the head (0 = oldest)
    function [2:0] age;
        input [2:0] t;
        input [2:0] h;
        age = t - h;
    endfunction

    // ======================= CDB arbitration (oldest first) =================
    reg        cdb_v;
    reg [2:0]  cdb_tag;
    reg [7:0]  cdb_val, cdb_addr, cdb_data;
    reg [4:0]  cdb_flg;
    reg        cdb_taken;
    reg        g_alu, g_md, g_ls;

    always @(*) begin
        g_alu = 1'b0; g_md = 1'b0; g_ls = 1'b0;
        if (md_done && (!alu_o_v || age(md_tag, head) < age(alu_o_tag, head))
                    && (!ls_o_v  || age(md_tag, head) < age(ls_o_tag,  head)))
            g_md = 1'b1;
        else if (ls_o_v && (!alu_o_v || age(ls_o_tag, head) < age(alu_o_tag, head)))
            g_ls = 1'b1;
        else if (alu_o_v)
            g_alu = 1'b1;

        cdb_v = g_alu | g_md | g_ls;
        cdb_tag = 3'd0; cdb_val = 8'd0; cdb_flg = 5'd0; cdb_taken = 1'b0;
        cdb_addr = 8'd0; cdb_data = 8'd0;
        if (g_md) begin
            cdb_tag = md_tag; cdb_val = md_y; cdb_flg = md_flg;
        end else if (g_ls) begin
            cdb_tag = ls_o_tag; cdb_val = ls_o_val; cdb_addr = ls_o_addr; cdb_data = ls_o_data;
        end else if (g_alu) begin
            cdb_tag = alu_o_tag; cdb_val = alu_o_val; cdb_flg = alu_o_flg; cdb_taken = alu_o_taken;
        end
    end

    // ======================= dispatch: operand lookup =======================
    reg        sa_r, sb_r, sf_r;
    reg [7:0]  sa_v, sb_v;
    reg [4:0]  sf_v;
    reg [2:0]  sa_q, sb_q, sf_q;

    always @(*) begin
        // A = Rd
        sa_q = rat_tag[d_rd]; sa_v = 8'd0; sa_r = 1'b0;
        if (!d_rd_used)                          begin sa_r = 1'b1; end
        else if (!rat_busy[d_rd])                begin sa_r = 1'b1; sa_v = arf_a; end
        else if (rob_ready[sa_q])                begin sa_r = 1'b1; sa_v = rob_val[sa_q]; end
        else if (cdb_v && cdb_tag == sa_q)       begin sa_r = 1'b1; sa_v = cdb_val; end
        // B = Rs
        sb_q = rat_tag[d_rs]; sb_v = 8'd0; sb_r = 1'b0;
        if (!d_rs_used)                          begin sb_r = 1'b1; end
        else if (!rat_busy[d_rs])                begin sb_r = 1'b1; sb_v = arf_b; end
        else if (rob_ready[sb_q])                begin sb_r = 1'b1; sb_v = rob_val[sb_q]; end
        else if (cdb_v && cdb_tag == sb_q)       begin sb_r = 1'b1; sb_v = cdb_val; end
        // F = FLAGS (branches)
        sf_q = rat_tag[4]; sf_v = 5'd0; sf_r = 1'b0;
        if (!d_is_br)                            begin sf_r = 1'b1; end
        else if (!rat_busy[4])                   begin sf_r = 1'b1; sf_v = aflags; end
        else if (rob_ready[sf_q])                begin sf_r = 1'b1; sf_v = rob_flg[sf_q]; end
        else if (cdb_v && cdb_tag == sf_q)       begin sf_r = 1'b1; sf_v = cdb_flg; end
    end

    // ======================= free RS slots ==================================
    reg       ra_free_v, rm_free_v, rl_free_v;
    reg [1:0] ra_free, rl_free;
    reg       rm_free;
    always @(*) begin
        ra_free_v = 1'b0; ra_free = 2'd0;
        for (i = 3; i >= 0; i = i - 1) if (!ra_busy[i]) begin ra_free_v = 1'b1; ra_free = i; end
        rm_free_v = 1'b0; rm_free = 1'b0;
        for (i = 1; i >= 0; i = i - 1) if (!rm_busy[i]) begin rm_free_v = 1'b1; rm_free = i; end
        rl_free_v = 1'b0; rl_free = 2'd0;
        for (i = 3; i >= 0; i = i - 1) if (!rl_busy[i]) begin rl_free_v = 1'b1; rl_free = i; end
    end

    // ======================= commit =========================================
    wire        c_ok      = (count != 4'd0) && rob_ready[head] && !halted_r;
    assign      c_fire    = en & c_ok;
    wire        c_mispred = rob_br[head] && (rob_taken[head] != rob_pred[head]);
    wire        flush     = c_fire & c_mispred;
    wire [7:0]  c_target  = rob_taken[head] ? rob_instr[head][7:0] : rob_pc[head] + 8'd1;

    // ======================= dispatch =======================================
    wire d_space = d_is_alu ? ra_free_v : d_is_md ? rm_free_v : d_is_ls ? rl_free_v : 1'b1;
    wire d_flag_wait = (FLAG_RENAME == 0) && d_is_br && rat_busy[4];
    wire d_fire  = en && fb_valid && !stop_fetch && !halted_r && !flush &&
                   (count != 4'd8) && d_space && !d_flag_wait;

    // ======================= issue selection (oldest ready) =================
    reg       ra_sel_v, rm_sel_v, rl_sel_v;
    reg [1:0] ra_sel, rl_sel;
    reg       rm_sel;
    reg [2:0] best;
    reg       older_store;
    reg [2:0] e;

    always @(*) begin
        ra_sel_v = 1'b0; ra_sel = 2'd0; best = 3'd7;
        for (i = 0; i < 4; i = i + 1)
            if (ra_busy[i] && ra_ar[i] && ra_br[i] && ra_fr[i] &&
                (!ra_sel_v || age(ra_tag[i], head) < best)) begin
                ra_sel_v = 1'b1; ra_sel = i; best = age(ra_tag[i], head);
            end
        rm_sel_v = 1'b0; rm_sel = 1'b0; best = 3'd7;
        for (i = 0; i < 2; i = i + 1)
            if (rm_busy[i] && rm_ar[i] && rm_br[i] &&
                (!rm_sel_v || age(rm_tag[i], head) < best)) begin
                rm_sel_v = 1'b1; rm_sel = i; best = age(rm_tag[i], head);
            end
        rl_sel_v = 1'b0; rl_sel = 2'd0; best = 3'd7;
        for (i = 0; i < 4; i = i + 1) begin
            // a load waits until every older store has committed
            older_store = 1'b0;
            for (e = 3'd0; e < 3'd7; e = e + 3'd1)   // ages 0..6 below this entry
                if (e < age(rl_tag[i], head) && rob_store[head + e]) older_store = 1'b1;
            if (rl_busy[i] && rl_ar[i] && rl_br[i] &&
                ((rl_op[i] == OP_ST || rl_op[i] == OP_STR) || !older_store) &&
                (!rl_sel_v || age(rl_tag[i], head) < best)) begin
                rl_sel_v = 1'b1; rl_sel = i; best = age(rl_tag[i], head);
            end
        end
    end

    wire alu_issue = ra_sel_v && (!alu_o_v || g_alu) && !flush;
    wire md_issue  = rm_sel_v && !md_busy && !flush;
    wire ls_issue  = rl_sel_v && (!ls_o_v || g_ls) && !flush;

    // ---- ALU unit ----
    wire [4:0] x_op = ra_op[ra_sel];
    wire [7:0] x_y;
    wire       x_zf, x_pf, x_cf, x_of, x_af;
    alu u_alu (
        .a(ra_av[ra_sel]), .b(ra_bv[ra_sel]), .op(x_op[3:0]), .result(x_y),
        .zf(x_zf), .pf(x_pf), .cf(x_cf), .of(x_of), .af(x_af)
    );
    wire x_taken = (x_op == OP_BEQ) ? ra_fv[ra_sel][0] : ~ra_fv[ra_sel][0];

    // ---- MUL/DIV unit ----
    muldiv u_md (
        .clk(clk), .rst(rst), .en(en), .flush(flush),
        .start(md_issue), .is_div(rm_op[rm_sel] == OP_DIV),
        .a(rm_av[rm_sel]), .b(rm_bv[rm_sel]), .tag_in(rm_tag[rm_sel]),
        .ack(g_md & en),
        .busy(md_busy), .done(md_done), .result(md_y), .flags(md_flg), .tag(md_tag)
    );

    // ---- load/store unit ----
    wire [4:0] l_op   = rl_op[rl_sel];
    wire [7:0] l_addr = (l_op == OP_LDR || l_op == OP_STR) ? rl_bv[rl_sel] : rl_imm[rl_sel];
    wire [7:0] l_rdata;

    data_mem u_dmem (
        .clk(clk), .rst(rst), .we(c_fire & rob_store[head]),
        .waddr(rob_st_addr[head]), .wdata(rob_st_data[head]),
        .raddr(l_addr), .rdata(l_rdata),
        .io_in(io_in), .io_out(io_out)
    );

    // ======================= sequential update ==============================
    always @(posedge clk) begin
        if (rst) begin
            pc <= 8'h00; fb_valid <= 1'b0; fb_pc <= 8'h00; fb_instr <= 16'h0000;
            stop_fetch <= 1'b0; halted_r <= 1'b0; aflags <= 5'b00000;
            head <= 3'd0; tail <= 3'd0; count <= 4'd0;
            alu_o_v <= 1'b0; ls_o_v <= 1'b0;
            for (i = 0; i < 5; i = i + 1) begin rat_busy[i] <= 1'b0; rat_tag[i] <= 3'd0; end
            for (i = 0; i < 4; i = i + 1) begin ra_busy[i] <= 1'b0; rl_busy[i] <= 1'b0; end
            for (i = 0; i < 2; i = i + 1) rm_busy[i] <= 1'b0;
            for (i = 0; i < 8; i = i + 1) begin
                rob_ready[i] <= 1'b0; rob_store[i] <= 1'b0; rob_br[i] <= 1'b0;
                rob_halt[i] <= 1'b0; rob_wr_reg[i] <= 1'b0; rob_wr_flg[i] <= 1'b0;
            end
        end else if (en && !halted_r) begin
            // -------------------- commit --------------------
            if (c_fire) begin
                if (rob_wr_flg[head]) aflags <= rob_flg[head];
                if (rob_halt[head])   halted_r <= 1'b1;
                rob_store[head] <= 1'b0;          // no longer an "older store"
                head <= head + 3'd1;
                // free the rename if this entry is still the latest producer
                if (rob_wr_reg[head] && rat_busy[rob_rd[head]] && rat_tag[rob_rd[head]] == head)
                    rat_busy[rob_rd[head]] <= 1'b0;
                if (rob_wr_flg[head] && rat_busy[4] && rat_tag[4] == head)
                    rat_busy[4] <= 1'b0;
            end

            if (flush) begin
                // -------------------- mispredict recovery --------------------
                head <= 3'd0; tail <= 3'd0; count <= 4'd0;
                for (i = 0; i < 8; i = i + 1) begin rob_ready[i] <= 1'b0; rob_store[i] <= 1'b0; end
                for (i = 0; i < 5; i = i + 1) rat_busy[i] <= 1'b0;
                for (i = 0; i < 4; i = i + 1) begin ra_busy[i] <= 1'b0; rl_busy[i] <= 1'b0; end
                for (i = 0; i < 2; i = i + 1) rm_busy[i] <= 1'b0;
                alu_o_v <= 1'b0; ls_o_v <= 1'b0;
                fb_valid <= 1'b0; stop_fetch <= 1'b0;
                pc <= c_target;
            end else begin
                // -------------------- CDB write-back + wakeup --------------------
                if (cdb_v) begin
                    rob_ready[cdb_tag]   <= 1'b1;
                    rob_val[cdb_tag]     <= cdb_val;
                    rob_flg[cdb_tag]     <= cdb_flg;
                    rob_taken[cdb_tag]   <= cdb_taken;
                    rob_st_addr[cdb_tag] <= cdb_addr;
                    rob_st_data[cdb_tag] <= cdb_data;
                    for (i = 0; i < 4; i = i + 1) begin
                        if (ra_busy[i] && !ra_ar[i] && ra_aq[i] == cdb_tag) begin ra_ar[i] <= 1'b1; ra_av[i] <= cdb_val; end
                        if (ra_busy[i] && !ra_br[i] && ra_bq[i] == cdb_tag) begin ra_br[i] <= 1'b1; ra_bv[i] <= cdb_val; end
                        if (ra_busy[i] && !ra_fr[i] && ra_fq[i] == cdb_tag) begin ra_fr[i] <= 1'b1; ra_fv[i] <= cdb_flg; end
                        if (rl_busy[i] && !rl_ar[i] && rl_aq[i] == cdb_tag) begin rl_ar[i] <= 1'b1; rl_av[i] <= cdb_val; end
                        if (rl_busy[i] && !rl_br[i] && rl_bq[i] == cdb_tag) begin rl_br[i] <= 1'b1; rl_bv[i] <= cdb_val; end
                    end
                    for (i = 0; i < 2; i = i + 1) begin
                        if (rm_busy[i] && !rm_ar[i] && rm_aq[i] == cdb_tag) begin rm_ar[i] <= 1'b1; rm_av[i] <= cdb_val; end
                        if (rm_busy[i] && !rm_br[i] && rm_bq[i] == cdb_tag) begin rm_br[i] <= 1'b1; rm_bv[i] <= cdb_val; end
                    end
                end

                // -------------------- issue --------------------
                if (alu_issue) begin
                    ra_busy[ra_sel] <= 1'b0;
                    alu_o_v <= 1'b1; alu_o_tag <= ra_tag[ra_sel];
                    alu_o_val <= x_y; alu_o_flg <= {x_af, x_of, x_cf, x_pf, x_zf};
                    alu_o_taken <= x_taken;
                end else if (g_alu)
                    alu_o_v <= 1'b0;
                if (md_issue)
                    rm_busy[rm_sel] <= 1'b0;
                if (ls_issue) begin
                    rl_busy[rl_sel] <= 1'b0;
                    ls_o_v <= 1'b1; ls_o_tag <= rl_tag[rl_sel];
                    ls_o_val <= l_rdata; ls_o_addr <= l_addr; ls_o_data <= rl_av[rl_sel];
                end else if (g_ls)
                    ls_o_v <= 1'b0;

                // -------------------- dispatch --------------------
                if (d_fire) begin
                    rob_ready[tail]  <= d_none;
                    rob_pc[tail]     <= fb_pc;
                    rob_instr[tail]  <= fb_instr;
                    rob_wr_reg[tail] <= d_reg_write;
                    rob_rd[tail]     <= d_rd;
                    rob_val[tail]    <= d_imm;            // final value for LDI
                    rob_wr_flg[tail] <= d_flag_write;
                    rob_store[tail]  <= d_mem_write;
                    rob_br[tail]     <= d_is_br;
                    rob_pred[tail]   <= d_pred;
                    rob_halt[tail]   <= d_halt;
                    tail <= tail + 3'd1;
                    if (d_reg_write)  begin rat_busy[d_rd] <= 1'b1; rat_tag[d_rd] <= tail; end
                    if (d_flag_write) begin rat_busy[4]    <= 1'b1; rat_tag[4]    <= tail; end
                    if (d_halt) stop_fetch <= 1'b1;

                    if (d_is_alu) begin
                        ra_busy[ra_free] <= 1'b1; ra_tag[ra_free] <= tail; ra_op[ra_free] <= d_op;
                        ra_ar[ra_free] <= sa_r; ra_av[ra_free] <= sa_v; ra_aq[ra_free] <= sa_q;
                        ra_br[ra_free] <= sb_r; ra_bv[ra_free] <= sb_v; ra_bq[ra_free] <= sb_q;
                        ra_fr[ra_free] <= sf_r; ra_fv[ra_free] <= sf_v; ra_fq[ra_free] <= sf_q;
                    end
                    if (d_is_md) begin
                        rm_busy[rm_free] <= 1'b1; rm_tag[rm_free] <= tail; rm_op[rm_free] <= d_op;
                        rm_ar[rm_free] <= sa_r; rm_av[rm_free] <= sa_v; rm_aq[rm_free] <= sa_q;
                        rm_br[rm_free] <= sb_r; rm_bv[rm_free] <= sb_v; rm_bq[rm_free] <= sb_q;
                    end
                    if (d_is_ls) begin
                        rl_busy[rl_free] <= 1'b1; rl_tag[rl_free] <= tail; rl_op[rl_free] <= d_op;
                        rl_ar[rl_free] <= sa_r; rl_av[rl_free] <= sa_v; rl_aq[rl_free] <= sa_q;
                        rl_br[rl_free] <= sb_r; rl_bv[rl_free] <= sb_v; rl_bq[rl_free] <= sb_q;
                        rl_imm[rl_free] <= d_imm;
                    end
                end
                count <= count + {3'd0, d_fire} - {3'd0, c_fire};

                // -------------------- fetch --------------------
                if (d_fire && d_redir) begin
                    fb_valid <= 1'b0;                     // squash, refetch at target
                    pc <= d_imm;
                end else if (d_fire && d_halt) begin
                    fb_valid <= 1'b0;
                end else if ((d_fire || !fb_valid) && !stop_fetch) begin
                    fb_valid <= 1'b1; fb_pc <= pc; fb_instr <= imem_q;
                    pc <= pc + 8'd1;
                end
            end
        end
    end

    // ======================= observation ====================================
    assign {af, of, cf, pf, zf} = aflags;
    assign pc_out       = pc;
    assign retire_valid = c_fire;
    assign retire_pc    = rob_pc[head];
    assign retire_instr = rob_instr[head];
    assign halted       = halted_r | (c_ok & rob_halt[head]);
    assign ex_valid     = (count != 4'd0);
    assign dbg_fwd      = cdb_v;
    assign dbg_flush    = flush;
endmodule
