//=============================================================================
// fv_afifo_helpers -- helper properties (invariants) that let the formal engine
//                     prove chk_data_match
//
// THE PROBLEM THEY SOLVE
//   chk_data_match (in fv_afifo.sv) is an end-to-end, "black-box" check: it only
//   looks at the FIFO's ports. To prove it, the engine has to work out by itself
//   how the checker's bookkeeping (tag, wr_seq, rd_seq, data_tracked) lines up
//   with the design's internals (b_wptr, b_rptr, the memory f_mem). Here that is
//   awkward: the checker's counters wrap every 64 (mod 2**SEQW) while the
//   pointers wrap every 46 (9..54), so the slot holding the tagged word is not a
//   simple function of the tag. Left alone, the engine ran 17 h and stopped at
//   bound 117 with no answer.
//
// THE IDEA
//   An "invariant" is a statement that is true in every reachable state. These
//   four invariants spell out the missing relationship, one step at a time, so
//   that each is easy to prove once the previous ones are known. They are
//   "white-box" because they look at RTL internals (memory, pointers).
//   fv_afifo.sv itself is NOT modified; this module only reads its signals
//   (connected by scripts/afifo/fv_afifo_helpers_bind.sv).
//
// PROOF CHAIN (each step may assume the steps above it; nothing is circular)
//   F  chk_fv_full_when_occ_depth, chk_fv_empty_when_occ_zero   (proven on their own)
//   H_range  pointers stay inside 9..54
//   H_occ    occupancy counted at the ports == distance between the pointers   needs F
//   H_mem    while the tagged word is in the FIFO, its slot holds that word    needs F, H_occ
//   H_post   right after the tagged read, data_out == the tagged word          needs F, H_occ, H_mem
//   chk_data_match                                                             needs H_post
//   The run scripts prove the steps in this order with `prove -with_proven`,
//   which lets each stage use the properties already proven. Using a proven
//   property as an assumption is sound: it is true on every reachable trace.
//
// WHY EVERY INVARIANT IS CHECKED ON BOTH CLOCKS
//   An assertion is only sampled on its own clock edge. With two independent
//   clocks, every state is seen just before the next edge of one clock or the
//   other, so checking on both edges covers every state. A one-clock version
//   would leave gaps that the proof could not rely on.
//
// RESULTS (2026-11-11, deimos, Jasper 2026.06; baseline FIFO RTL with the Bug 6 fix)
//   DW=1 and DW=8: H_range, H_occ, H_mem, H_post and chk_data_match all proven
//   unbounded (chk_data_match 0.015 s / 0.048 s), 38/38 covers reached.
//   Reports: docs/runs/afifo_helpers_dw1*.txt, docs/runs/afifo_helpers_dw8*.txt.
//   Golden-first run on gold_top: scripts/golden/golden_helpers.tcl.
//   Origin: branch fv/data-match-helpers (commit a7a1976), merged into main.
//=============================================================================

module fv_afifo_helpers #(
  parameter int DW      = 8,
  parameter int AW      = 6,
  parameter int SEQW    = 6,
  parameter int DEPTH   = 46,   // number of slots = PTR_MAX - PTR_MIN + 1 (46 baseline, 16 golden)
  parameter int DEPTH_EFF = 45, // usable entries (45 baseline, 16 golden)
  parameter int PTR_MIN = 9,
  parameter int PTR_MAX = 54
)(
  input logic            w_clk, wrst_n,
  input logic            r_clk, rrst_n,
  // design (RTL) signals, read through the bind
  input logic [AW-1:0]   b_wptr, b_rptr,
  input logic [DW-1:0]   data_out,
  // The memory is passed in whole. Unpacked arrays connect BY POSITION, not by
  // index number, so this port must be declared in the same direction as the
  // design's array or slot k here would be some other slot in the RTL:
  //   baseline FIFO rtl/fifo_mem.sv : f_mem [54:9]  (descending) -> default
  //   golden  golden_afifo.sv : mem   [0:15]  (ascending)  -> +define+FV_MEM_ASCENDING
`ifdef FV_MEM_ASCENDING
  input logic [DW-1:0]   f_mem [PTR_MIN:PTR_MAX],
`else
  input logic [DW-1:0]   f_mem [PTR_MAX:PTR_MIN],
`endif
  // the contract checker's scoreboard signals (read only, never driven)
  input logic [SEQW-1:0] tag, wr_seq, rd_seq,
  input logic [DW-1:0]   data_tracked,
  input logic            valid
);

   logic rst_any;
   assign rst_any = !wrst_n || !rrst_n;

   // fill level counted from port events, computed exactly as fv_afifo does
   logic [SEQW-1:0] occ;
   assign occ = wr_seq - rd_seq;

   // how many reads must happen before the tagged entry comes out (mod 2**SEQW)
   logic [SEQW-1:0] ahead;
   assign ahead = tag - rd_seq;

   // true when the tagged entry has been written and not yet read
   logic in_flight;
   assign in_flight = (ahead < occ);

   // Move a pointer forward by `off` slots around the ring, wrapping past PTR_MAX
   // back to PTR_MIN. Correct for off <= DEPTH (one wrap at most), which always
   // holds here because no more than DEPTH_EFF entries are ever in flight.
   function automatic logic [AW-1:0] ptr_add(input logic [AW-1:0]   p,
                                             input logic [SEQW-1:0] off);
      logic [AW+1:0] s;
      s = p + off;
      if (s > PTR_MAX) s = s - DEPTH;
      return s[AW-1:0];
   endfunction

   // the slot the tagged entry sits in: `ahead` slots after the read pointer
   logic [AW-1:0] slot;
   assign slot = ptr_add(b_rptr, ahead);

   // read that slot, guarded so an out-of-range index never reaches the array
   logic [DW-1:0] mem_at_slot;
   assign mem_at_slot = (slot >= PTR_MIN && slot <= PTR_MAX) ? f_mem[slot] : '0;

`define FV_HELPER(name, expr)                                              \
   name``_w: assert property (@(posedge w_clk) disable iff (rst_any) expr); \
   name``_r: assert property (@(posedge r_clk) disable iff (rst_any) expr)

   // H_range: the pointers never leave 9..54 (also covers behaviour B18)
   `FV_HELPER(H_range,
              (b_wptr >= PTR_MIN && b_wptr <= PTR_MAX &&
               b_rptr >= PTR_MIN && b_rptr <= PTR_MAX));

   // H_occ: at most DEPTH_EFF entries are ever stored, and moving forward from the
   // read pointer by the fill level lands exactly on the write pointer
   `FV_HELPER(H_occ,
              (occ <= DEPTH_EFF && ptr_add(b_rptr, occ) == b_wptr));

   // H_mem: while the tagged entry is stored, the scoreboard has captured it AND
   // the memory slot it occupies still holds exactly that value (nothing has
   // overwritten it). This is the step that ties the checker to the memory.
   `FV_HELPER(H_mem,
              in_flight |-> (valid && mem_at_slot == data_tracked));

   // H_post: right after the tagged entry is read (and before the next read),
   // data_out holds the captured value. chk_data_match looks one read clock later
   // (|=>); any number of write clocks may tick in between, and this helper property covers
   // that gap.
   `FV_HELPER(H_post,
              (valid && rd_seq == SEQW'(tag + 1'b1)) |-> (data_out == data_tracked));

`undef FV_HELPER

   // Covers (reachability checks), so the helper properties are not passing vacuously:
   //   deep    : the tagged entry is in flight with DEPTH_EFF-1 entries ahead of it
   //   wrapped : the tagged entry sits past the 54 -> 9 wrap (slot below read pointer)
   //   post    : the "just read" state that H_post talks about happens
   cov_h_in_flight_deep:
     cover property (@(posedge r_clk) disable iff (rst_any)
                     in_flight && ahead == DEPTH_EFF - 1);
   cov_h_in_flight_wrapped:
     cover property (@(posedge r_clk) disable iff (rst_any)
                     in_flight && slot < b_rptr);
   cov_h_post:
     cover property (@(posedge r_clk) disable iff (rst_any)
                     valid && rd_seq == SEQW'(tag + 1'b1));

endmodule
