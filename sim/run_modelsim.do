# ModelSim / ModelSim-Altera: run all self-checking testbenches.
#   GUI:   cd to sim/, then in the transcript:  do run_modelsim.do
#   Batch: vsim -c -do run_modelsim.do
# Working directory must be sim/ so "../mem/program.hex" resolves.

if {[file exists work]} { vdel -lib work -all }
vlib work
set RTL {../rtl/alu.v ../rtl/muldiv.v ../rtl/decoder.v ../rtl/register_file.v ../rtl/instr_rom.v
         ../rtl/data_mem.v ../rtl/processor.v ../rtl/processor_pipe.v ../rtl/processor_ooo.v}

# 1) exhaustive ALU check (~1M vectors)
vlog -work work +incdir+../tb ../rtl/alu.v ../tb/tb_alu.v
vsim -c work.tb_alu
run -all
quit -sim

# 2) single-cycle core vs reference model
vlog -work work +incdir+../tb {*}$RTL ../tb/tb_cpu.v
vsim -c work.tb_cpu
run -all
quit -sim

# 3) pipelined core vs reference model (same testbench, +define+PIPE)
vlog -work work +incdir+../tb +define+PIPE {*}$RTL ../tb/tb_cpu.v
vsim -c work.tb_cpu
run -all
quit -sim

# 3b) out-of-order core vs reference model (+define+OOO)
vlog -work work +incdir+../tb +define+OOO {*}$RTL ../tb/tb_cpu.v
vsim -c work.tb_cpu
run -all
quit -sim

# 3c) MUL/DIV unit (exhaustive) and CPI benchmark of all three cores
vlog -work work +incdir+../tb ../rtl/muldiv.v ../tb/tb_muldiv.v
vsim -c work.tb_muldiv
run -all
quit -sim
vlog -work work +incdir+../tb {*}$RTL ../tb/tb_bench.v
vsim -c work.tb_bench
run -all
quit -sim

# 4) board wrapper
vlog -work work {*}$RTL ../board/seg7_hex.v ../board/de2_top.v ../tb/tb_de2_top.v
vsim -c work.tb_de2_top
run -all
quit -sim

# 5) waveforms: pipelined core running the demo program
#    (for the out-of-order core use +define+OOO and add /tb_cpu/dut/head, tail,
#     count, cdb_v, cdb_tag, flush)
vlog -work work +incdir+../tb +define+PIPE {*}$RTL ../tb/tb_cpu.v
vsim work.tb_cpu
add wave -radix hex /tb_cpu/clk /tb_cpu/en /tb_cpu/dut/pc_f
add wave -radix hex /tb_cpu/dut/valid_d /tb_cpu/dut/pc_d /tb_cpu/dut/instr_d
add wave -radix hex /tb_cpu/dut/valid_e /tb_cpu/dut/pc_e /tb_cpu/dut/instr_e
add wave /tb_cpu/dut/fwd_a /tb_cpu/dut/fwd_b /tb_cpu/dut/flush_d /tb_cpu/dut/flush_e
add wave -radix hex /tb_cpu/regs_flat /tb_cpu/io_out
run 2us
