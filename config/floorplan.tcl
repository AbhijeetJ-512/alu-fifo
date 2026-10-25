# config/floorplan.tcl - design names and floorplan size for alu_fifo_top.
# The die is sized from the netlist's cell area by utilisation (replacing Full-Adder's fixed 13x13 um die).

set design        "alu_fifo"
set top_module    "alu_fifo_top"
set synth_verilog "build/synth.v"

# Percent of the core area filled with standard cells (make CORE_UTILIZATION=40 exports it).
if {[info exists ::env(CORE_UTILIZATION)]} { set core_utilization $::env(CORE_UTILIZATION) } else { set core_utilization 40 }
set core_aspect_ratio 1
set core_space        5  ;# microns between core and die edge
