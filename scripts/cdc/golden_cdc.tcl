#=============================================================================
#  golden_cdc.tcl -- Jasper CDC App run on the GOLDEN async FIFO
#
#  DUT : golden_fifo/golden_afifo.sv, top "gold_top"
#        depth 16 (AW=4, DW=8), gray-coded pointers, 2-FF synchronizers,
#        registered read (data_out <= mem[r_ptr]).
#  Run : jg -cdc scripts/cdc/golden_cdc.tcl      (from anywhere in the repo)
#  Out : docs/cdc/golden_{setup,violations,properties,waivers,signoff}.txt
#                 golden_pairs.csv
#
#  RTL ONLY -- the FPV checker and its bind are deliberately NOT analyzed here.
#  The checker's scoreboard adds w_clk flops feeding r_clk properties, which
#  would appear as extra CDC crossings in the structural phase and bury the
#  design's own crossings in testbench noise.
#
#  EXPECTED RESULT (diff against this when something changes):
#    setup violations ....... 2   (PRT_IS_UNCK on w_clk / r_clk themselves)
#    CDC pairs .............. 18  (wgray->wq1, rgray->rq1, mem[0..15]->data_out)
#    scheme ................. 1 FIFO, Detection Type = Automatic
#    protocol checks ........ 2 proven (ours), 2 cex (built-in, waived below)
#    open items ............. WCDC238 x2, PRT_IS_UNCK x2  -- see docs
#    assumption ............. resets declared -synchronized (see section 2)
#=============================================================================

clear -all
set ROOT [exec git rev-parse --show-toplevel]
puts "ROOT = $ROOT"

analyze -sv09 $ROOT/golden_fifo/golden_afifo.sv
elaborate -top gold_top

#-----------------------------------------------------------------------------
# 1. CLOCKS
#-----------------------------------------------------------------------------
# Declaring the clocks only tells the tool where the clock trees are; it says
# NOTHING about their relationship.
config_rtlds -clock -create w_clk
config_rtlds -clock -create r_clk

# The tool defaults to STA mode (all_clocks_sync_by_default = true): every
# declared clock is assumed SYNCHRONOUS to every other one. With that default
# the two domains count as one family, no path qualifies as a crossing, and
# the run reports 0 pairs / 0 violations -- a clean-looking report that
# checked nothing. Switching to async mode is what makes this analysis exist.
config_rtlds -rule -parameter {all_clocks_sync_by_default = false}

#-----------------------------------------------------------------------------
# 2. RESETS -- declared as asynchronously asserted, synchronously de-asserted
#-----------------------------------------------------------------------------
# INTEGRATION ASSUMPTION (must be discharged at the next level up):
#   wrst_n and rrst_n arrive already synchronized to w_clk and r_clk
#   respectively -- asserted asynchronously, released synchronously to the
#   destination clock.
#
# This block contains no reset synchronizer: both resets drive the flops'
# async reset pins directly. Asserting async is safe; RELEASING async is not
# -- a release close to a clock edge can violate recovery/removal timing, so
# flops may go metastable or leave reset in different cycles. Unlike the
# push/pop checks, there is no internal guard here to assert instead, so the
# obligation genuinely belongs to whoever drives these resets.
#
# Declaring them -async (assert AND release asynchronous) is the pessimistic
# model and produces RST_NO_SYNC on all 10 reset-domain crossings. Declaring
# the synchronized type states the contract instead. The integrator must
# verify it: the reset controller must synchronize each reset's release to
# the destination clock before it reaches this block.
config_rtlds -reset -synchronized wrst_n -clock w_clk_n0 -polarity low
config_rtlds -reset -synchronized rrst_n -clock r_clk_n1 -polarity low

#-----------------------------------------------------------------------------
# 3. FIFO RECOGNITION
#-----------------------------------------------------------------------------
# fifo_detection defaults to FALSE. Without it the tool matches
# mem[i] -> data_out to a generic mux/enable scheme and generates a
# data-stability check ("the selected word must not change while the capture
# enable is high"). A correct FIFO fails that: back-to-back reads advance
# r_ptr, so the read-mux output legitimately changes -> DAT_NO_STBL CEX on a
# good design. With detection on, all 18 pairs collapse into one FIFO scheme
# and the right checks (push-on-full / pop-on-empty) are generated instead.
config_rtlds -rule -parameter {fifo_detection = true}

#-----------------------------------------------------------------------------
# 4. GRAY-CODE SIGNAL CONFIG -- intentionally ABSENT
#-----------------------------------------------------------------------------
# config_rtlds -signal -gray_code {wgray rgray} was removed for two reasons:
#
#  (a) It is inert here. It existed to auto-waive the CNV_ST_CONV convergence
#      violations at full/empty, but with fifo_detection=true those violations
#      no longer appear (the FIFO scheme owns those pointers). Verified: the
#      violation report is byte-identical with and without it.
#
#  (b) Declaring both pointers in ONE command builds a single expression over
#      the CONCATENATION:
#        ##1 $changed({rgray,wgray}) |-> $onehot({rgray,wgray} ^ $past(...))
#      A sampling instant in which each pointer advances one bit then shows
#      two set bits and fails, although both behaved correctly. If it is ever
#      needed, declare them one per command.
#
# NOTE FOR THE STUDENT RTL: the tool BELIEVES signal configurations, it does
# not prove them. There the wrap gray(53)->gray(9) changes two bits, so
# declaring those pointers gray-coded would assert something false and
# auto-waive the very convergence violation that exposes it. Do not declare
# gray coding there; let FPV chk_wgray_onehot0 / chk_rgray_onehot0 decide.

#-----------------------------------------------------------------------------
# 5. PORT CLOCK / RESET RATINGS
#-----------------------------------------------------------------------------
# A primary port has no internal flop to infer a domain from, so the tool
# cannot tell whether a path through it crosses domains -> PRT_IS_UNCK.
# This is the CDC equivalent of the FPV "clock -rate {w_en data_in} w_clk".
# The -clock argument takes the clock NAME (w_clk_n0), not the signal name.
# Effect: setup violations 7 -> 2 (the two left are the clock ports themselves,
# the "port used as both clock and data" case).
# These ratings constrain input behaviour, so they could over-constrain;
# :noConflict / :noDeadEnd proven and :live covered confirm they do not.
config_rtlds -port {w_en data_in} -clock w_clk_n0
config_rtlds -port {r_en}         -clock r_clk_n1
config_rtlds -port {w_ptr}        -clock w_clk_n0
config_rtlds -port {r_ptr}        -clock r_clk_n1

config_rtlds -port {w_en data_in w_ptr} -reset wrst_n
config_rtlds -port {r_en r_ptr}         -reset rrst_n

#-----------------------------------------------------------------------------
# 6. STRUCTURAL ANALYSIS
#-----------------------------------------------------------------------------
# -setup   : build the netlist, paint clock domains, bookkeep resets
# -extract : find crossings, match synchronizer schemes, run the
#            around-the-scheme checks (convergence, glitch, reset release)
#
# NOTE: a user-defined scheme (check_cdc -scheme -add fifo -module ... -map)
# was tried and rejected. Every -map entry must be a PORT of the module
# (WCDC113), so neither an expression nor an internal net is accepted, and one
# bad entry silently drops the whole map (WCDC115) with a fallback to
# automatic detection. A map that IS accepted describes the module as a black
# box and loses Wptr/Rptr, the Q1 flops and the NDFF chains. For a design
# whose internals are the subject of verification, automatic detection wins.
check_cdc -setup
check_cdc -extract

#-----------------------------------------------------------------------------
# 7. SANITY CHECK -- fail loudly instead of reporting a false clean
#-----------------------------------------------------------------------------
# The zero-pairs failure above looks identical to a clean result, so assert
# the expectation rather than eyeballing it. Predicted crossings:
#   wgray -> wq1 (5b), rgray -> rq1 (5b), mem[0..15] -> data_out (8b each).
puts "clock_synchronicity: \[[check_cdc -list clock_synchronicity]\]  (empty = no clocks declared synchronous)"
set pairs [check_cdc -list pairs]
puts "CDC pairs found: [dict size $pairs]  (expected 18)"
if {[dict size $pairs] == 0} {
    puts "ERROR: zero CDC pairs -- clocks treated as synchronous?"
} elseif {[dict size $pairs] != 18} {
    puts "WARNING: pair count changed from the documented baseline of 18."
}

#-----------------------------------------------------------------------------
# 8. CUSTOM PROTOCOL CHECKS  (the core of this run)
#-----------------------------------------------------------------------------
# The built-in POP_ON_EMTY / PSH_ON_FULL map Rinc/Winc to the RAW REQUEST
# ports r_en / w_en, so they ask an ENVIRONMENT question: "does anyone ever
# request a read while empty?" Both CEX on this correct FIFO, because the
# environment is free to make such a request and this FIFO's contract allows
# it -- the guard is inside the design:
#     rbin_next = rbin + (r_en & ~empty);
#
# The DESIGN question is "does such a request do anything?". We add it as our
# own protocol check. -protocol_check -add takes an SVA template written
# against the scheme's FORMAL signals (%rinc, %rempty, %rptr, ...), which the
# tool resolves from the AUTO-DETECTED connection map -- so %rptr reaches the
# internal net rgray without the port restriction that blocks -scheme -map.
#
# Why this is not a disguised assumption: an assumption deletes traces from
# the proof (assuming !(r_en && empty) would make student Bug 3 unreachable).
# This adds no constraint; it asserts and proves the design's own guard.
#
# Why it transfers: the condition is "the pointer did not move", not "the
# guard expression is true", so it is not a tautology. Student Bug 3
# (b_rptr_next = (b_rptr==0x36) ? 0x09 : b_rptr + (r_en & ~empty) -- the wrap
# branch is ungated) moves the pointer while empty and should CEX here.
#
# Must be added BEFORE -generate, which instantiates them per scheme.
check_cdc -protocol_check -add no_pop_on_empty \
  -expression {@(posedge %dclk) (%rinc && %rempty) |=> $stable(%rptr)} \
  -scheme fifo

check_cdc -protocol_check -add no_push_on_full \
  -expression {@(posedge %sclk) (%winc && %wfull) |=> $stable(%wptr)} \
  -scheme fifo

#-----------------------------------------------------------------------------
# 9. FUNCTIONAL ANALYSIS
#-----------------------------------------------------------------------------
# Expected: CDC_data_out_no_pop_on_empty  proven
#           CDC_data_out_no_push_on_full  proven
#           CDC_data_out_no_read_on_empty cex  (1 cycle)
#           CDC_data_out_no_write_on_full cex  (17 cycles = 16 writes + 1)
#
# KNOWN GAP (WCDC238 x2): CDC_data_out_put_not_stable / get_not_stable are not
# generated, "Unable to determine clock". The auto-detected map binds Rdata
# but not Wdata -- data_in never crosses a clock domain in this RTL, it is
# captured by mem[] in the write domain. Read-side data stability is covered
# on the FPV side by chk_fv_stable_dout.
check_cdc -protocol_check -generate
check_cdc -protocol_check -prove

#-----------------------------------------------------------------------------
# 10. WAIVERS for the two built-in request-side checks
#-----------------------------------------------------------------------------
# No built-in waiver reason exists for POP_ON_EMTY / PSH_ON_FULL
# (check_cdc -list waiver_reasons), so check_cdc -waiver -generate never even
# attempts them and SEE_COMMENTS is the only reason available. SEE_COMMENTS
# waivers are Unvalidatable by design -- acceptable ONLY because the comment
# cites properties proven in this same session. A waiver backed by a proof
# discharges the obligation elsewhere; an assumption would delete it.
#
# Do NOT run "check_cdc -waiver -prove" here: it switches the session to
# both-edge clock sampling (WCDC250) and invalidates the proof results above,
# and there is nothing to prove for an Unvalidatable reason.
set f_pop [check_cdc -filter -add -tag POP_ON_EMTY]
set f_psh [check_cdc -filter -add -tag PSH_ON_FULL]

check_cdc -waiver -add -reason SEE_COMMENTS -filter $f_pop \
  -comment {Rinc maps to the raw request port r_en, so this check asks whether the environment ever requests a read while empty. The FIFO guards pops internally (rbin_next = rbin + (r_en & ~empty)), so a request on empty has no effect. Proven in this session by CDC_data_out_no_pop_on_empty.}

check_cdc -waiver -add -reason SEE_COMMENTS -filter $f_psh \
  -comment {Winc maps to the raw request port w_en; same reasoning on the write side. Proven in this session by CDC_data_out_no_push_on_full.}

#-----------------------------------------------------------------------------
# 11. REPORTS  (after the waivers, so they show as Waived rather than Error)
#-----------------------------------------------------------------------------
file mkdir $ROOT/docs/cdc

# how the tool understood clocks, resets, port ratings and rule parameters
check_cdc -report -setup     -file $ROOT/docs/cdc/golden_setup.txt      -force

# structural + functional violations, including waived ones
check_cdc -report -violation -detailed -file $ROOT/docs/cdc/golden_violations.txt -force

# every generated property and its status
check_cdc -report -property  -file $ROOT/docs/cdc/golden_properties.txt -force

# waivers with their comments and the checks they cover
check_cdc -report -waiver -detailed -file $ROOT/docs/cdc/golden_waivers.txt -force

# single bundled artifact: statistics + config + violations + waivers
check_cdc -report -signoff   -file $ROOT/docs/cdc/golden_signoff.txt    -force

# the crossing list, to compare against the predicted crossings
check_cdc -list pairs -file $ROOT/docs/cdc/golden_pairs -force

puts "CDC run complete. Reports in docs/cdc/."
puts "Open items: WCDC238 x2 (put/get not_stable not generated), PRT_IS_UNCK x2 (clock ports)."
puts "Integration assumption: wrst_n/rrst_n declared -synchronized (async assert, sync release)."
