// Fixture: violates exactly R-ALWAYS (always @* instead of always_comb).
module bad_always (input logic a, output logic y);
  always @* y = a;
endmodule
