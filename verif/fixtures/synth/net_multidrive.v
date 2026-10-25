// Fixture: two cell outputs on one net. Must be stopped by check-assert.
module top (input a, input b, output y);
  sky130_fd_sc_hd__and2_1 u0 (.A(a), .B(b), .X(y));
  sky130_fd_sc_hd__and2_1 u1 (.A(a), .B(b), .X(y));
endmodule
