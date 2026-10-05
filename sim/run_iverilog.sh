#!/usr/bin/env bash
# Run all self-checking testbenches with Icarus Verilog (run from anywhere).
set -e
cd "$(dirname "$0")"
RTL="../rtl/alu.v ../rtl/decoder.v ../rtl/register_file.v ../rtl/instr_rom.v ../rtl/data_mem.v ../rtl/processor.v ../rtl/processor_pipe.v"

iverilog -g2005 -Wall -I../tb -o tb_alu.vvp ../rtl/alu.v ../tb/tb_alu.v
vvp -n tb_alu.vvp

iverilog -g2005 -Wall -I../tb -o tb_cpu_single.vvp $RTL ../tb/tb_cpu.v
vvp -n tb_cpu_single.vvp

iverilog -g2005 -Wall -I../tb -DPIPE -o tb_cpu_pipe.vvp $RTL ../tb/tb_cpu.v
vvp -n tb_cpu_pipe.vvp

iverilog -g2005 -Wall -o tb_de2_top.vvp $RTL ../board/seg7_hex.v ../board/de2_top.v ../tb/tb_de2_top.v
vvp -n tb_de2_top.vvp
