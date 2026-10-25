// Fixture netlist: only its port declarations matter to check_sdc.py.
module tiny (clk, rst_n, a, y);
  input clk;
  input rst_n;
  input [1:0] a;
  output y;
endmodule
