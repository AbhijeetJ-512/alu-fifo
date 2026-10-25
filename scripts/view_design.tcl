# view_design.tcl - Load final routed design (new results dir pnr_results)
source sky130hd/sky130hd.vars

read_lef $tech_lef
read_lef $std_cell_lef
foreach lef $extra_lef { read_lef $lef }

set final_def "pnr_results/alu_fifo_sky130hd_final-tcl.def"
set routed_def "pnr_results/alu_fifo_sky130hd_route-tcl.def"
if {[file exists $final_def]} {
  puts "Loading final DEF: $final_def"
  read_def $final_def
} elseif {[file exists $routed_def]} {
  puts "Final DEF missing, loading routed DEF: $routed_def"
  read_def $routed_def
} else {
  puts stderr "No DEF found (expected $final_def or $routed_def). Run make pnr first."
  return
}
after 1000 { gui::fit }
