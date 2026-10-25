// alu_fifo_top - input FIFO -> combinational ALU -> output FIFO (spec 4).
// One transfer per cycle whenever the input FIFO has a command and the output FIFO has room.
//
// The internal wire names below (in_push ... xfer, cmd_*, alu_*) are bound by the
// checkers in verif/ with `.*`; renaming one breaks the bind.
module alu_fifo_top #(
  parameter int unsigned W     = 16,
  parameter int unsigned DEPTH = 8
) (
  input  logic                     clk,
  input  logic                     rst_n,
  // source side
  input  logic                     in_valid,
  output logic                     in_ready,
  input  logic [alu_pkg::OP_W-1:0] in_op,
  input  logic [W-1:0]             in_a,
  input  logic [W-1:0]             in_b,
  // sink side
  output logic                     out_valid,
  input  logic                     out_ready,
  output logic [W-1:0]             out_y,
  output logic [3:0]               out_flags   // {N, Z, C, V}
);
  localparam int unsigned IN_W  = alu_pkg::OP_W + 2 * W;
  localparam int unsigned OUT_W = 4 + W;

  // FIFO handshakes
  logic in_push, in_pop, in_full, in_empty;
  logic out_push, out_pop, out_full, out_empty;
  logic xfer;

  logic [IN_W-1:0]  in_fifo_din;
  logic [IN_W-1:0]  in_fifo_dout;
  logic [OUT_W-1:0] out_fifo_din;
  logic [OUT_W-1:0] out_fifo_dout;

  // ALU operands (input FIFO head) and result
  logic [alu_pkg::OP_W-1:0] cmd_op;
  logic [W-1:0]             cmd_a;
  logic [W-1:0]             cmd_b;
  logic [W-1:0]             alu_y;
  logic                     alu_c;
  logic                     alu_v;
  logic [3:0]               res_flags;

  // source side: accept while the input FIFO has room
  assign in_fifo_din = {in_op, in_a, in_b};
  assign in_ready    = !in_full;
  assign in_push     = in_valid && in_ready;

  // transfer rule (spec 4.3)
  assign xfer     = !in_empty && !out_full;
  assign in_pop   = xfer;
  assign out_push = xfer;

  assign {cmd_op, cmd_a, cmd_b} = in_fifo_dout;

  alu #(.W(W)) u_alu (
    .op(cmd_op), .a(cmd_a), .b(cmd_b), .y(alu_y), .c(alu_c), .v(alu_v)
  );

  assign res_flags[alu_pkg::FLAG_N] = alu_y[W-1];
  assign res_flags[alu_pkg::FLAG_Z] = (alu_y == '0);
  assign res_flags[alu_pkg::FLAG_C] = alu_c;
  assign res_flags[alu_pkg::FLAG_V] = alu_v;
  assign out_fifo_din = {res_flags, alu_y};

  // sink side
  assign out_valid = !out_empty;
  assign out_pop   = out_valid && out_ready;
  assign {out_flags, out_y} = out_fifo_dout;

  sync_fifo #(.WIDTH(IN_W), .DEPTH(DEPTH)) u_in_fifo (
    .clk, .rst_n,
    .push(in_push), .din(in_fifo_din), .pop(in_pop), .dout(in_fifo_dout),
    .full(in_full), .empty(in_empty)
  );

  sync_fifo #(.WIDTH(OUT_W), .DEPTH(DEPTH)) u_out_fifo (
    .clk, .rst_n,
    .push(out_push), .din(out_fifo_din), .pop(out_pop), .dout(out_fifo_dout),
    .full(out_full), .empty(out_empty)
  );
endmodule
