// sync_fifo_checker - black-box assertions for sync_fifo (spec 5.2). Attached by `bind`
// in checker_binds.sv; synthesis never reads this file.
//
// It never looks at the RTL's pointers. It keeps its own occupancy count `cnt` from the
// FIFO's ports, so a bug in the pointer logic cannot also change the checker's reference.
// Every assertion is wrapped in `ifndef NEUTRALISE_<LABEL>` so the mutation run can remove
// exactly one check at a time (scripts/mutants.py passes -DNEUTRALISE_<LABEL>).
module sync_fifo_checker #(
  parameter int unsigned WIDTH = 8,
  parameter int unsigned DEPTH = 8
) (
  input logic             clk,
  input logic             rst_n,
  input logic             push,
  input logic [WIDTH-1:0] din,
  input logic             pop,
  input logic [WIDTH-1:0] dout,
  input logic             full,
  input logic             empty
);
  localparam int unsigned CW = $clog2(DEPTH + 1);
  localparam logic [CW-1:0] DEPTH_C = CW'(DEPTH);

  // Reference occupancy: a push counts only below DEPTH, a pop only above 0.
  logic [CW-1:0] cnt;
  always_ff @(posedge clk) begin
    if (!rst_n) cnt <= '0;
    else        cnt <= cnt + CW'(push && (cnt < DEPTH_C)) - CW'(pop && (cnt > '0));
  end

  // The checker's own write and read index models (mod DEPTH), for the wrap bins.
  localparam int unsigned IW = $clog2(DEPTH);
  logic acc_push;
  logic acc_pop;
  logic [IW-1:0] wr_idx;
  logic [IW-1:0] rd_idx;
  assign acc_push = push && (cnt < DEPTH_C);
  assign acc_pop  = pop && (cnt > '0);
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wr_idx <= '0;
      rd_idx <= '0;
    end else begin
      if (acc_push) wr_idx <= wr_idx + IW'(1);
      if (acc_pop)  rd_idx <= rd_idx + IW'(1);
    end
  end

`ifndef NEUTRALISE_A_NOT_FULL_AND_EMPTY
  a_not_full_and_empty: assert property (@(posedge clk) disable iff (!rst_n)
    !(full && empty)
  ) else $error("a_not_full_and_empty");
`endif

`ifndef NEUTRALISE_A_FULL_DEF
  a_full_def: assert property (@(posedge clk) disable iff (!rst_n)
    full == (cnt == DEPTH_C)
  ) else $error("a_full_def");
`endif

`ifndef NEUTRALISE_A_EMPTY_DEF
  a_empty_def: assert property (@(posedge clk) disable iff (!rst_n)
    empty == (cnt == '0)
  ) else $error("a_empty_def");
`endif

`ifndef NEUTRALISE_A_HEAD_STABLE
  a_head_stable: assert property (@(posedge clk) disable iff (!rst_n)
    (!empty && !pop) |=> (dout == $past(dout))
  ) else $error("a_head_stable");
`endif

  // No disable iff: reset itself is what is being checked.
  // The simulator lowers |=> to a delay register that --x-initial unique starts random, so at
  // the very first clock edge the check could fire on a stale antecedent. started is 0 only
  // then, which makes the consequent vacuously true for that one edge and for no other.
  logic started;
  always_ff @(posedge clk) started <= 1'b1;
  initial started = 1'b0;

`ifndef NEUTRALISE_A_RESET_EMPTY
  a_reset_empty: assert property (@(posedge clk)
    !rst_n |=> (!started || (empty && !full))
  ) else $error("a_reset_empty");
`endif

  // ---- cover bins (one named statement each; per FIFO instance) ----
  c_full:     cover property (@(posedge clk) disable iff (!rst_n) cnt == DEPTH_C);
  c_empty:    cover property (@(posedge clk) disable iff (!rst_n) pop && (cnt == CW'(1)));
  c_push_pop: cover property (@(posedge clk) disable iff (!rst_n)
                              push && pop && (cnt > '0) && (cnt < DEPTH_C));
  c_wrap_wr:  cover property (@(posedge clk) disable iff (!rst_n) acc_push && (wr_idx == IW'(DEPTH - 1)));
  c_wrap_rd:  cover property (@(posedge clk) disable iff (!rst_n) acc_pop && (rd_idx == IW'(DEPTH - 1)));
endmodule
