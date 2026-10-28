bind gold_top fv_afifo_full #(.DW(8), .AW(4), .SEQW(5)) tc_checker_inst (
  .w_clk(w_clk), .wrst_n(wrst_n), .w_en(w_en), .full(full), .data_in(data_in),
  .w_ptr(w_ptr), .wbin(wbin), .wgray(wgray),
  .r_clk(r_clk), .rrst_n(rrst_n), .r_en(r_en), .empty(empty), .data_out(data_out),
  .r_ptr(r_ptr), .rbin(rbin), .rgray(rgray)
);
