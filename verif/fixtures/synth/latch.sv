// Fixture: an inferred latch. Must be stopped by the no-latch check.
module latch_top (input logic en, input logic d, output logic q);
  always_latch if (en) q = d;
endmodule
