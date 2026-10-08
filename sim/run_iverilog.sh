#!/usr/bin/env bash
# Run all self-checking testbenches and the CPI benchmark with Icarus Verilog.
set -e
cd "$(dirname "$0")"
RTL="../rtl/ALU.v ../rtl/pc.v ../rtl/muldiv.v ../rtl/Controlunit.v ../rtl/Register.v ../rtl/memory.v ../rtl/data_mem.v ../rtl/processor.v ../rtl/processor_pipe.v ../rtl/processor_ooo.v"
IV="iverilog -g2005 -I../tb"

$IV -o tb_alu.vvp ../rtl/ALU.v ../tb/tb_alu.v                && vvp -n tb_alu.vvp
$IV -o tb_muldiv.vvp ../rtl/muldiv.v ../tb/tb_muldiv.v       && vvp -n tb_muldiv.vvp
$IV -o tb_cpu_single.vvp       $RTL ../tb/tb_cpu.v           && vvp -n tb_cpu_single.vvp
$IV -o tb_cpu_pipe.vvp   -DPIPE $RTL ../tb/tb_cpu.v          && vvp -n tb_cpu_pipe.vvp
$IV -o tb_cpu_ooo.vvp    -DOOO  $RTL ../tb/tb_cpu.v          && vvp -n tb_cpu_ooo.vvp
$IV -o tb_bench.vvp            $RTL ../tb/tb_bench.v         && vvp -n tb_bench.vvp
$IV -o tb_bench_nofr.vvp -DNO_FLAG_RENAME $RTL ../tb/tb_bench.v && vvp -n tb_bench_nofr.vvp
$IV -o tb_de2_top.vvp $RTL ../board/seg7_hex.v ../board/de2_top.v ../tb/tb_de2_top.v && vvp -n tb_de2_top.vvp
rm -f *.vvp
