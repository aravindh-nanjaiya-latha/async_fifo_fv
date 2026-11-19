// fv_afifo_helpers_bind.sv -- attaches the helper properties (fv_afifo_helpers.sv)
// to the baseline FIFO, next to the contract checker.
//
// `bind` places the helper module inside `top` without editing the RTL.
// It needs two kinds of signals:
//   - design signals: pointers, data_out, and the memory array
//     f_memory_inst.f_mem (a hierarchical name: instance.signal)
//   - the contract checker's scoreboard: tag, wr_seq, rd_seq, data_tracked,
//     valid, read out of the checker instance tc_checker_inst.
// So it must be analysed AFTER fv_afifo_bind.sv, which creates tc_checker_inst.
// The memory is [54:9] (descending), which matches the helper's default port.
bind top fv_afifo_helpers #(.DW(`FV_DW), .AW(6), .SEQW(6), .DEPTH(46), .DEPTH_EFF(45), .PTR_MIN(9), .PTR_MAX(54))
  tc_helpers_inst (
  .w_clk(w_clk), .wrst_n(wrst_n),
  .r_clk(r_clk), .rrst_n(rrst_n),
  .b_wptr(b_wptr), .b_rptr(b_rptr),
  .data_out(data_out),
  .f_mem(f_memory_inst.f_mem),
  .tag(tc_checker_inst.tag),
  .wr_seq(tc_checker_inst.wr_seq),
  .rd_seq(tc_checker_inst.rd_seq),
  .data_tracked(tc_checker_inst.data_tracked),
  .valid(tc_checker_inst.valid)
);
