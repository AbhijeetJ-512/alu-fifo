// Fixture: a valid mapped netlist. Must pass netlist_check.ys.
module top (input a, input b, output y);
  sky130_fd_sc_hd__and2_1 u0 (.A(a), .B(b), .X(y));
endmodule
