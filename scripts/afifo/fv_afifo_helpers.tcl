#=============================================================================
# fv_afifo_helpers.tcl -- THE run that proves chk_data_match on the baseline
# FIFO, using the helper properties in fv/fv_afifo/fv_afifo_helpers.sv.
#
# IN ONE PARAGRAPH
#   chk_data_match (every word comes out once, in order, unchanged) is too hard
#   for the engine to prove in one go on this design. This script proves it in
#   small stages: first some facts about the flags (F), then the pointer range
#   and fill level (H_range, H_occ), then "the waiting word is still in memory"
#   (H_mem), then "the word just read is on data_out" (H_post), and finally
#   chk_data_match itself. `prove -with_proven` lets each stage use what the
#   earlier stages proved. Each stage's log line says how many properties were
#   "already proven"; that number must grow (0, 2, 6, 8, 10, 11), which shows
#   the stages really build on each other.
#
# Adapted from the staged proof on branch fv/data-match-helpers (commit a7a1976).
#
# HOW TO RUN
#   cd scripts/afifo && jg -proj jgproject_helpers fv_afifo_helpers.tcl &
#   DW defaults to 8 (the reported width). For the cheap DW=1 run: `set DW 1`, then source.
#   Re-sourcing in an open session: `unset DW` first, or the old value is kept.
#
# Differences from the branch's original staged script (it had the same name):
#   - stage 5 proves a NAMED list, never prove -all (project rule)
#   - set_proofgrid_max_local_jobs 4; no exit (GUI stays open)
#   - set RUN_STAGES 0 before sourcing to only elaborate and run stages by hand:
#       stage F {...}   stage 1 {...}   ...   (proc `stage` is defined either way)
# Runs against the CURRENT rtl/ (includes the Bug 6 fix, uncommitted).
#
# The PREDICTIONS / OUTCOME blocks below are the record of what was expected
# before each run and what happened; they are kept unchanged.
#
# PREDICTIONS for the first run (DW=1), written 2026-11-11 before any run
#   CHECK 1 hierarchical bind ports into tc_checker_inst: elaborates
#   CHECK 2 -with_proven: accepted (probed on a toy design); each stage's log line
#           "N properties to prove with M already proven" must show M > 0
#   stage F proven fast | stage 1 H_range fast, H_occ minutes
#   stage 2 H_mem: the hard step -- proven plausible, NOT certain at default engines
#           (if it stalls: try `prove -property {*H_mem*} -with_proven -engine_mode {G G2 C I}`)
#   stage 3 H_post fast given H_mem | stage 4 chk_data_match fast given H_post
#   covers: all covered; cov_h_in_flight_deep >= ~45 cycles
#
# PREDICTIONS for the rerun after removing the old helper block from fv_afifo.sv
# (written 2026-11-18, before the run; same RTL, same H_* module, same stages):
#   "already proven" sequence 0, 2, 6, 8, 10, 11 (unchanged)
#   28/28 asserts proven (20 checker+embedded, 8 H_*), 0 unprocessed; 38/38 covers
#   every status, bound and trace length identical to the 11-11 runs below
#   reports: overwrite docs/runs/afifo_helpers_dw1*.txt and _dw8*.txt
#
# DW=1 OUTCOME (2026-11-11 20:06, user GUI run, Bug-6-fixed RTL) -- all predictions held
#   stage logs "already proven": 0, 2, 6, 8, 10, 11  (CHECK 2 confirmed)
#   H_range 0.035 s, H_occ 0.22 s, H_mem 1.36 s, H_post 0.06 s, chk_data_match 0.015 s (Hp), all Infinite
#   stage F: proofs ~20 s, but proof thread shut down only at 767 s (unexplained; harmless)
#   28/33 asserts proven, 5 unprocessed = hlp_* (skipped by design); 38/38 covers
#   cover depths: deep 46, wrapped 48, h_post 6, full_after_empty 41-46, empty_after_full 89,
#                 wptr_wrap 47, rptr_wrap 51, second_lap 69, full_bound 48, empty_bound 5
#   reports docs/runs/afifo_helpers_dw1*.txt
#
# PREDICTIONS for DW=8 (written 2026-11-11, before the run)
#   same "already proven" sequence 0, 2, 6, 8, 10, 11
#   H_range, H_occ, H_post, chk_data_match: proven, same order of time as DW=1
#   H_mem: proven, slowest step, slower than 1.36 s; seconds-to-minutes, not hours
#   28/33 proven (5 hlp_* unprocessed), 38/38 covers, depths IDENTICAL to DW=1
#   Any depth change or any non-proven helper REFUTES the bit-slicing argument.
#   reports docs/runs/afifo_helpers_dw8*.txt
#
# DW=8 OUTCOME (2026-11-11 20:35, user GUI run) -- all predictions held
#   H_range 0.032 s, H_occ 0.23 s, H_mem 1.58 s (slowest, as predicted), H_post 0.11 s,
#   chk_data_match 0.048 s (N), all Infinite; 28/33 (5 hlp_* skipped); 38/38 covers
#   all 71 rows identical to DW=1 in status, bound and trace length; the only textual
#   difference is cov_full_after_empty "33 - 46" vs "41 - 46" (lower bound found by
#   the engine; the trace is 46 in both)
#
# PREDICTIONS for the DW=1 rerun after the hlp_* removal (written 2026-11-18,
# before the run; the DW=8 rerun that day gave 28/28 and 34/34 covers)
#   "already proven" sequence 0, 2, 6, 8, 10, 11 (unchanged)
#   28/28 asserts proven, 0 unprocessed; 34/34 covers (38 - 4 hlp_* precondition covers)
#   every status, bound and trace length identical to the 18 Nov DW=8 rerun,
#   except possibly the engine's lower bound on cov_full_after_empty (trace 46)
#   Any other difference REFUTES the bit-slicing argument.
#   reports: overwrite docs/runs/afifo_helpers_dw1*.txt
#
# DW=1 RERUN OUTCOME (2026-11-18 16:55, user GUI run) -- all predictions held
#   "already proven": 0, 2, 6, 8, 10, 11; 28/28 proven, 0 unprocessed; 34/34 covers
#   H_range 0.06 s, H_occ 0.31 s, H_mem 1.06 s, H_post 0.02 s, chk_data_match 0.002 s, all Infinite
#   all 63 rows identical to the DW=8 rerun in status, bound and trace length; the only
#   difference is cov_full_after_empty "31 - 46" vs "40 - 46" (engine lower bound; trace 46)
#   stage F proof thread again shut down late (1095 s; proofs done at 78 s; harmless)
#=============================================================================
clear -all

if {![info exists DW]} { set DW 8 }
if {![info exists RUN_STAGES]} { set RUN_STAGES 1 }
puts "DW = $DW   RUN_STAGES = $RUN_STAGES"

set ROOT [exec git rev-parse --show-toplevel]
puts "ROOT = $ROOT"

#--- RTL (leaf modules first, top last)
analyze -sv09 $ROOT/rtl/fifo_mem.sv
analyze -sv09 $ROOT/rtl/read_ptr.sv
analyze -sv09 $ROOT/rtl/synchronizer.sv
analyze -sv09 $ROOT/rtl/write_ptr.sv
analyze -sv09 $ROOT/rtl/top.sv

#--- contract checker + helper module, then the binds. The checker bind must
#    come first: the helper bind reads the scoreboard out of tc_checker_inst.
analyze -sv12 $ROOT/fv/fv_afifo/fv_afifo.sv
analyze -sv12 $ROOT/fv/fv_afifo/fv_afifo_helpers.sv
analyze -sv12 +define+FV_DW=$DW $ROOT/scripts/afifo/fv_afifo_bind.sv
analyze -sv12 +define+FV_DW=$DW $ROOT/scripts/afifo/fv_afifo_helpers_bind.sv

elaborate -top top -parameter top.data_width $DW

#--- same clocks, resets and input ratings as fv_afifo.tcl, so results compare
clock w_clk
clock r_clk
reset -expression {!wrst_n} {!rrst_n}
clock -rate {w_en data_in} w_clk
clock -rate {r_en} r_clk

set_proofgrid_max_local_jobs 4

proc stage {label patterns} {
   puts "=== stage $label: $patterns ==="
   prove -property $patterns -with_proven
}

if {$RUN_STAGES} {
   stage F {*chk_fv_full_when_occ_depth *chk_fv_empty_when_occ_zero}
   stage 1 {*H_range_w *H_range_r *H_occ_w *H_occ_r}
   stage 2 {*H_mem_w *H_mem_r}
   stage 3 {*H_post_w *H_post_r}
   stage 4 {*chk_data_match}

   puts "=== stage 5: remaining properties (NAMED, not prove -all) ==="
   set rest {}
   foreach p [get_property_list -include {type assert}] {
      if {[string match *chk_data_match* $p]} continue
      if {[get_status $p] ne "proven"} { lappend rest $p }
   }
   foreach p [get_property_list -include {type cover}] { lappend rest $p }
   prove -property $rest -with_proven

   report -summary
   report -summary -force -file $ROOT/docs/runs/afifo_helpers_dw$DW.txt
   report -force -file $ROOT/docs/runs/afifo_helpers_dw${DW}_detail.txt
}
