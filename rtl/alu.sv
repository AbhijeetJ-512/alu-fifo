// alu - combinational ALU (spec 4.3). Returns y, c and v; Z and N are derived from y in
// the top so one piece of logic serves every op.
//   ADD: c = carry-out of a + b          v = signed overflow
//   SUB: c = carry-out of a + ~b + 1     v = signed overflow   (c = 1 means no borrow)
//   others: c = v = 0.  Shifts use b[$clog2(W)-1:0]; SRL is logical.
module alu #(
  parameter int unsigned W = 16
) (
  input  logic [alu_pkg::OP_W-1:0] op,
  input  logic [W-1:0]             a,
  input  logic [W-1:0]             b,
  output logic [W-1:0]             y,
  output logic                     c,
  output logic                     v
);
  localparam int unsigned SH_W = $clog2(W);

  logic [W:0]      sum;
  logic [W:0]      diff;
  logic [SH_W-1:0] shamt;

  assign sum   = {1'b0, a} + {1'b0, b};
  assign diff  = {1'b0, a} + {1'b0, ~b} + {{W{1'b0}}, 1'b1};
  assign shamt = b[SH_W-1:0];

  always_comb begin
    y = '0;
    c = 1'b0;
    v = 1'b0;
    unique case (op)
      alu_pkg::OP_ADD: begin
        y = sum[W-1:0];
        c = sum[W];
        v = (a[W-1] == b[W-1]) && (sum[W-1] != a[W-1]);
      end
      alu_pkg::OP_SUB: begin
        y = diff[W-1:0];
        c = diff[W];
        v = (a[W-1] != b[W-1]) && (diff[W-1] != a[W-1]);
      end
      alu_pkg::OP_AND:  y = a & b;
      alu_pkg::OP_OR:   y = a | b;
      alu_pkg::OP_XOR:  y = a ^ b;
      alu_pkg::OP_SLL:  y = a << shamt;
      alu_pkg::OP_SRL:  y = a >> shamt;
      alu_pkg::OP_SLTU: y = {{(W-1){1'b0}}, (a < b)};
    endcase
  end
endmodule
