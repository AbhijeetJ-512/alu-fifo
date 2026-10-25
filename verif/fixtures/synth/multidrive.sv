// Fixture: one net with two drivers. Must be stopped by check-rtl.
module multidrive_top (input logic a, input logic b, output wire y);
  assign y = a;
  assign y = b;
endmodule
