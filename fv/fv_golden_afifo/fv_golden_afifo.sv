//=============================================================================
// fv_afifo_full -- formal checker for the GOLDEN (reference) async FIFO
//                  (golden_fifo/golden_afifo.sv, top module gold_top)
//
// WHY A GOLDEN FIFO
//   The golden FIFO is a textbook depth-16 asynchronous FIFO (Cummings style:
//   gray-coded pointers with an extra wrap bit, 2-flop synchronisers,
//   registered flags), generated with Claude and declared as such. It is NOT
//   the subject of the project. Its job is to test the CHECKER: a property that
//   fails on a known-good design is a broken property. Every property here was
//   proven on gold_top (22/22) before it was ported to the baseline-FIFO checker
//   (fv/fv_afifo/fv_afifo.sv).
//
// HOW TO READ IT
//   assert property = must always hold;  cover property = must be reachable;
//   assume property = taken as given (only one here, the stable symbolic tag).
//   |-> means "in the same clock", |=> means "on the next clock".
//   disable iff (!rst_n) switches a property off while its reset is active.
//   The checker is attached with scripts/golden/fv_golden_afifo_bind.sv.
//
// GOLDEN GEOMETRY
//   wbin/rbin are AW+1 = 5 bits: 4 address bits plus a wrap bit, so full and
//   empty can be told apart and all 16 slots are usable. w_ptr/r_ptr are the
//   4-bit memory indices (0..15). Both flags are registered, so each may lag
//   the true fill level by 2 sync flops + 1 flag flop = 3 clocks (SYNC_LAT).
//=============================================================================


module fv_afifo_full #(
  parameter int DW = 8,
  parameter int AW = 4, // address bits: depth = 2**AW = 16
  parameter int BW = AW+1,
  parameter int SEQW = 4,
  parameter int DEPTH = (1<<AW)
)(
  input logic          w_clk, wrst_n, w_en, full,
  input logic [DW-1:0] data_in,
  input logic [AW-1:0] w_ptr,              // memory index being written (0..15)
  input logic [AW:0]   wbin,               // binary write counter, AW+1 bits (top bit = wrap bit)
  input logic [AW:0]   wgray,              // gray-coded write counter (the value that crosses to r_clk)
  input logic          r_clk, rrst_n, r_en, empty,
  input logic [DW-1:0] data_out,
  input logic [AW-1:0] r_ptr,              // memory index being read (0..15)
  input logic [AW:0]   rbin,               // binary read counter, AW+1 bits
  input logic [AW:0]   rgray               // gray-coded read counter (crosses to w_clk)
);


   logic 	       wr_fire, rd_fire;
   assign wr_fire = w_en && !full;
   assign rd_fire = r_en && !empty;
   

// wr_fire / rd_fire: a write / read the FIFO actually accepts. A request made
// while full / empty is legal but must have no effect.

//==========================================================
// --reset--  what must be true right after reset is released
//==========================================================

      // empty must be on as read-side reset is released
      chk_fv_empty_after_reset:
	assert property (@(posedge r_clk) 
		      $rose(rrst_n) |-> empty);

      // full must be off as write-side reset is released
      chk_fv_no_full_after_reset:
	assert property (@(posedge w_clk)
		      $rose(wrst_n) |-> !full);

      // data_out may only change on an accepted read
      chk_fv_stable_dout:
	assert property (@(posedge r_clk) disable iff (!rrst_n)
			 !rd_fire |=> $stable(data_out));

  // end of reset checks
	 
//=================================================================
// DATA INTEGRITY -- the "symbolic tag" scoreboard
// wr_seq / rd_seq count accepted writes / reads. `tag` is undriven, so the
// formal engine treats it as ANY value. The word written when wr_seq == tag is
// saved in data_tracked; when rd_seq == tag the word read out must match it.
// Because the tag can be any value, one property covers every word: correct
// data, correct order, nothing dropped, nothing duplicated.
//=================================================================

	 // the symbolic tag (undriven on purpose)
	 logic [SEQW-1:0] tag;

	 // The only assumption: the tag does not change during a run. It restricts a
	 // checker variable, never a FIFO input, so it cannot hide a design bug.
	 chk_fv_asm_stable_tag:
	   assume property ($stable(tag));

	 // Checker-owned sequence counters, built from port events only (they do not
	 // trust the RTL pointers).
	    logic [SEQW-1:0] wr_seq, rd_seq;

	    // +1 per accepted write
	    always_ff @(posedge w_clk or negedge wrst_n) begin
	       if(!wrst_n)
		 wr_seq <= '0;
	       else if (wr_fire)
		 wr_seq <= wr_seq + 1'b1;
	    end
   
   // +1 per accepted read
   always_ff @(posedge r_clk or negedge rrst_n) begin
      if(!rrst_n)
	rd_seq <= '0;
      else if (rd_fire)
	rd_seq <= rd_seq + 1'b1;
   end

   // capture the tagged word; valid = it has been captured
   logic [DW-1:0]data_tracked;
   logic 	   valid;
   
   always_ff @(posedge w_clk or negedge wrst_n) begin
      if(!wrst_n) begin
	data_tracked <= '0;
        valid <= 1'b0;
      end else if (wr_fire && (wr_seq == tag)) begin
	 data_tracked <= data_in;
	 valid <= 1'b1;
      end
   end

   // THE data property: when the tagged entry is read, data_out on the next read
   // clock (data_out is registered, hence |=>) must equal the captured word.
   // (Written 2026-09-27. Proven on gold_top without any helper properties.)
   chk_data_match:
     assert property (@(posedge r_clk) disable iff (!rrst_n)
		      (rd_seq == tag && rd_fire && valid) |=> (data_tracked == data_out));
      // POINTER STEP: an accepted transfer moves the pointer up by exactly one.
      // History: first written without the AW'(...) cast. $past(w_ptr)+1 is then
      // evaluated wider than 4 bits, so 15+1 = 16 never equalled the wrapped value 0
      // and Jasper reported a counterexample (CEX) on the legal wrap 1111 -> 0000.
      // AW'(...) truncates the sum to AW bits so the wrap compares correctly.
      // That CEX was a CHECKER error, not a design bug -- the reason for golden-first.
      chk_wrptr:
	assert property (@(posedge w_clk) disable iff (!wrst_n)
			 wr_fire |=> (w_ptr == AW'($past(w_ptr)+1)));
      // same step check for the read index
      chk_rptr:
	assert property (@(posedge r_clk) disable iff (!rrst_n)
			 rd_fire |=> (r_ptr == AW'($past(r_ptr)+1)));

      // same step check for the AW+1-bit counters (BW'(...) = AW+1-bit wrap)
      chk_wbin:
	assert property (@(posedge w_clk) disable iff (!wrst_n)
			 wr_fire |=> (wbin == BW'($past(wbin)+1)));
	 
      chk_rbin:
	assert property (@(posedge r_clk) disable iff (!rrst_n)
			 rd_fire |=> (rbin == BW'($past(rbin)+1)));

     // GUARD: a request while full / empty must not move the pointer.
     // ($stable = same value as on the previous clock)

	 chk_no_increment_when_full:
	   assert property (@(posedge w_clk) disable iff (!wrst_n)
			    w_en && full |=> $stable(w_ptr));

	 chk_no_increment_when_empty:
	   assert property (@(posedge r_clk) disable iff (!rrst_n)
			    r_en && empty |=> $stable(r_ptr));
	    
	    
	 
   // GRAY POINTERS. Gray code changes exactly one bit between consecutive values,
   // which is what makes a multi-bit pointer safe to sample from another clock.
   // A gray value does not simply "increase", so ">" against $past is useless.
   // Instead XOR the current and previous values: the result must have at most
   // one bit set ($onehot0 allows zero bits, i.e. no change).
      chk_wgray_onehot0:
	assert property (@(posedge w_clk) disable iff (!wrst_n)
			 $past(wrst_n) |-> $onehot0(wgray ^ $past(wgray)));

	 chk_rgray_onehot0:
	   assert property (@(posedge r_clk) disable iff (!rrst_n)
			    $past(rrst_n) |-> $onehot0(rgray ^ $past(rgray)));
	 
    // One changed bit is necessary but not sufficient: it could be the wrong bit.
    // These two check that the gray counter always equals gray(binary counter)
    // = b ^ (b >> 1).
      chk_wgray_correct_encoding:
        assert property (@(posedge w_clk) disable iff (!wrst_n)
                         (wgray == (wbin ^ (wbin >> 1))));

      chk_rgray_correct_encoding:
        assert property (@(posedge r_clk) disable iff (!rrst_n)
                         (rgray == (rbin ^ (rbin >> 1))));

	 
    // COVERS: the FIFO can fill from empty and drain from full
	    cov_full_after_empty:
	      cover property (@(posedge w_clk) disable iff (!wrst_n)
			      empty ##[1:$] full);
	       cov_empty_after_full:
	      cover property (@(posedge w_clk) disable iff (!wrst_n)
			      full ##[1:$] empty);

// HOLD: no accepted write -> w_ptr must not change
      chk_fv_same_w_ptr_on_no_write:
	assert property (@(posedge w_clk) disable iff (!wrst_n)
			 !wr_fire |=> ($past(w_ptr)== w_ptr));
	 
// HOLD: no accepted write -> wbin must not change
	 chk_fv_same_wbin_on_no_write:
	   assert property (@(posedge w_clk) disable iff (!wrst_n)
			    !wr_fire |=> ($past(wbin) == wbin));
	    
// HOLD: no accepted read -> r_ptr must not change
	 chk_fv_same_r_ptr_on_no_read:
	   assert property (@(posedge r_clk) disable iff (!rrst_n)
			    !rd_fire |=> ($past(r_ptr) == r_ptr));
	    
// HOLD: no accepted read -> rbin must not change
	 chk_fv_same_rbin_on_no_read:
	   assert property (@(posedge r_clk) disable iff (!rrst_n)
			    !rd_fire |=> ($past(rbin) == rbin));
	    
// cover: the scoreboard captures the tagged word
	 cov_fv_data_captured:
	   cover property (@(posedge w_clk)
			   ((tag == wr_seq)&& wr_fire) ##1 valid); // (the engine reports the shortest trace it finds for a cover) 
	    
// cover: the tagged word is read back (the moment chk_data_match checks)
	 cov_fv_data_checked:
	   cover property (@(posedge r_clk)
			   (tag == rd_seq) && rd_fire);
	    
// (A "second lap" cover -- the same tag checked twice -- exists only in the
//  baseline-FIFO checker, as cov_fv_check_second_lap.)
// cover: the write index makes a full lap: written at 0, moves to 1, and later
// comes back to 0, so the 15 -> 0 wrap is exercised
	 cov_fv_wptr_wrap:
	   cover property (@(posedge w_clk) disable iff (!wrst_n)
			   w_ptr == 4'b0 && wr_fire ##1 w_ptr == 4'b1 ##[0:$] w_ptr == 4'b0);
	    
	    
// cover: the same full lap on the read side
	 cov_fv_rptr_wrap:
	   cover property (@(posedge r_clk) disable iff (!rrst_n)
			   r_ptr == 4'b0 && rd_fire ##1 r_ptr == 4'b1 ##[0:$] r_ptr == 4'b0);
	    
logic [SEQW-1:0] occ;
assign occ = wr_seq - rd_seq;        // fill level from port events; SEQW=5 (set by the bind) > 16 entries, so no ambiguity

localparam int SYNC_LAT = 3;
	    


// BOUNDED RESPONSE: a flag that is on while the FIFO is not truly empty/full
// must clear within SYNC_LAT clocks of its own domain.
// empty belongs to the read clock domain, so it is checked on r_clk.
chk_fv_empty_deasserts_within_sync_lat:
  assert property (@(posedge r_clk) disable iff (!rrst_n)
    (empty && (occ != 0)) |-> ##[1:SYNC_LAT] !empty);

// full belongs to the write clock domain, so it is checked on w_clk.
chk_fv_full_deasserts_within_sync_lat:
  assert property (@(posedge w_clk) disable iff (!wrst_n)
    (full && (occ != DEPTH)) |-> ##[1:SYNC_LAT] !full);

// FLAGS vs TRUE FILL LEVEL: truly empty -> empty, truly full -> full.
// A late (synchronised) pointer only makes a flag more cautious, so these hold
// at all times.
chk_fv_empty_when_occ_zero:
  assert property (@(posedge r_clk) disable iff (!rrst_n) (occ == 0)     |-> empty);
chk_fv_full_when_occ_depth:
  assert property (@(posedge w_clk) disable iff (!wrst_n) (occ == DEPTH) |-> full);

endmodule
