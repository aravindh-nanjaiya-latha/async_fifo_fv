#=============================================================================
# fv_afifo_bug6.tcl -- FPV regression for fix-bug6 (registered g_wptr).
#
# WHY THIS RUN EXISTS
#   Bug 6 was found by the CDC tool, not by FPV: the gray write pointer was made
#   by combinational XOR logic and fed straight into the synchroniser, which can
#   glitch. The fix turns g_wptr into a register. A fix must not break anything
#   else, so the formal run is repeated on the fixed RTL ("regression") and
#   compared property by property with the run before the fix.
# Same checker (fv/fv_afifo/fv_afifo.sv) and same setup (fv_afifo.tcl, NOPROVE),
# proving by name exactly the 19 contract assertions + 9 covers of the
# after-Bug-5 run (docs/runs/afifo_after_bug5_dw8_bounded.txt). The working-
# tree helper block (hlp_*) is not proven here: it is extra, not part of the
# before/after comparison. chk_data_match is not re-run (argument below).
#
# Run (from repo root):  jg -batch -tcl scripts/afifo/fv_afifo_bug6.tcl -proj <own>
#
# PREDICTIONS (written 2026-11-11, BEFORE the fix is applied)
#   19/19 proven, unbounded -- identical to after-Bug-5.
#   chk_wgray_correct_encoding  PROVEN. This is the load-bearing one: it shows
#     the registered g_wptr == b_wptr ^ (b_wptr>>1) on every reachable cycle, i.e.
#     the fixed design is cycle-equivalent to the pre-fix design on every signal.
#     Hence every earlier result (incl. chk_data_match: bound 117, and the
#     decomposed proof pending review) transfers unchanged, so it is not re-run.
#   chk_wgray_onehot0           PROVEN
#   w_inst._assert_1, r_inst._assert_1 PROVEN
#   9 explicit covers + preconditions: all covered, depths UNCHANGED vs after-Bug-5
#     (equivalent behaviour => same shortest traces).
#   Any change in a cover depth would REFUTE the equivalence claim -> investigate.
# ATTEMPT 1 (2026-11-11, aborted at the precondition step, before the report):
#   19/19 proven; cover depths 2,5,5,69,51 identical; 46,47,48,89 inside the
#   after-Bug-5 ranges (43-46, 44-47, 47-48, 81-91). Predictions held.
#=============================================================================
set NOPROVE 1
set ROOT [exec git rev-parse --show-toplevel]
source $ROOT/scripts/afifo/fv_afifo.tcl
set_proofgrid_max_local_jobs 4

set P tc_checker_inst
set props [list top.w_inst._assert_1 top.r_inst._assert_1]
foreach n {chk_fv_empty_after_reset chk_fv_no_full_after_reset chk_fv_stable_dout
           chk_wrptr chk_rptr chk_no_increment_when_full chk_no_increment_when_empty
           chk_fv_same_w_ptr_on_no_write chk_fv_same_r_ptr_on_no_read
           chk_wgray_onehot0 chk_rgray_onehot0 chk_wgray_correct_encoding chk_rgray_correct_encoding
           chk_fv_empty_when_occ_zero chk_fv_full_when_occ_depth
           chk_fv_empty_deasserts_within_sync_lat chk_fv_full_deasserts_within_sync_lat
           cov_full_after_empty cov_empty_after_full cov_fv_data_captured cov_fv_data_checked
           cov_fv_check_second_lap cov_fv_wptr_wrap cov_fv_rptr_wrap
           cov_fv_empty_bound_tight cov_fv_full_bound_tight} {
  lappend props top.$P.$n
}
prove -property $props
# Every assertion of the form A |-> B also gets an automatic "precondition"
# cover that checks A can happen at all (otherwise the assertion would pass
# vacuously). Prove those too, skipping the hlp_* helper properties.
# (attempt 1 aborted here: get_property_list has no -regexp option -> ECD018 under -batch)
set pre {}
foreach c [get_property_list -include {type cover}] {
  if {[string match *:precondition* $c] && ![string match *hlp_* $c]} { lappend pre $c }
}
prove -property $pre

report -summary -force -file $ROOT/docs/runs/afifo_after_bug6.txt
report -force -file $ROOT/docs/runs/afifo_after_bug6_detail.txt
exit
