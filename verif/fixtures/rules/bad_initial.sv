// Fixture: violates exactly R-INITIAL (an initial block in RTL).
module bad_initial (output logic q);
  initial q = 1'b0;
endmodule
