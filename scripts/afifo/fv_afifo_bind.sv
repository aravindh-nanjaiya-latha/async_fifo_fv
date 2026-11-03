// bind for the student async FIFO. Pointer names must match the wires declared in rtl/top.sv.
bind top fv_afifo #(.DW(`FV_DW), .AW(6), .SEQW(6), .DEPTH(46), .DEPTH_EFF(45), .PTR_MIN(9), .PTR_MAX(54))
  tc_checker_inst (
  .w_clk(w_clk), .wrst_n(wrst_n), .w_en(w_en), .full(full), .data_in(data_in),
  .b_wptr(b_wptr), .g_wptr(g_wptr),
  .r_clk(r_clk), .rrst_n(rrst_n), .r_en(r_en), .empty(empty), .data_out(data_out),
  .b_rptr(b_rptr), .g_rptr(g_rptr)
);
