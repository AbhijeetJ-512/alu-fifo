// Fixture: a net that is read but never driven. Must be stopped by check-rtl
// (after synth it would already have become a constant, so a later check cannot see it).
module undriven_top (input logic a, output logic y);
  logic u;
  assign y = a & u;
endmodule
