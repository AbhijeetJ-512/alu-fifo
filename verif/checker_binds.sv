// checker_binds - attach the checkers to the RTL. `.*` connects by name, so the RTL port
// and wire names in rtl/ are a contract with the checkers (see the note in alu_fifo_top.sv).
bind sync_fifo sync_fifo_checker #(.WIDTH(WIDTH), .DEPTH(DEPTH)) u_chk (.*);
bind alu_fifo_top alu_fifo_checker #(.W(W), .DEPTH(DEPTH)) u_chk (.*);
