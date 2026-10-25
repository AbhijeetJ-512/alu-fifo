// tb_alu_fifo - self-checking testbench for alu_fifo_top (spec 5.1).
//
// Source drives {op,a,b} with valid/ready; sink drains {flags,y}. A queue of expected
// words (from ref_alu, an independent model) is compared on every output transfer.
// ref_alu itself is checked against a hand-derived known-answer table before any stimulus.
module tb_alu_fifo;
  localparam int unsigned W = 16;
  parameter  int unsigned DEPTH = 8;  // -GDEPTH=<n> from the Makefile

  // ---- DUT -----------------------------------------------------------------
  logic                     clk       = 1'b0;
  logic                     rst_n     = 1'b0;
  logic                     in_valid  = 1'b0;
  logic                     in_ready;
  logic [alu_pkg::OP_W-1:0] in_op     = '0;
  logic [W-1:0]             in_a      = '0;
  logic [W-1:0]             in_b      = '0;
  logic                     out_valid;
  logic                     out_ready = 1'b0;
  logic [W-1:0]             out_y;
  logic [3:0]               out_flags;

  alu_fifo_top #(.W(W), .DEPTH(DEPTH)) dut (.*);

  always #5 clk = ~clk;

  // ---- bookkeeping ---------------------------------------------------------
  typedef struct packed {
    logic [2:0]   op;
    logic [W-1:0] a;
    logic [W-1:0] b;
  } cmd_t;

  cmd_t         src_q [$];  // commands not yet accepted by the DUT (head is on the bus)
  logic [W+3:0] exp_q [$];  // expected {flags, y}, in command order

  bit           seen_cmd [cmd_t];  // distinct {op,a,b} offered, for the TB STATS line

  int unsigned total_cmds = 0;
  int unsigned accepted   = 0;
  int unsigned delivered  = 0;
  int unsigned distinct   = 0;
  int unsigned ncmd;
  int          p_src      = 100;  // percent of cycles the source offers a command
  int          p_snk      = 100;  // percent of cycles the sink is ready
  logic [31:0] seed_u;
  logic [31:0] rng;
  logic        accepted_last = 1'b0;
  bit          tb_failed     = 1'b0;  // sticky: PASS is never printed after any failure

  // xorshift32; the state is never allowed to be zero (it would stick at zero).
  function automatic logic [31:0] rnd();
    rng = rng ^ (rng << 13);
    rng = rng ^ (rng >> 17);
    rng = rng ^ (rng << 5);
    return rng;
  endfunction

  // $fatal aborts the run by default, but Verilator ignores it when a run raises
  // +verilator+error+limit (the mutation runner does, to see several checks fire). The
  // sticky flag keeps the verdict honest in that case.
  task automatic fail(input string why);
    tb_failed = 1'b1;
    $display("TB FAIL %s", why);
    $fatal(1, "TB FAIL %s", why);
  endtask

  // ---- reference model -----------------------------------------------------
  // Deliberately not the RTL's structure: wide integer arithmetic for carry and
  // signed overflow, unsigned compare for "no borrow". Returns {n, z, c, v, y}.
  function automatic logic [W+3:0] ref_alu(input logic [2:0] op,
                                           input logic [W-1:0] a,
                                           input logic [W-1:0] b);
    longint sa, sb, lim_hi, lim_lo, wide;
    logic [W-1:0] y;
    logic c, v;
    logic [$clog2(W)-1:0] sh;
    sa     = longint'($signed(a));
    sb     = longint'($signed(b));
    lim_hi = (longint'(1) <<< (W - 1)) - 1;
    lim_lo = -(longint'(1) <<< (W - 1));
    sh     = b[$clog2(W)-1:0];
    y = '0;
    c = 1'b0;
    v = 1'b0;
    wide = 0;
    case (op)
      3'd0: begin  // ADD
        wide = longint'(a) + longint'(b);
        y    = wide[W-1:0];
        c    = (wide > ((longint'(1) <<< W) - 1));
        v    = ((sa + sb) > lim_hi) || ((sa + sb) < lim_lo);
      end
      3'd1: begin  // SUB: C = 1 means no borrow
        wide = longint'(a) - longint'(b);
        y    = wide[W-1:0];
        c    = (a >= b);
        v    = ((sa - sb) > lim_hi) || ((sa - sb) < lim_lo);
      end
      3'd2:    y = a & b;
      3'd3:    y = a | b;
      3'd4:    y = a ^ b;
      3'd5:    y = a << sh;
      3'd6:    y = a >> sh;
      default: y = (a < b) ? W'(1) : W'(0);  // 3'd7 SLTU
    endcase
    return {y[W-1], (y == '0), c, v, y};
  endfunction

  // ---- known answers, derived by hand from spec 4.3 (not from ref_alu) -----
  typedef struct packed {
    logic [2:0]   op;
    logic [W-1:0] a;
    logic [W-1:0] b;
    logic [W-1:0] y;
    logic [3:0]   nzcv;
  } ka_t;

  localparam int unsigned N_KA = 20;

  function automatic ka_t ka_row(input int unsigned i);
    ka_t r;
    case (i)
      0:  r = '{op: 3'd0, a: 16'hFFFF, b: 16'h0001, y: 16'h0000, nzcv: 4'b0110};  // ADD carry out, zero
      1:  r = '{op: 3'd0, a: 16'h7FFF, b: 16'h0001, y: 16'h8000, nzcv: 4'b1001};  // ADD signed overflow
      2:  r = '{op: 3'd0, a: 16'h8000, b: 16'h8000, y: 16'h0000, nzcv: 4'b0111};  // ADD carry and overflow
      3:  r = '{op: 3'd0, a: 16'hFFFF, b: 16'hFFFF, y: 16'hFFFE, nzcv: 4'b1010};  // ADD neg+neg, no overflow
      4:  r = '{op: 3'd1, a: 16'h0000, b: 16'h0001, y: 16'hFFFF, nzcv: 4'b1000};  // SUB borrow (C=0)
      5:  r = '{op: 3'd1, a: 16'h8000, b: 16'h0001, y: 16'h7FFF, nzcv: 4'b0011};  // SUB overflow, no borrow
      6:  r = '{op: 3'd1, a: 16'h0005, b: 16'h0005, y: 16'h0000, nzcv: 4'b0110};  // SUB equal operands
      7:  r = '{op: 3'd1, a: 16'h7FFF, b: 16'hFFFF, y: 16'h8000, nzcv: 4'b1001};  // SUB pos-neg overflow
      8:  r = '{op: 3'd7, a: 16'h0001, b: 16'h0002, y: 16'h0001, nzcv: 4'b0000};  // SLTU true
      9:  r = '{op: 3'd7, a: 16'h8000, b: 16'h0001, y: 16'h0000, nzcv: 4'b0100};  // SLTU unsigned, not signed
      10: r = '{op: 3'd5, a: 16'h0001, b: 16'h000F, y: 16'h8000, nzcv: 4'b1000};  // SLL by 15
      11: r = '{op: 3'd5, a: 16'h0001, b: 16'h0010, y: 16'h0001, nzcv: 4'b0000};  // SLL: bits above shift field ignored
      12: r = '{op: 3'd5, a: 16'h0001, b: 16'hFFF0, y: 16'h0001, nzcv: 4'b0000};  // SLL: bits above shift field ignored
      13: r = '{op: 3'd6, a: 16'h8000, b: 16'h000F, y: 16'h0001, nzcv: 4'b0000};  // SRL logical by 15
      14: r = '{op: 3'd6, a: 16'hFFFF, b: 16'h00F0, y: 16'hFFFF, nzcv: 4'b1000};  // SRL: bits above shift field ignored
      15: r = '{op: 3'd2, a: 16'hF0F0, b: 16'h0FF0, y: 16'h00F0, nzcv: 4'b0000};  // AND
      16: r = '{op: 3'd3, a: 16'hF0F0, b: 16'h0FF0, y: 16'hFFF0, nzcv: 4'b1000};  // OR
      17: r = '{op: 3'd4, a: 16'hF0F0, b: 16'h0FF0, y: 16'hFF00, nzcv: 4'b1000};  // XOR
      18: r = '{op: 3'd4, a: 16'hAA55, b: 16'hAA55, y: 16'h0000, nzcv: 4'b0100};  // XOR equal operands
      default: r = '{op: 3'd7, a: 16'h0002, b: 16'h0001, y: 16'h0000, nzcv: 4'b0100};  // SLTU false
    endcase
    return r;
  endfunction

  task automatic check_model();
    ka_t r;
    logic [W+3:0] got;
    for (int unsigned i = 0; i < N_KA; i++) begin
      r   = ka_row(i);
      got = ref_alu(r.op, r.a, r.b);
      if (got !== {r.nzcv, r.y}) begin
        $display("MODEL SELFTEST FAIL row=%0d op=%0d a=%h b=%h got={nzcv=%b y=%h} want={nzcv=%b y=%h}",
                 i, r.op, r.a, r.b, got[W+3:W], got[W-1:0], r.nzcv, r.y);
        fail("model selftest");
      end
    end
  endtask

  // ---- operand set for the directed phase ----------------------------------
  function automatic logic [W-1:0] s_val(input int unsigned i);
    case (i)
      0: return 16'h0000;
      1: return 16'h0001;
      2: return 16'h7FFF;
      3: return 16'h8000;
      4: return 16'hFFFF;
      5: return 16'hAAAA;
      6: return 16'h5555;
      default: return 16'h00F0;
    endcase
  endfunction

  // ---- stimulus helpers ----------------------------------------------------
  task automatic send_exp(input logic [2:0] op, input logic [W-1:0] a, input logic [W-1:0] b,
                          input logic [W+3:0] e);
    cmd_t c;
    c.op = op;
    c.a  = a;
    c.b  = b;
    src_q.push_back(c);
    exp_q.push_back(e);
    total_cmds++;
    if (seen_cmd.exists(c) == 0) begin
      seen_cmd[c] = 1'b1;
      distinct++;
    end
  endtask

  task automatic send_cmd(input logic [2:0] op, input logic [W-1:0] a, input logic [W-1:0] b);
    send_exp(op, a, b, ref_alu(op, a, b));
  endtask

  task automatic drain(input int unsigned timeout_cycles);
    int unsigned t;
    t = 0;
    while ((src_q.size() != 0 || exp_q.size() != 0) && t < timeout_cycles) begin
      @(posedge clk);
      t++;
    end
    if (src_q.size() != 0 || exp_q.size() != 0) fail("drain timeout");
  endtask

  // Random commands: each operand comes from the corner set 25% of the time, so carry,
  // overflow, equal operands and full-width shifts all occur.
  task automatic send_random(input int unsigned n);
    logic [31:0] r1, r2;
    logic [W-1:0] a, b;
    for (int unsigned k = 0; k < n; k++) begin
      r1 = rnd();
      r2 = rnd();
      a  = (r1[1:0] == 2'd0) ? s_val(32'(r1[4:2])) : r1[31:16];
      b  = (r1[6:5] == 2'd0) ? s_val(32'(r1[9:7])) : r2[15:0];
      send_cmd(r2[18:16], a, b);
    end
  endtask

  // Wait until both FIFOs are full (sink stalled, source still offering).
  task automatic wait_full();
    int unsigned t;
    t = 0;
    while (!(dut.in_full && dut.out_full) && t < 100 * DEPTH + 100) begin
      @(posedge clk);
      t++;
    end
    if (!(dut.in_full && dut.out_full)) fail("fill timeout");
  endtask

  // Void everything in flight at a reset. Call from the main thread just after a posedge.
  // Keeps the counters balanced: commands that were accepted but not delivered, and those
  // not yet accepted, no longer count.
  task automatic flush_all();
    total_cmds    = total_cmds - exp_q.size();
    accepted      = accepted - (exp_q.size() - src_q.size());
    src_q.delete();
    exp_q.delete();
    in_valid      = 1'b0;
    accepted_last = 1'b0;
  endtask

  // ---- source driver: present at negedge, hold until accepted ----------------
  always @(negedge clk) begin
    logic [31:0] r;
    if (in_valid && !accepted_last) begin
      // protocol: valid and the command stay unchanged until in_ready is seen
    end else begin
      r = rnd();
      if (src_q.size() != 0 && int'(r % 100) < p_src) begin
        in_valid = 1'b1;
        in_op    = src_q[0].op;
        in_a     = src_q[0].a;
        in_b     = src_q[0].b;
      end else begin
        r        = rnd();
        in_valid = 1'b0;  // idle: random garbage on the bus, so a DUT that samples it fails
        in_op    = r[2:0];
        in_a     = r[15:0];
        in_b     = r[31:16];
      end
    end
    r = rnd();
    out_ready = (int'((r >> 8) % 100) < p_snk);
  end

  // ---- monitor and scoreboard: sample at posedge, compare on valid && ready ---
  always @(posedge clk) begin
    logic [W+3:0] e;
    accepted_last = 1'b0;
    if (rst_n) begin
      if (in_valid && in_ready) begin
        accepted_last = 1'b1;
        void'(src_q.pop_front());
        accepted++;
      end
      if (out_valid && out_ready) begin
        delivered++;
        if (exp_q.size() == 0) begin
          $display("SCOREBOARD MISMATCH unexpected output flags=%b y=%h", out_flags, out_y);
          fail("unexpected output");
        end else begin
          e = exp_q.pop_front();
          if ({out_flags, out_y} !== e) begin
            $display("SCOREBOARD MISMATCH output=%0d got={flags=%b y=%h} want={flags=%b y=%h}",
                     delivered, out_flags, out_y, e[W+3:W], e[W-1:0]);
            fail("scoreboard");
          end
        end
      end
    end
  end

  // ---- watchdog ------------------------------------------------------------
  initial begin
    #100_000_000;
    fail("watchdog");
  end

  // ---- the test ------------------------------------------------------------
  string vcd_path;
  initial begin
    if (!$value$plusargs("seed=%d", seed_u)) seed_u = 32'd1;
    rng = seed_u ^ 32'h9E3779B9;
    if (rng == 32'd0) rng = 32'd1;
    if (!$value$plusargs("ncmd=%d", ncmd)) ncmd = 20000;
    if ($value$plusargs("vcd=%s", vcd_path)) begin
      $dumpfile(vcd_path);
      $dumpvars(0, tb_alu_fifo);
    end

    check_model();

    // Phase 1: reset. Both FIFOs empty, out_valid low, in_ready high.
    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk);
    if (out_valid !== 1'b0 || in_ready !== 1'b1) fail("reset state");
    rst_n = 1'b1;

    // Phase 2: directed. Every op against every ordered pair of corner operands,
    // then the known-answer rows with their hand-derived expected words.
    p_src = 100;
    p_snk = 100;
    for (int unsigned op = 0; op < 8; op++)
      for (int unsigned i = 0; i < 8; i++)
        for (int unsigned j = 0; j < 8; j++)
          send_cmd(op[2:0], s_val(i), s_val(j));
    for (int unsigned k = 0; k < N_KA; k++) begin
      ka_t r;
      r = ka_row(k);
      send_exp(r.op, r.a, r.b, {r.nzcv, r.y});
    end
    drain(200000);

    // Phase 3: fill and drain. Sink stalled; every slot gets a different operand pair so a
    // slot mix-up changes a result. The source keeps offering 3 commands past capacity and
    // must hold the first of them (in_valid high, in_ready low) until the sink opens.
    begin
      int unsigned base;
      base  = accepted;
      p_src = 100;
      p_snk = 0;
      for (int unsigned k = 0; k < 2 * DEPTH + 3; k++)
        send_cmd(k[2:0], W'(32'h1000 + k), W'(32'h0100 * k + 32'd3));
      wait_full();
      repeat (3) @(posedge clk);
      @(negedge clk);
      if (in_ready !== 1'b0 || out_valid !== 1'b1) fail("fill: in_ready must be low and out_valid high when full");
      if (accepted - base != 2 * DEPTH) fail("fill: wrong number accepted while the sink is stalled");
      p_snk = 100;
      drain(200000);
    end

    // Phase 4: wrap. 4*DEPTH+1 commands per mix go through both FIFOs, so both pointers wrap
    // at several fill levels.
    for (int unsigned m = 0; m < 3; m++) begin
      if (m == 0)      begin p_src = 100; p_snk = 30;  end
      else if (m == 1) begin p_src = 30;  p_snk = 100; end
      else             begin p_src = 60;  p_snk = 60;  end
      send_random(4 * DEPTH + 1);
      drain(200000);
    end

    // Phase 5: random. Source and sink offered at 10, 50 and 90 percent, every combination.
    for (int pi = 0; pi < 3; pi++) begin
      for (int pj = 0; pj < 3; pj++) begin
        p_src = 10 + 40 * pi;
        p_snk = 10 + 40 * pj;
        send_random(ncmd / 9);
        drain(100 * (ncmd / 9) + 10000);
      end
    end

    // Phase 6: reset in traffic. Both FIFOs full, sink stalled, source still offering; reset
    // for two cycles. Nothing stale may survive, and the next commands must be right.
    p_src = 100;
    p_snk = 0;
    for (int unsigned k = 0; k < 2 * DEPTH + 2; k++)
      send_cmd(k[2:0], W'(32'h2000 + k), W'(32'h0200 * k + 32'd5));
    wait_full();
    @(posedge clk);
    #1;
    rst_n = 1'b0;
    flush_all();
    repeat (2) @(posedge clk);
    @(negedge clk);
    if (out_valid !== 1'b0 || in_ready !== 1'b1) fail("reset in traffic: stale state after reset");
    rst_n = 1'b1;
    p_snk = 100;
    for (int unsigned k = 0; k < 4; k++)
      send_cmd(k[2:0], W'(32'h3000 + 32'h0111 * k), W'(32'h0F0F ^ (32'h0101 * k)));
    drain(200000);

    repeat (4) @(posedge clk);  // any extra output would be an unexpected-output mismatch
    if (accepted != total_cmds || delivered != total_cmds) fail("accepted/delivered count");
    if (tb_failed) begin
      $display("TB FAIL a check failed earlier in this run");
    end else begin
      $display("TB PASS seed=%0d cmds=%0d", seed_u, total_cmds);
      $display("TB STATS distinct_cmds=%0d", distinct);
    end
    $finish;
  end
endmodule
