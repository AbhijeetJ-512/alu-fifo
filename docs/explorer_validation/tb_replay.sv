// tb_replay - closed-loop replay of one explorer scenario against the real RTL, one trace line per clock cycle.
//   +cmds=<file>  one 35-bit hex word {op, a, b} per command     +src=<file> / +snk=<file>  512 lines of 0/1: offer / ready in cycle i+1
//   +n=<commands>  +ncyc=<cycles>  +log=<file>
// The source holds a command until in_ready is seen at a clock edge (as verif/tb_alu_fifo.sv does) and offers the next one
// only when its pattern bit for that cycle is 1; the sink's out_ready is its pattern bit, independent of out_valid.
// Cycle 1 is the first cycle after reset. Each line is sampled just before the clock edge, so it holds that cycle's values.
module tb_replay;
  localparam int unsigned W = 16;
  parameter  int unsigned DEPTH = 8;
  logic clk = 1'b0, rst_n = 1'b0, in_valid = 1'b0, out_ready = 1'b0;
  logic [2:0] in_op = '0; logic [W-1:0] in_a = '0, in_b = '0;
  wire in_ready, out_valid; wire [W-1:0] out_y; wire [3:0] out_flags;
  alu_fifo_top #(.W(W), .DEPTH(DEPTH)) dut (.*);
  always #5 clk = ~clk;

  logic [34:0] cmds [0:255];
  logic [3:0]  srcp [0:511];
  logic [3:0]  snkp [0:511];
  string cmds_f, src_f, snk_f, log_f;
  int n, ncyc, qi, cyc, fd;

  initial begin
    if (!$value$plusargs("cmds=%s", cmds_f) || !$value$plusargs("src=%s", src_f) || !$value$plusargs("snk=%s", snk_f) ||
        !$value$plusargs("n=%d", n) || !$value$plusargs("ncyc=%d", ncyc) || !$value$plusargs("log=%s", log_f)) begin
      $display("tb_replay: missing plusarg"); $finish;
    end
    for (int i = 0; i < 256; i++) cmds[i] = '0;
    for (int i = 0; i < 512; i++) begin srcp[i] = '0; snkp[i] = '0; end
    $readmemh(cmds_f, cmds); $readmemh(src_f, srcp); $readmemh(snk_f, snkp);
    fd = $fopen(log_f, "w");
    repeat (3) @(posedge clk);
    #2 rst_n = 1'b1;           // released away from a clock edge; cycle 1 starts here
    cyc = 1; qi = 0;
    if (n > 0 && srcp[0] == 4'd1) begin in_valid = 1'b1; {in_op, in_a, in_b} = cmds[0]; qi = 1; end
    out_ready = (snkp[0] == 4'd1);
  end

  always @(posedge clk) if (rst_n) begin
    $fwrite(fd, "%0d %0h %0h %0h %0h %0h %0h %0h %0h %0h %0h %0h %0h %0h %0h %0h %0h\n", cyc,
            in_valid, in_ready, in_valid ? in_op : 3'd0, in_valid ? in_a : 16'd0, in_valid ? in_b : 16'd0,
            out_valid, out_ready, out_valid ? out_y : 16'd0, out_valid ? out_flags : 4'd0,
            dut.u_in_fifo.wr_ptr, dut.u_in_fifo.rd_ptr, dut.u_out_fifo.wr_ptr, dut.u_out_fifo.rd_ptr,
            dut.xfer, dut.in_empty ? 16'd0 : dut.alu_y, dut.in_empty ? 4'd0 : dut.res_flags);
    if (in_valid && in_ready) in_valid <= 1'b0;
    if ((!in_valid || in_ready) && qi < n && srcp[cyc] == 4'd1) begin
      in_valid <= 1'b1; {in_op, in_a, in_b} <= cmds[qi]; qi = qi + 1;
    end
    out_ready <= (snkp[cyc] == 4'd1);
    cyc = cyc + 1;
    if (cyc > ncyc) begin $fclose(fd); $finish; end
  end
endmodule
