// Fixture: a tri-state driver. Must be stopped by the no-tribuf check.
module tribuf_top (input logic en, input logic d, output tri y);
  assign y = en ? d : 1'bz;
endmodule
