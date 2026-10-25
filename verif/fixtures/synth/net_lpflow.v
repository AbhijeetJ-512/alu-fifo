// Fixture: a low-power-flow cell. Must be stopped by no-lpflow.
module top (input a, input b, output y);
  sky130_fd_sc_hd__lpflow_inputiso1p_1 u0 (.A(a), .SLEEP(b), .X(y));
endmodule
