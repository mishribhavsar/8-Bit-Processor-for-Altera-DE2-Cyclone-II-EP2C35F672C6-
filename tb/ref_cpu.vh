// -----------------------------------------------------------------------------
// ref_cpu.vh  --  instruction-level reference model of the ISA (testbench only)
//   Include after ref_model.vh. Executes one instruction per call to
//   model_step, written straight from the ISA table (no pipeline, no RTL).
// -----------------------------------------------------------------------------
reg [15:0] m_rom [0:255];      // program
reg [7:0]  m_mem [0:255];      // data memory (0xFE/0xFF are I/O, see below)
reg [7:0]  m_r   [0:3];
reg [7:0]  m_pc;
reg [4:0]  m_flags;            // {AF, OF, CF, PF, ZF}
reg [7:0]  m_out;
reg [7:0]  m_last_st_addr;     // address of the most recent store (for checks)
reg        m_last_was_st;

task model_reset;
    integer k;
    begin
        m_pc = 0; m_flags = 0; m_out = 0;
        for (k = 0; k < 4; k = k + 1)   m_r[k]   = 0;
        for (k = 0; k < 256; k = k + 1) m_mem[k] = 0;
        m_last_was_st = 0;
    end
endtask

function [7:0] model_load;
    input [7:0] addr;
    input [7:0] io_in;
    begin
        if      (addr == 8'hFF) model_load = io_in;
        else if (addr == 8'hFE) model_load = m_out;
        else                    model_load = m_mem[addr];
    end
endfunction

task model_store;
    input [7:0] addr;
    input [7:0] data;
    begin
        if      (addr == 8'hFE) m_out = data;
        else if (addr != 8'hFF) m_mem[addr] = data;
        m_last_was_st = 1; m_last_st_addr = addr;
    end
endtask

task model_step;
    input [7:0] io_in;
    reg [15:0] ir;
    reg [4:0]  op;
    reg [1:0]  d, s;
    reg [7:0]  imm;
    reg [12:0] r;
    begin
        ir  = m_rom[m_pc];
        op  = ir[15:11]; d = ir[10:9]; s = ir[8:7]; imm = ir[7:0];
        m_last_was_st = 0;
        if (op <= 5'h0E) begin                       // ALU group
            r = ref_alu(op[3:0], m_r[d], m_r[s]);
            m_flags = r[12:8];
            if (op != 5'h06) m_r[d] = r[7:0];        // CMP: flags only
            m_pc = m_pc + 1;
        end else begin
            case (op)
                5'h10: begin m_r[d] = imm;                        m_pc = m_pc + 1; end // LDI
                5'h11: begin m_r[d] = model_load(imm, io_in);     m_pc = m_pc + 1; end // LD
                5'h12: begin model_store(imm, m_r[d]);            m_pc = m_pc + 1; end // ST
                5'h13: begin m_r[d] = model_load(m_r[s], io_in);  m_pc = m_pc + 1; end // LDR
                5'h14: begin model_store(m_r[s], m_r[d]);         m_pc = m_pc + 1; end // STR
                5'h15: m_pc = imm;                                                     // JMP
                5'h16: m_pc = m_flags[0] ? imm : m_pc + 1;                             // BEQ
                5'h17: m_pc = m_flags[0] ? m_pc + 1 : imm;                             // BNE
                5'h18: m_pc = m_pc;                                                    // HLT
                default: m_pc = m_pc + 1;                                              // NOP / unused
            endcase
        end
    end
endtask
