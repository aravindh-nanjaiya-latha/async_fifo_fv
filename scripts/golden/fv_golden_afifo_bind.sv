// fv_golden_afifo_bind.sv -- attaches the golden checker (module fv_afifo_full,
// fv/fv_golden_afifo/fv_golden_afifo.sv) inside the golden FIFO gold_top.
//
// `bind` adds the checker instance without editing the design file. The
// instance name tc_checker_inst matters: the helper bind
// (fv_golden_helpers_bind.sv) reads the scoreboard out of it.
// SEQW=5: the sequence counters must count past the 16 entries that can be in
// flight (2**5 = 32 > 16), so the checker never confuses two entries.
// wbin/wgray and rbin/rgray are internal golden signals, visible through bind.
bind gold_top fv_afifo_full #(.DW(8), .AW(4), .SEQW(5)) tc_checker_inst (
  .w_clk(w_clk), .wrst_n(wrst_n), .w_en(w_en), .full(full), .data_in(data_in),
  .w_ptr(w_ptr), .wbin(wbin), .wgray(wgray),
  .r_clk(r_clk), .rrst_n(rrst_n), .r_en(r_en), .empty(empty), .data_out(data_out),
  .r_ptr(r_ptr), .rbin(rbin), .rgray(rgray)
);
