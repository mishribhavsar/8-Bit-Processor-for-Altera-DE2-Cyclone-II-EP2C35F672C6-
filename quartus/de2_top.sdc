# de2_top.sdc -- timing constraints (TimeQuest)

create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_clock_uncertainty

# All cores only change state when step_en is high, and step_en pulses at
# most once every 1 ms (step mode) or 0.5 s (run mode). Paths inside each core
# therefore get several clock periods, which lets the combinational 8-bit
# multiplier/divider in the datapath meet timing at 50 MHz.
set cores [get_registers {processor:u_sc|* processor_pipe:u_pl|* processor_ooo:u_oo|*}]
set_multicycle_path -setup 4 -from $cores -to $cores
set_multicycle_path -hold  3 -from $cores -to $cores

# Asynchronous human inputs and slow visual outputs
set_false_path -from [get_ports {KEY[*] SW[*]}]
set_false_path -to   [get_ports {LEDG[*] LEDR[*] HEX*}]
