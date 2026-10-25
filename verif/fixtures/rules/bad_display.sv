// Fixture: violates exactly R-DISPLAY (a system task in RTL).
module bad_display (input logic clk);
  always_ff @(posedge clk) $display("x");
endmodule
