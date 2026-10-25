// alu_fifo_checker - top-level assertions for alu_fifo_top (spec 5.2). Attached by `bind`
// in checker_binds.sv; synthesis never reads this file.
//
// Structure and protocol only: the scoreboard in the testbench checks the ALU's arithmetic,
// and nothing here claims to. Every assertion is wrapped in `ifndef NEUTRALISE_<LABEL>` so
// the mutation run can remove exactly one check at a time.
module alu_fifo_checker #(
  parameter int unsigned W     = 16,
  parameter int unsigned DEPTH = 8
) (
  input logic                     clk,
  input logic                     rst_n,
  // ports of alu_fifo_top
  input logic                     in_valid,
  input logic                     in_ready,
  input logic [alu_pkg::OP_W-1:0] in_op,
  input logic [W-1:0]             in_a,
  input logic [W-1:0]             in_b,
  input logic                     out_valid,
  input logic                     out_ready,
  input logic [W-1:0]             out_y,
  input logic [3:0]               out_flags,
  // internal wires of alu_fifo_top (names are a contract with rtl/alu_fifo_top.sv)
  input logic                     in_push,
  input logic                     in_pop,
  input logic                     in_full,
  input logic                     in_empty,
  input logic                     out_push,
  input logic                     out_pop,
  input logic                     out_full,
  input logic                     out_empty,
  input logic                     xfer,
  input logic [alu_pkg::OP_W-1:0] cmd_op,
  input logic [W-1:0]             cmd_a,
  input logic [W-1:0]             cmd_b,
  input logic [W-1:0]             alu_y,
  input logic                     alu_c,
  input logic                     alu_v
);
  localparam int unsigned CW = $clog2(DEPTH + 1);

  // Conservation bookkeeping: commands accepted and results taken, plus one occupancy model
  // per FIFO built from the handshake wires (the same way sync_fifo_checker builds its cnt).
  logic [31:0]   acc;
  logic [31:0]   tak;
  logic [CW-1:0] in_cnt;
  logic [CW-1:0] out_cnt;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      acc     <= '0;
      tak     <= '0;
      in_cnt  <= '0;
      out_cnt <= '0;
    end else begin
      acc     <= acc + 32'(in_push);
      tak     <= tak + 32'(out_pop);
      in_cnt  <= in_cnt  + CW'(in_push)  - CW'(in_pop);
      out_cnt <= out_cnt + CW'(out_push) - CW'(out_pop);
    end
  end

  // Consecutive-transfer run length, saturating, for the back-to-back bin.
  localparam int unsigned SH_W = $clog2(W);
  logic [3:0] run;
  always_ff @(posedge clk) begin
    if (!rst_n)     run <= '0;
    else if (!xfer) run <= '0;
    else if (run != 4'd15) run <= run + 4'd1;
  end

  // Environment rule on the source: a stalled command is held, unchanged. Catches a bad testbench.
`ifndef NEUTRALISE_A_IN_HOLD
  a_in_hold: assert property (@(posedge clk) disable iff (!rst_n)
    (in_valid && !in_ready) |=> (in_valid && $stable({in_op, in_a, in_b}))
  ) else $error("a_in_hold");
`endif

  // The DUT's own promise on the sink: a stalled result is held, unchanged.
`ifndef NEUTRALISE_A_OUT_HOLD
  a_out_hold: assert property (@(posedge clk) disable iff (!rst_n)
    (out_valid && !out_ready) |=> (out_valid && $stable({out_y, out_flags}))
  ) else $error("a_out_hold");
`endif

`ifndef NEUTRALISE_A_FLAG_Z
  a_flag_z: assert property (@(posedge clk) disable iff (!rst_n)
    out_valid |-> (out_flags[alu_pkg::FLAG_Z] == (out_y == '0))
  ) else $error("a_flag_z");
`endif

`ifndef NEUTRALISE_A_FLAG_N
  a_flag_n: assert property (@(posedge clk) disable iff (!rst_n)
    out_valid |-> (out_flags[alu_pkg::FLAG_N] == out_y[W-1])
  ) else $error("a_flag_n");
`endif

  // Pop and push happen together, and only when there is a command and room for the result.
`ifndef NEUTRALISE_A_LOCKSTEP
  a_lockstep: assert property (@(posedge clk) disable iff (!rst_n)
    (in_pop == out_push) && (!in_pop || (!in_empty && !out_full))
  ) else $error("a_lockstep");
`endif

  // The handshake rules, exactly (spec 4.3). a_lockstep only says a transfer happens ONLY when there is a command and
  // room; these say it happens WHENEVER there is, and that the two sides' ready/valid are nothing but the FIFO flags.
  // Without them a bug that stalls the source or holds results back (half-rate throughput) passes every other check.
`ifndef NEUTRALISE_A_XFER_DEF
  a_xfer_def: assert property (@(posedge clk) disable iff (!rst_n)
    xfer == (!in_empty && !out_full)
  ) else $error("a_xfer_def");
`endif

`ifndef NEUTRALISE_A_READY_DEF
  a_ready_def: assert property (@(posedge clk) disable iff (!rst_n)
    in_ready == !in_full
  ) else $error("a_ready_def");
`endif

`ifndef NEUTRALISE_A_VALID_DEF
  a_valid_def: assert property (@(posedge clk) disable iff (!rst_n)
    out_valid == !out_empty
  ) else $error("a_valid_def");
`endif

  // A pushed result is visible next cycle; a command accepted into an empty pipeline is a
  // result two cycles later. Written as one boolean over $past (no ## in this simulator).
  // Pushes made during a reset cycle are void, so each term is gated by rst_n having been high.
`ifndef NEUTRALISE_A_LATENCY
  a_latency: assert property (@(posedge clk) disable iff (!rst_n)
    (!($past(rst_n) && $past(out_push)) || out_valid) &&
    (!($past(rst_n) && $past(rst_n, 2) && $past(in_push && in_empty && out_empty, 2)) || out_valid)
  ) else $error("a_latency");
`endif

  // The occupancy models are built from the top's handshake wires, so they must also agree
  // with what each FIFO reports (empty / full). That catches a fault that touches only a
  // FIFO instance's pin: the wires say a result was pushed, the FIFO's flags say it was not.
`ifndef NEUTRALISE_A_CONSERVATION
  a_conservation: assert property (@(posedge clk) disable iff (!rst_n)
    ((acc - tak) == (32'(in_cnt) + 32'(out_cnt))) &&
    (in_empty  == (in_cnt  == '0)) && (out_empty == (out_cnt == '0)) &&
    (in_full   == (in_cnt  == CW'(DEPTH))) && (out_full == (out_cnt == CW'(DEPTH)))
  ) else $error("a_conservation");
`endif

  // ---- cover bins: one named statement each (a generate loop would merge them into one name).
  // Operations and results are taken on the cycle the ALU result is pushed (xfer).
  c_op_add:  cover property (@(posedge clk) disable iff (!rst_n) xfer && cmd_op == alu_pkg::OP_ADD);
  c_op_sub:  cover property (@(posedge clk) disable iff (!rst_n) xfer && cmd_op == alu_pkg::OP_SUB);
  c_op_and:  cover property (@(posedge clk) disable iff (!rst_n) xfer && cmd_op == alu_pkg::OP_AND);
  c_op_or:   cover property (@(posedge clk) disable iff (!rst_n) xfer && cmd_op == alu_pkg::OP_OR);
  c_op_xor:  cover property (@(posedge clk) disable iff (!rst_n) xfer && cmd_op == alu_pkg::OP_XOR);
  c_op_sll:  cover property (@(posedge clk) disable iff (!rst_n) xfer && cmd_op == alu_pkg::OP_SLL);
  c_op_srl:  cover property (@(posedge clk) disable iff (!rst_n) xfer && cmd_op == alu_pkg::OP_SRL);
  c_op_sltu: cover property (@(posedge clk) disable iff (!rst_n) xfer && cmd_op == alu_pkg::OP_SLTU);

  c_z_add:   cover property (@(posedge clk) disable iff (!rst_n)
                             xfer && cmd_op == alu_pkg::OP_ADD && alu_y == '0);
  c_z_sub:   cover property (@(posedge clk) disable iff (!rst_n)
                             xfer && cmd_op == alu_pkg::OP_SUB && alu_y == '0);
  c_z_logic: cover property (@(posedge clk) disable iff (!rst_n)
                             xfer && (cmd_op == alu_pkg::OP_AND || cmd_op == alu_pkg::OP_OR ||
                                      cmd_op == alu_pkg::OP_XOR) && alu_y == '0);
  c_n_set:   cover property (@(posedge clk) disable iff (!rst_n) xfer && alu_y[W-1]);
  c_c_add:   cover property (@(posedge clk) disable iff (!rst_n)
                             xfer && cmd_op == alu_pkg::OP_ADD && alu_c);
  c_c_sub_set: cover property (@(posedge clk) disable iff (!rst_n)
                               xfer && cmd_op == alu_pkg::OP_SUB && alu_c);
  c_c_sub_clr: cover property (@(posedge clk) disable iff (!rst_n)
                               xfer && cmd_op == alu_pkg::OP_SUB && !alu_c);
  c_v_add:   cover property (@(posedge clk) disable iff (!rst_n)
                             xfer && cmd_op == alu_pkg::OP_ADD && alu_v);
  c_v_sub:   cover property (@(posedge clk) disable iff (!rst_n)
                             xfer && cmd_op == alu_pkg::OP_SUB && alu_v);

  c_shamt_0:   cover property (@(posedge clk) disable iff (!rst_n)
                               xfer && (cmd_op == alu_pkg::OP_SLL || cmd_op == alu_pkg::OP_SRL) &&
                               cmd_b[SH_W-1:0] == '0);
  c_shamt_max: cover property (@(posedge clk) disable iff (!rst_n)
                               xfer && (cmd_op == alu_pkg::OP_SLL || cmd_op == alu_pkg::OP_SRL) &&
                               cmd_b[SH_W-1:0] == SH_W'(W - 1));
  c_sltu_true:  cover property (@(posedge clk) disable iff (!rst_n)
                                xfer && cmd_op == alu_pkg::OP_SLTU && alu_y[0]);
  c_sltu_false: cover property (@(posedge clk) disable iff (!rst_n)
                                xfer && cmd_op == alu_pkg::OP_SLTU && !alu_y[0]);

  c_src_stall: cover property (@(posedge clk) disable iff (!rst_n) in_valid && !in_ready);
  c_snk_stall: cover property (@(posedge clk) disable iff (!rst_n) out_valid && !out_ready);
  c_b2b_8:     cover property (@(posedge clk) disable iff (!rst_n) run == 4'd8);
endmodule
