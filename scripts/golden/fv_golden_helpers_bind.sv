// fv_golden_helpers_bind.sv -- binds the chk_data_match helper invariants
// (fv/fv_afifo/fv_afifo_helpers.sv) into the GOLDEN FIFO. It is the very same
// module that is bound into the baseline FIFO; only the parameters differ.
// (`bind` = insert a module instance into a design without editing its source.)
//
// Golden geometry: AW=4, memory mem[0:15], physical pointers w_ptr/r_ptr run
// 0..15 (a 16-slot ring based at 0). Full uses the extra wrap bit, so all 16
// slots are usable: DEPTH = DEPTH_EFF = 16. SEQW=5 matches the golden checker
// bind (2**5 = 32 > 16 entries in flight, so the sequence counters never alias).
//
// Analyse the helper module with +define+FV_MEM_ASCENDING (mem is [0:15]).
// Must be analysed AFTER fv_golden_afifo_bind.sv: it reads the scoreboard
// signals out of the checker instance tc_checker_inst.
bind gold_top fv_afifo_helpers #(.DW(8), .AW(4), .SEQW(5), .DEPTH(16), .DEPTH_EFF(16),
                                 .PTR_MIN(0), .PTR_MAX(15))
  tc_helpers_inst (
  .w_clk(w_clk), .wrst_n(wrst_n),
  .r_clk(r_clk), .rrst_n(rrst_n),
  .b_wptr(w_ptr), .b_rptr(r_ptr),          // physical indices = slot numbers
  .data_out(data_out),
  .f_mem(mem),
  .tag(tc_checker_inst.tag),
  .wr_seq(tc_checker_inst.wr_seq),
  .rd_seq(tc_checker_inst.rd_seq),
  .data_tracked(tc_checker_inst.data_tracked),
  .valid(tc_checker_inst.valid)
);
