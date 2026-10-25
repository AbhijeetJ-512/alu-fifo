# sta.tcl - OpenSTA on the synthesised netlist (spec 6.4).
# Usage: CLK_PERIOD_NS=10.0 sta -no_splash -exit scripts/sta.tcl     (the Makefile sets the environment)
# Pre-layout: ideal clock, no wire parasitics. Typical-corner library.
# Writes: build/reports/sdc_readback.sdc  (what OpenSTA loaded; scripts/check_sdc.py checks it)
#         build/reports/timing.txt, build/reports/power_report.txt

read_liberty sky130hd/sky130hd_tt.lib
read_verilog build/synth.v
link_design alu_fifo_top

if {[info exists ::env(SDC_FILE)]} { set sdc $::env(SDC_FILE) } else { set sdc constraints/alu_fifo.sdc }
read_sdc $sdc
write_sdc -no_timestamp build/reports/sdc_readback.sdc

set hdr "Post-synthesis static timing, ideal clock, no wire parasitics (pre-layout). Library: sky130_fd_sc_hd__tt_025C_1v80. SDC: $sdc"

set f [open build/reports/timing.txt w]
puts $f "# $hdr"
puts $f "# clock period (from the loaded design): [get_property [get_clocks clk] period] ns"
close $f
report_checks -path_delay max -digits 3 >> build/reports/timing.txt
report_checks -path_delay min -digits 3 >> build/reports/timing.txt
report_worst_slack -max -digits 3 >> build/reports/timing.txt
report_worst_slack -min -digits 3 >> build/reports/timing.txt
report_tns -digits 3 >> build/reports/timing.txt

set f [open build/reports/power_report.txt w]
puts $f "# $hdr"
puts $f "# switching activity: OpenSTA defaults (no VCD/SAIF supplied), so this is not a measured workload"
close $f
report_power >> build/reports/power_report.txt

exit
