// Fixture: a generic gate left in the netlist (not a library cell). Must be stopped by all-mapped.
module top (input a, input b, output y);
  assign y = a & b;
endmodule
