# ModelSim / ModelSim-Altera: run both self-checking testbenches.
#   GUI:   cd to sim/, then in the transcript:  do run_modelsim.do
#   Batch: vsim -c -do run_modelsim.do
# Working directory must be sim/ so "../mem/program.hex" resolves.

if {[file exists work]} { vdel -lib work -all }
vlib work

vlog -work work ../rtl/alu.v ../rtl/control_unit.v ../rtl/register_file.v \
                ../rtl/pc.v ../rtl/instr_rom.v ../rtl/processor.v
vlog -work work ../board/seg7_hex.v ../board/de2_top.v
vlog -work work +incdir+../tb ../tb/tb_alu.v ../tb/tb_processor.v ../tb/tb_de2_top.v

# 1) exhaustive ALU check (~1M vectors)
vsim -c work.tb_alu
run -all
quit -sim

# 2) board wrapper smoke test (step mode, reads the 7-seg displays back)
vsim -c work.tb_de2_top
run -all
quit -sim

# 3) processor: demo trace + random programs
vsim work.tb_processor
add wave -radix hex /tb_processor/clk /tb_processor/rst /tb_processor/en
add wave -radix hex /tb_processor/pc_out /tb_processor/instr /tb_processor/alu_result
add wave -radix hex /tb_processor/dut/u_rf/r0 /tb_processor/dut/u_rf/r1 \
                    /tb_processor/dut/u_rf/r2 /tb_processor/dut/u_rf/r3
add wave /tb_processor/zf /tb_processor/pf /tb_processor/cf /tb_processor/of /tb_processor/af
run -all
