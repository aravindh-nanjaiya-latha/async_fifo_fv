// fv_afifo_bind.sv -- attaches the contract checker to the baseline FIFO.
//
// `bind` creates an instance of a module (here fv_afifo) INSIDE another module
// (here `top`) without editing that module's source. This keeps rtl/ untouched:
// the checker sees the design's internal wires, but no RTL line is changed.
//
// The instance is named tc_checker_inst; the helper properties
// (fv_afifo_helpers_bind.sv) read the scoreboard out of it by that name.
// The names on the right of each .port(...) are wires declared in rtl/top.sv
// and must match them exactly. FV_DW is the data width, passed in by the tcl.
// Geometry: 6-bit pointers, ring 9..54 (46 slots), 45 usable, 6-bit counters.
bind top fv_afifo #(.DW(`FV_DW), .AW(6), .SEQW(6), .DEPTH(46), .DEPTH_EFF(45), .PTR_MIN(9), .PTR_MAX(54))
  tc_checker_inst (
  .w_clk(w_clk), .wrst_n(wrst_n), .w_en(w_en), .full(full), .data_in(data_in),
  .b_wptr(b_wptr), .g_wptr(g_wptr),
  .r_clk(r_clk), .rrst_n(rrst_n), .r_en(r_en), .empty(empty), .data_out(data_out),
  .b_rptr(b_rptr), .g_rptr(g_rptr)
);
