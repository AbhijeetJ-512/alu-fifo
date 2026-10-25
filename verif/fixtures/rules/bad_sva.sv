// Fixture: violates exactly R-SVA (an assertion in RTL; they belong in verif/).
module bad_sva (input logic clk, input logic a);
  assert property (@(posedge clk) a);
endmodule
