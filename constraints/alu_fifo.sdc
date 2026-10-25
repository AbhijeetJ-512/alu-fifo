# alu_fifo.sdc - timing constraints for alu_fifo_top (spec 6.3, decision D-011).
# The clock period is NOT written here: it comes from the Makefile's CLK_PERIOD_NS (the one source,
# also given to Yosys abc -D) through the environment. Input and output delays are 20% of the period
# on every non-clock port; the driving cell and the output load are assumptions about the surrounding
# system, not results. scripts/check_sdc.py verifies all of this against what OpenSTA actually loaded.
set period $::env(CLK_PERIOD_NS)
set io_delay [expr {0.2 * $period}]

create_clock -name clk -period $period [get_ports clk]

set data_inputs {}
foreach port [all_inputs] {
  if {[get_property $port name] ne "clk"} { lappend data_inputs $port }
}

set_input_delay  $io_delay -clock clk $data_inputs
set_output_delay $io_delay -clock clk [all_outputs]
set_driving_cell -lib_cell sky130_fd_sc_hd__buf_2 -pin X $data_inputs
set_load 0.01 [all_outputs]
