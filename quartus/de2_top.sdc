# de2_top.sdc -- timing constraints (TimeQuest)

create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_clock_uncertainty

# The core only updates when step_en is high, and step_en pulses at most once
# every 1 ms (step) or 0.5 s (run). Core-to-core paths therefore get several
# clock periods; this lets the combinational 8-bit divider/multiplier in the
# single-cycle datapath meet timing at 50 MHz without a slower clock.
set_multicycle_path -setup 4 -from [get_registers {processor:u_core|*}] -to [get_registers {processor:u_core|*}]
set_multicycle_path -hold  3 -from [get_registers {processor:u_core|*}] -to [get_registers {processor:u_core|*}]

# Asynchronous human inputs and slow visual outputs
set_false_path -from [get_ports {KEY[*] SW[*]}]
set_false_path -to   [get_ports {LEDG[*] LEDR[*] HEX*}]
