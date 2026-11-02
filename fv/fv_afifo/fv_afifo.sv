//=============================================================================
// fv_afifo -- FPV checker for the student async FIFO (rtl/, top module `top`)
//
// Ported from fv/fv_golden_afifo/fv_golden_afifo.sv (proven 22/22 on gold_top).
// Rule for this file: asserts and covers only. The single assume (stable tag)
// is the symbolic-scoreboard requirement and is kept deliberately.
//
// Design facts this checker encodes (from RTL inspection, 2026-10-28):
//   - binary pointers b_wptr/b_rptr: AW=6 bits, reset 9, range 9..54 (DEPTH=46 slots)
//   - full = (b_wptr_next == b_rptr_sync)  -> one slot kept empty -> DEPTH_EFF = 45 entries
//   - gray pointers g_wptr/g_rptr computed per domain, 2-FF synchronised
//   - flags are combinational in both domains -> flag latency after a crossing = 2 edges
//
// Properties deliberately NOT adapted to the design:
//   - chk_*gray_onehot0 : the wrap 53->9 flips two gray bits (Bug 4). Expected to CEX.
//=============================================================================

module fv_afifo #(
  parameter int DW      = 8,
  parameter int AW      = 6,    // pointer width (NOT log2(depth) here -- range is 9..53)
  parameter int SEQW    = 6,    // scheme A: 2**SEQW > DEPTH_EFF  (45 -> 6)
  parameter int DEPTH   = 46,   // memory slots / pointer range size
  parameter int DEPTH_EFF = 45, // usable entries: full = (wptr_next == rptr) wastes one slot
  parameter int PTR_MIN = 9,
  parameter int PTR_MAX = 54
)(
  input logic          w_clk, wrst_n, w_en, full,
  input logic [DW-1:0] data_in,
  input logic [AW-1:0] b_wptr,             // binary write pointer (also the mem index)
  input logic [AW-1:0] g_wptr,             // gray write pointer (the signal that crosses)
  input logic          r_clk, rrst_n, r_en, empty,
  input logic [DW-1:0] data_out,
  input logic [AW-1:0] b_rptr,             // binary read pointer
  input logic [AW-1:0] g_rptr              // gray read pointer
);

   // 2 synchroniser flops, combinational flags -> flag visible 2 destination edges later
   localparam int SYNC_LAT_R = 3;   // 2 sync flops + registered empty
   localparam int SYNC_LAT_W = 2;   // 2 sync flops, combinational full

   // the design's own successor function: 9..53, then back to 9
   function automatic logic [AW-1:0] next_ptr(input logic [AW-1:0] p);
      return (p == AW'(PTR_MAX)) ? AW'(PTR_MIN) : p + 1'b1;
   endfunction

   logic wr_fire, rd_fire;
   assign wr_fire = w_en && !full;
   assign rd_fire = r_en && !empty;


//==========================================================
// --reset--
//==========================================================

      //check empty after reset           (Bug 1 detector: sync resets 0, g_rptr resets gray(9))
      chk_fv_empty_after_reset:
	assert property (@(posedge r_clk)
		      $rose(rrst_n) |-> empty);

      //check no full after reset
      chk_fv_no_full_after_reset:
	assert property (@(posedge w_clk)
		      $rose(wrst_n) |-> !full);

      //stable data_out when there is no read
      chk_fv_stable_dout:
	assert property (@(posedge r_clk) disable iff (!rrst_n)
			 !rd_fire |=> $stable(data_out));

  //end of reset checks.

//=================================================================
//Symbolic technique to check data ordering and data integrity
//=================================================================

	 // a tag is created to take the symbolic value
	 logic [SEQW-1:0] tag;

	 //assume the tag is completely stable
	 //This property keeps the tag constant
	 chk_fv_asm_stable_tag:
	   assume property ($stable(tag));

	 //using local pointers to increment the value and when the tag matches the pointer
	 //data in is stored in into a internal logic.
	    logic [SEQW-1:0] wr_seq, rd_seq;

	    //increment on wr's
	    always_ff @(posedge w_clk or negedge wrst_n) begin
	       if(!wrst_n)
		 wr_seq <= '0;
	       else if (wr_fire)
		 wr_seq <= wr_seq + 1'b1;
	    end

   //increment on rd's
   always_ff @(posedge r_clk or negedge rrst_n) begin
      if(!rrst_n)
	rd_seq <= '0;
      else if (rd_fire)
	rd_seq <= rd_seq + 1'b1;
   end

   //logic to keep track of the data
   logic [DW-1:0] data_tracked;
   logic 	  valid;

   always_ff @(posedge w_clk or negedge wrst_n) begin
      if(!wrst_n) begin
	data_tracked <= '0;
        valid <= 1'b0;
      end else if (wr_fire && (wr_seq == tag)) begin
	 data_tracked <= data_in;
	 valid <= 1'b1;
      end
   end

   // occupancy from port events only (checker-owned counters, no RTL internals)
   // SEQW=6, max DEPTH_EFF=45 in flight -> no aliasing
   logic [SEQW-1:0] occ;
   assign occ = wr_seq - rd_seq;

   // When the rd tag matches - check data_out with data_tracked
   // One property covers integrity, ordering, no-drop and no-duplicate.
   chk_data_match:
     assert property (@(posedge r_clk) disable iff (!rrst_n)
		      (rd_seq == tag && rd_fire && valid) |=> (data_tracked == data_out));

//=================================================================
// pointer step / hold
//=================================================================
      // step: an accepted transfer moves the pointer to exactly its successor (incl. 53->9).
      // NOTE: NOT `+1` with a width cast as on the golden -- the range is 9..53, not 0..2^AW-1.
      chk_wrptr:
	assert property (@(posedge w_clk) disable iff (!wrst_n)
			 wr_fire |=> (b_wptr == next_ptr($past(b_wptr))));

      chk_rptr:
	assert property (@(posedge r_clk) disable iff (!rrst_n)
			 rd_fire |=> (b_rptr == next_ptr($past(b_rptr))));

     //below property checks if the pointer doesnt advance when the fifo is full / empty.
	 chk_no_increment_when_full:
	   assert property (@(posedge w_clk) disable iff (!wrst_n)
			    w_en && full |=> $stable(b_wptr));

	 chk_no_increment_when_empty:
	   assert property (@(posedge r_clk) disable iff (!rrst_n)
			    r_en && empty |=> $stable(b_rptr));

// hold - if no accepted write, b_wptr must not change on the next w_clk   (Bug 3b detector)
      chk_fv_same_w_ptr_on_no_write:
	assert property (@(posedge w_clk) disable iff (!wrst_n)
			 !wr_fire |=> ($past(b_wptr) == b_wptr));

// hold - if no accepted read, b_rptr must not change on the next r_clk    (Bug 3 detector)
	 chk_fv_same_r_ptr_on_no_read:
	   assert property (@(posedge r_clk) disable iff (!rrst_n)
			    !rd_fire |=> ($past(b_rptr) == b_rptr));

//=================================================================
// gray pointers (CDC-relevant)
//=================================================================
   //gray coded ptr's must differ in exactly one bit between consecutive values,
   //INCLUDING at the wrap. Written as on the golden; NOT adapted to 9..53 on purpose.
      chk_wgray_onehot0:
	assert property (@(posedge w_clk) disable iff (!wrst_n)
			 $past(wrst_n) |-> $onehot0(g_wptr ^ $past(g_wptr)));

	 chk_rgray_onehot0:
	   assert property (@(posedge r_clk) disable iff (!rrst_n)
			    $past(rrst_n) |-> $onehot0(g_rptr ^ $past(g_rptr)));

    // gray value is the correct encoding of the binary pointer
      chk_wgray_correct_encoding:
        assert property (@(posedge w_clk) disable iff (!wrst_n)
                         (g_wptr == (b_wptr ^ (b_wptr >> 1))));

      chk_rgray_correct_encoding:
        assert property (@(posedge r_clk) disable iff (!rrst_n)
                         (g_rptr == (b_rptr ^ (b_rptr >> 1))));

//=================================================================
// occupancy vs flags (black-box: occ is built from port events only)
//=================================================================
// A stale synchronised pointer can only make a flag MORE pessimistic, so these
// hold even though occ sees reads/writes before the other side does.
chk_fv_empty_when_occ_zero:
  assert property (@(posedge r_clk) disable iff (!rrst_n) (occ == 0)         |-> empty);
chk_fv_full_when_occ_depth:
  assert property (@(posedge w_clk) disable iff (!wrst_n) (occ == DEPTH_EFF) |-> full);

// bounded response -- the honest form of the converse: a flag may lag the true
// occupancy, but only by the synchroniser latency. Written in the flag's own domain.
chk_fv_empty_deasserts_within_sync_lat:
  assert property (@(posedge r_clk) disable iff (!rrst_n)
    (empty && (occ != 0)) |-> ##[1:SYNC_LAT_R] !empty);

chk_fv_full_deasserts_within_sync_lat:
  assert property (@(posedge w_clk) disable iff (!wrst_n)
    (full && (occ != DEPTH_EFF)) |-> ##[1:SYNC_LAT_W] !full);

//=================================================================
// covers (non-vacuity)
//=================================================================
    //full and empty conditions happen
	    cov_full_after_empty:
	      cover property (@(posedge w_clk) disable iff (!wrst_n)
			      empty ##[1:$] full);
	    cov_empty_after_full:
	      cover property (@(posedge w_clk) disable iff (!wrst_n)
			      full ##[1:$] empty);

// cover - an accepted write occurs while wr_seq equals tag (scoreboard captures)
	 cov_fv_data_captured:
	   cover property (@(posedge w_clk)
			   ((tag == wr_seq) && wr_fire) ##1 valid);

// cover - an accepted read occurs while rd_seq equals tag and valid is set (scoreboard checks)
	 cov_fv_data_checked:
	   cover property (@(posedge r_clk)
			   (tag == rd_seq) && rd_fire);

// cover - the same symbolic tag is checked twice (rd_seq wrapped through 2**SEQW reads):
//         the case scheme A exists for.
	 cov_fv_check_second_lap:
	   cover property (@(posedge r_clk) disable iff (!rrst_n)
			   (tag == rd_seq && rd_fire) ##1 (tag != rd_seq)[*1:$] ##1 (tag == rd_seq && rd_fire));

// cover - the pointer wrap 53 -> 9 is exercised on both sides
	 cov_fv_wptr_wrap:
	   cover property (@(posedge w_clk) disable iff (!wrst_n)
			   (b_wptr == AW'(PTR_MAX)) && wr_fire ##1 (b_wptr == AW'(PTR_MIN)));

	 cov_fv_rptr_wrap:
	   cover property (@(posedge r_clk) disable iff (!rrst_n)
			   (b_rptr == AW'(PTR_MAX)) && rd_fire ##1 (b_rptr == AW'(PTR_MIN)));

// cover - the bounded-response bound is reachable AND tight (hit at exactly SYNC_LAT)
	 cov_fv_empty_bound_tight:
	   cover property (@(posedge r_clk) disable iff (!rrst_n)
			   (empty && (occ != 0)) ##SYNC_LAT_R !empty);
	 cov_fv_full_bound_tight:
	   cover property (@(posedge w_clk) disable iff (!wrst_n)
			   (full && (occ != DEPTH_EFF)) ##SYNC_LAT_W !full);

endmodule
