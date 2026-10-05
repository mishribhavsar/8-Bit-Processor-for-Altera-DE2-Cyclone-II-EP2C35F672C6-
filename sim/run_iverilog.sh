#!/usr/bin/env bash
# Run both self-checking testbenches with Icarus Verilog (run from sim/).
set -e
cd "$(dirname "$0")"
RTL="../rtl/alu.v ../rtl/control_unit.v ../rtl/register_file.v ../rtl/pc.v ../rtl/instr_rom.v ../rtl/processor.v"

iverilog -g2005 -Wall -I../tb -o tb_alu.vvp       $RTL ../tb/tb_alu.v
vvp -n tb_alu.vvp

iverilog -g2005 -Wall -I../tb -o tb_processor.vvp $RTL ../tb/tb_processor.v
vvp -n tb_processor.vvp

iverilog -g2005 -Wall -o tb_de2_top.vvp $RTL ../board/seg7_hex.v ../board/de2_top.v ../tb/tb_de2_top.v
vvp -n tb_de2_top.vvp
