// Fixture: violates exactly R-TRISTATE (a high-impedance drive).
module bad_tristate (input logic a, input logic en, output tri y);
  assign y = en ? a : 1'bz;
endmodule
