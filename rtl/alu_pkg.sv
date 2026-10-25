// alu_pkg - opcodes and flag bit positions shared by the RTL, testbench and checkers.
// Always read first; used by fully-qualified name (alu_pkg::OP_ADD).
package alu_pkg;
  localparam int unsigned OP_W = 3;

  localparam logic [OP_W-1:0] OP_ADD  = 3'd0;
  localparam logic [OP_W-1:0] OP_SUB  = 3'd1;
  localparam logic [OP_W-1:0] OP_AND  = 3'd2;
  localparam logic [OP_W-1:0] OP_OR   = 3'd3;
  localparam logic [OP_W-1:0] OP_XOR  = 3'd4;
  localparam logic [OP_W-1:0] OP_SLL  = 3'd5;
  localparam logic [OP_W-1:0] OP_SRL  = 3'd6;
  localparam logic [OP_W-1:0] OP_SLTU = 3'd7;

  // Bit positions in the 4-bit flags word {N, Z, C, V}.
  localparam int unsigned FLAG_N = 3;
  localparam int unsigned FLAG_Z = 2;
  localparam int unsigned FLAG_C = 1;
  localparam int unsigned FLAG_V = 0;
endpackage
