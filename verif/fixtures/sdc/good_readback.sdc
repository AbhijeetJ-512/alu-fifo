###############################################################################
# Created by write_sdc
###############################################################################
current_design tiny
###############################################################################
# Timing Constraints
###############################################################################
create_clock -name clk -period 10.0000 [get_ports {clk}]
set_input_delay 2.0000 -clock [get_clocks {clk}] -add_delay [get_ports {rst_n}]
set_input_delay 2.0000 -clock [get_clocks {clk}] -add_delay [get_ports {a[0]}]
set_input_delay 2.0000 -clock [get_clocks {clk}] -add_delay [get_ports {a[1]}]
set_output_delay 2.0000 -clock [get_clocks {clk}] -add_delay [get_ports {y}]
###############################################################################
# Environment
###############################################################################
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_2 -pin {X} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {rst_n}]
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_2 -pin {X} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {a[0]}]
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_2 -pin {X} -input_transition_rise 0.0000 -input_transition_fall 0.0000 [get_ports {a[1]}]
set_load -pin_load 0.0100 [get_ports {y}]
