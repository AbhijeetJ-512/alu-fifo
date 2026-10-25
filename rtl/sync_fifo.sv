// sync_fifo - single-clock FIFO, first-word-fall-through read (spec 4.3).
//   - pointers are $clog2(DEPTH)+1 bits: the extra bit tells full from empty
//   - dout = mem[rd_ptr]; the entry is valid when !empty
//   - a push while full and a pop while empty are ignored
//   - synchronous active-low reset clears the pointers only, not the memory
module sync_fifo #(
  parameter int unsigned WIDTH = 8,
  parameter int unsigned DEPTH = 8
) (
  input  logic             clk,
  input  logic             rst_n,
  input  logic             push,
  input  logic [WIDTH-1:0] din,
  input  logic             pop,
  output logic [WIDTH-1:0] dout,
  output logic             full,
  output logic             empty
);
  if (DEPTH < 2 || (DEPTH & (DEPTH - 1)) != 0) begin : g_bad_depth $error("DEPTH must be a power of two >= 2"); end

  localparam int unsigned AW = $clog2(DEPTH);
  localparam logic [AW:0] ONE = (AW + 1)'(1);

  logic [WIDTH-1:0] mem [DEPTH];
  logic [AW:0]      wr_ptr;
  logic [AW:0]      rd_ptr;

  assign empty = (wr_ptr == rd_ptr);
  assign full  = (wr_ptr[AW-1:0] == rd_ptr[AW-1:0]) && (wr_ptr[AW] != rd_ptr[AW]);
  assign dout  = mem[rd_ptr[AW-1:0]];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wr_ptr <= '0;
      rd_ptr <= '0;
    end else begin
      if (push && !full) begin
        mem[wr_ptr[AW-1:0]] <= din;
        wr_ptr              <= wr_ptr + ONE;
      end
      if (pop && !empty) begin
        rd_ptr <= rd_ptr + ONE;
      end
    end
  end
endmodule
