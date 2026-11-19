//=============================================================================
// fv_afifo -- the CONTRACT CHECKER for the baseline asynchronous FIFO
//             (design in rtl/, top module `top`)
//
// WHAT THIS FILE IS
//   A set of SystemVerilog Assertions (SVA) that describe how a correct
//   asynchronous FIFO must behave. Jasper's formal engine (FPV = Formal Property
//   Verification) does not simulate test vectors. It reasons about EVERY possible
//   input sequence at once and returns, for each property:
//     - "proven"     : true for every reachable state, forever ("unbounded proof",
//                      reported as bound = Infinite)
//     - "cex"        : a counterexample, i.e. a concrete waveform that breaks it
//     - "undetermined" with a bound N : no failure within N clock cycles, but no
//                      full proof either (inconclusive)
//
//   Three kinds of SVA statements appear below:
//     assert property : something the DESIGN must always do (checked)
//     cover  property : a scenario that must be REACHABLE. A cover that cannot be
//                       hit means some assertion may pass only because its
//                       trigger never happens ("vacuous" pass).
//     assume property : a restriction on the INPUTS that the engine takes as
//                       given. Assumptions are dangerous because they can hide
//                       bugs, so this file has exactly one (the stable tag, below),
//                       and it constrains only a checker-internal variable,
//                       never the FIFO's own inputs.
//
//   The checker is attached to the design with a `bind` statement
//   (scripts/afifo/fv_afifo_bind.sv). Bind inserts this module inside `top`
//   without editing the RTL, so rtl/ stays exactly as the designers wrote it.
//
// WHERE IT CAME FROM
//   Ported from fv/fv_golden_afifo/fv_golden_afifo.sv, which is proven 22/22 on
//   the golden reference FIFO (gold_top). Project rule ("golden-first"): a
//   property is trusted on the baseline FIFO only after it has passed on the
//   known-good golden FIFO, so that a failure here points at the design, not at
//   a mistake in the checker.
//
// DESIGN FACTS THIS CHECKER ENCODES (from reading the RTL)
//   - Binary pointers b_wptr/b_rptr are 6 bits, reset to 9, and count
//     9, 10, ..., 54, then wrap back to 9. That is 46 values = 46 memory slots.
//   - full = (b_wptr_next == b_rptr_sync): the FIFO reports full one slot early,
//     so one slot is always left empty and 45 entries are usable (DEPTH_EFF=45).
//   - Each side converts its pointer to gray code and sends it to the other
//     clock domain through a 2-flop synchroniser.
//   - empty is a REGISTERED flag (one extra flop after the synchroniser), full is
//     COMBINATIONAL. So after a crossing, empty can lag by 3 read clocks and full
//     by 2 write clocks (SYNC_LAT_R / SYNC_LAT_W below).
//
// GRAY-CODE CHECKS ARE NOT TAILORED TO THIS DESIGN, ON PURPOSE
//   chk_*gray_onehot0 are written exactly as on the golden FIFO. An early
//   suspicion (Bug 4) was that the 54 -> 9 wrap changes two gray bits. It was
//   REFUTED: gray(54) = 101101 and gray(9) = 001101 differ in one bit only, and
//   both properties are proven.
//
// RESULTS SO FAR (details: docs/runs/, see docs/runs/README.md)
//   baseline RTL (tag baseline-renamed) : 13/20 assertions proven, 7 CEX
//   after fixes for Bugs 1, 1b, 3, 5    : 19/20 proven, chk_data_match bounded
//   with the helper properties (fv_afifo_helpers.sv) : 20/20, chk_data_match proven
//                                          at DW=1 and DW=8
//=============================================================================

module fv_afifo #(
  parameter int DW      = 8,
  parameter int AW      = 6,    // pointer width in bits. NOT log2(depth): the pointers run 9..54
  parameter int SEQW    = 6,    // width of the checker's sequence counters; needs 2**SEQW > 45 entries in flight, so 6
  parameter int DEPTH   = 46,   // number of memory slots = number of pointer values (9..54)
  parameter int DEPTH_EFF = 45, // usable entries: full is flagged one slot early, so 46 - 1 = 45
  parameter int PTR_MIN = 9,
  parameter int PTR_MAX = 54
)(
  input logic          w_clk, wrst_n, w_en, full,
  input logic [DW-1:0] data_in,
  input logic [AW-1:0] b_wptr,             // binary write pointer; also the memory slot being written
  input logic [AW-1:0] g_wptr,             // gray-coded write pointer: the value that crosses to the read clock
  input logic          r_clk, rrst_n, r_en, empty,
  input logic [DW-1:0] data_out,
  input logic [AW-1:0] b_rptr,             // binary read pointer
  input logic [AW-1:0] g_rptr              // gray read pointer
);

   // How many clock edges a flag may lag behind the true fill level after the
   // other side has moved. A synchroniser is 2 flops in a row that safely bring a
   // signal from one clock domain into another; each flop costs one edge.
   localparam int SYNC_LAT_R = 3;   // read side: 2 sync flops + the registered empty flop = 3
   localparam int SYNC_LAT_W = 2;   // write side: 2 sync flops, full is combinational = 2

   // The design's own "next pointer" rule: 9, 10, ..., 54, then back to 9.
   // Used by chk_wrptr / chk_rptr to say exactly where a pointer must go next.
   function automatic logic [AW-1:0] next_ptr(input logic [AW-1:0] p);
      return (p == AW'(PTR_MAX)) ? AW'(PTR_MIN) : p + 1'b1;
   endfunction

   logic wr_fire, rd_fire;
   assign wr_fire = w_en && !full;
   assign rd_fire = r_en && !empty;


// wr_fire / rd_fire: a write or read the FIFO actually ACCEPTS. A request
// (w_en / r_en) made while full / empty is legal at the interface but must
// have no effect; many properties below depend on that distinction.

//==========================================================
// --reset--  what must be true right after reset is released
//==========================================================

      // The FIFO must say "empty" as reset is released.
      // (This passed even on the baseline RTL. Bug 1 -- the synchroniser reset to 0
      //  instead of gray(9) -- was caught two cycles later by chk_fv_empty_when_occ_zero.)
      chk_fv_empty_after_reset:
	assert property (@(posedge r_clk)
		      $rose(rrst_n) |-> empty);

      // The FIFO must not say "full" as reset is released.
      chk_fv_no_full_after_reset:
	assert property (@(posedge w_clk)
		      $rose(wrst_n) |-> !full);

      // data_out may only change on an accepted read. |=> means "on the next clock
      // edge"; $stable means "same value as on the previous edge".
      chk_fv_stable_dout:
	assert property (@(posedge r_clk) disable iff (!rrst_n)
			 !rd_fire |=> $stable(data_out));

  // end of reset checks

//=================================================================
// DATA INTEGRITY with a "symbolic tag" scoreboard
//
// Goal: prove that every accepted word comes out once, in order, unchanged.
// Tracking every word would need a model of the whole FIFO. Instead:
//   - wr_seq counts accepted writes and rd_seq counts accepted reads.
//   - `tag` is a value that nothing drives. The formal engine therefore treats
//     it as "any value at all" (a SYMBOLIC value), and a proof must hold for
//     every possible tag.
//   - The word written when wr_seq == tag is copied into data_tracked.
//   - When rd_seq == tag, the word read out must equal data_tracked.
// Because the tag can be anything, this one check covers every write: right
// data (integrity), right order (the Nth write is the Nth read), nothing lost,
// and nothing read twice.
//=================================================================

	 // the symbolic tag: undriven on purpose, so the engine may pick any value
	 logic [SEQW-1:0] tag;

	 // The project's ONLY assumption: the tag never changes during a run. Without
	 // it the engine could switch the tag mid-run and invent failures. It restricts
	 // a checker variable only, not any FIFO input, so it cannot hide a design bug.
	 chk_fv_asm_stable_tag:
	   assume property ($stable(tag));

	 // Sequence counters owned by the checker, built only from the FIFO's ports.
	 // They are independent of the RTL pointers, so a pointer bug cannot fool them.
	    logic [SEQW-1:0] wr_seq, rd_seq;

	    // +1 on every accepted write (wraps at 2**SEQW = 64)
	    always_ff @(posedge w_clk or negedge wrst_n) begin
	       if(!wrst_n)
		 wr_seq <= '0;
	       else if (wr_fire)
		 wr_seq <= wr_seq + 1'b1;
	    end

   // +1 on every accepted read
   always_ff @(posedge r_clk or negedge rrst_n) begin
      if(!rrst_n)
	rd_seq <= '0;
      else if (rd_fire)
	rd_seq <= rd_seq + 1'b1;
   end

   // data_tracked = copy of the word that was written when wr_seq == tag;
   // valid = that capture has happened at least once
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

   // occ = how many entries are in the FIFO right now, counted from port events
   // only (writes minus reads). With 6-bit counters and at most 45 entries in
   // flight, the subtraction never wraps ambiguously.
   logic [SEQW-1:0] occ;
   assign occ = wr_seq - rd_seq;

   // THE main data property. When the tagged entry is read, data_out on the next
   // read clock (data_out is registered, hence |=>) must equal the captured word.
   // Status: proven with the helper properties in fv_afifo_helpers.sv (DW=1 and DW=8).
   // Without them the engine cannot close it (bound 117 after 17 h): it has to
   // discover on its own how the mod-64 counters line up with the mod-46 pointers.
   chk_data_match:
     assert property (@(posedge r_clk) disable iff (!rrst_n)
		      (rd_seq == tag && rd_fire && valid) |=> (data_tracked == data_out));

//=================================================================
// POINTER STEP / HOLD -- each pointer moves by exactly one, and only when it should
//=================================================================
      // STEP: an accepted transfer moves the pointer to exactly its successor,
      // including the wrap 54 -> 9. Uses next_ptr() rather than "+1" (as on the
      // golden FIFO) because this design's range is 9..54, not 0..2**AW-1.
      chk_wrptr:
	assert property (@(posedge w_clk) disable iff (!wrst_n)
			 wr_fire |=> (b_wptr == next_ptr($past(b_wptr))));

      chk_rptr:
	assert property (@(posedge r_clk) disable iff (!rrst_n)
			 rd_fire |=> (b_rptr == next_ptr($past(b_rptr))));

     // GUARD: a request while full / empty must not move the pointer.
     // chk_no_increment_when_empty caught Bug 3 (read pointer wrapped 54 -> 9 even
     // when empty; CEX at 51 cycles on the baseline RTL).
	 chk_no_increment_when_full:
	   assert property (@(posedge w_clk) disable iff (!wrst_n)
			    w_en && full |=> $stable(b_wptr));

	 chk_no_increment_when_empty:
	   assert property (@(posedge r_clk) disable iff (!rrst_n)
			    r_en && empty |=> $stable(b_rptr));

// HOLD: no accepted write -> b_wptr must not change. Written to test the
// suspected write-side twin of Bug 3 (Bug 3b). Proven on the baseline, so Bug 3b
// was refuted: the write wrap is correctly gated.
      chk_fv_same_w_ptr_on_no_write:
	assert property (@(posedge w_clk) disable iff (!wrst_n)
			 !wr_fire |=> ($past(b_wptr) == b_wptr));

// HOLD: no accepted read -> b_rptr must not change. CEX on the baseline (Bug 3).
	 chk_fv_same_r_ptr_on_no_read:
	   assert property (@(posedge r_clk) disable iff (!rrst_n)
			    !rd_fire |=> ($past(b_rptr) == b_rptr));

//=================================================================
// GRAY POINTERS -- what makes the clock-domain crossing (CDC) safe
//
// Gray code is a binary encoding in which consecutive values differ in exactly
// one bit. If a multi-bit value is sampled by another clock just as it changes,
// only that one bit can be caught "half-way", so the receiver sees either the
// old value or the new one, never a random mix. This only works if the pointer
// really does change one bit at a time, which is what is checked here.
//=================================================================
   // At most one bit may change per clock ($onehot0 = zero or one bit set),
   // including at the 54 -> 9 wrap. Written exactly as on the golden FIFO, not
   // adapted to 9..54. Proven: gray(54)=101101 -> gray(9)=001101 is a 1-bit change.
      chk_wgray_onehot0:
	assert property (@(posedge w_clk) disable iff (!wrst_n)
			 $past(wrst_n) |-> $onehot0(g_wptr ^ $past(g_wptr)));

	 chk_rgray_onehot0:
	   assert property (@(posedge r_clk) disable iff (!rrst_n)
			    $past(rrst_n) |-> $onehot0(g_rptr ^ $past(g_rptr)));

    // The gray pointer must equal gray(binary pointer) = b ^ (b >> 1) on every clock.
    // After the Bug 6 fix (g_wptr became a register) this property is what shows the
    // fix changes no signal's value on any cycle: the register always equals the old
    // combinational value.
      chk_wgray_correct_encoding:
        assert property (@(posedge w_clk) disable iff (!wrst_n)
                         (g_wptr == (b_wptr ^ (b_wptr >> 1))));

      chk_rgray_correct_encoding:
        assert property (@(posedge r_clk) disable iff (!rrst_n)
                         (g_rptr == (b_rptr ^ (b_rptr >> 1))));

//=================================================================
// FLAGS vs TRUE OCCUPANCY
// occ is the true fill level, counted from port events only ("black-box").
// The flags see the other side's pointer late (it has to cross a synchroniser),
// but a late pointer can only make a flag more CAUTIOUS: empty may stay on a
// little too long, full may stay on a little too long. So "truly empty -> empty"
// and "truly full -> full" must hold at all times.
//=================================================================
chk_fv_empty_when_occ_zero:
  assert property (@(posedge r_clk) disable iff (!rrst_n) (occ == 0)         |-> empty);
chk_fv_full_when_occ_depth:
  assert property (@(posedge w_clk) disable iff (!wrst_n) (occ == DEPTH_EFF) |-> full);

// BOUNDED RESPONSE -- the converse, stated honestly: a flag that is on while
// the FIFO is not truly empty / full must turn off within the synchroniser
// latency (##[1:N] = within 1 to N clocks). Each is written in its flag's own
// clock domain.
chk_fv_empty_deasserts_within_sync_lat:
  assert property (@(posedge r_clk) disable iff (!rrst_n)
    (empty && (occ != 0)) |-> ##[1:SYNC_LAT_R] !empty);

chk_fv_full_deasserts_within_sync_lat:
  assert property (@(posedge w_clk) disable iff (!wrst_n)
    (full && (occ != DEPTH_EFF)) |-> ##[1:SYNC_LAT_W] !full);

//=================================================================
// COVERS -- prove that the interesting scenarios can actually happen.
// If any of these were unreachable, assertions that depend on them could be
// passing "vacuously" (never triggered). All are covered; the trace length
// (cycles to first hit) is also a sanity check, e.g. filling 45 entries cannot
// take fewer than about 45 write clocks.
//=================================================================
    // the FIFO can go from empty to full, and from full back to empty
	    cov_full_after_empty:
	      cover property (@(posedge w_clk) disable iff (!wrst_n)
			      empty ##[1:$] full);
	    cov_empty_after_full:
	      cover property (@(posedge w_clk) disable iff (!wrst_n)
			      full ##[1:$] empty);

// the scoreboard captures the tagged word (so chk_data_match is not vacuous)
	 cov_fv_data_captured:
	   cover property (@(posedge w_clk)
			   ((tag == wr_seq) && wr_fire) ##1 valid);

// the tagged word is read back (the moment chk_data_match actually checks)
	 cov_fv_data_checked:
	   cover property (@(posedge r_clk)
			   (tag == rd_seq) && rd_fire);

// the same tag is checked twice: rd_seq has wrapped through all 64 values, so
// the proof also covers the counters wrapping and the tag being reused
	 cov_fv_check_second_lap:
	   cover property (@(posedge r_clk) disable iff (!rrst_n)
			   (tag == rd_seq && rd_fire) ##1 (tag != rd_seq)[*1:$] ##1 (tag == rd_seq && rd_fire));

// the 54 -> 9 pointer wrap happens, on both the write and the read side
	 cov_fv_wptr_wrap:
	   cover property (@(posedge w_clk) disable iff (!wrst_n)
			   (b_wptr == AW'(PTR_MAX)) && wr_fire ##1 (b_wptr == AW'(PTR_MIN)));

	 cov_fv_rptr_wrap:
	   cover property (@(posedge r_clk) disable iff (!rrst_n)
			   (b_rptr == AW'(PTR_MAX)) && rd_fire ##1 (b_rptr == AW'(PTR_MIN)));

// the bounded-response limits are TIGHT: a flag really can take exactly
// SYNC_LAT clocks to clear, so the bounds above could not be made smaller
	 cov_fv_empty_bound_tight:
	   cover property (@(posedge r_clk) disable iff (!rrst_n)
			   (empty && (occ != 0)) ##SYNC_LAT_R !empty);
	 cov_fv_full_bound_tight:
	   cover property (@(posedge w_clk) disable iff (!wrst_n)
			   (full && (occ != DEPTH_EFF)) ##SYNC_LAT_W !full);


endmodule
