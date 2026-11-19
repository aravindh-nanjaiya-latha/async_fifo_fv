#=============================================================================
# golden_helpers.tcl -- GOLDEN-FIRST run of the chk_data_match helper invariants.
#
# Project rule ("golden-first"): a new property is trusted on the baseline FIFO
# only after it is proven on the known-good golden FIFO. If a property fails on
# a design that is known to be correct, the property is wrong, not the design.
# The helpers were proven on the baseline FIFO first (2026-11-11); this run
# closes that gap. Same helper module, same staged proof as
# scripts/afifo/fv_afifo_helpers.tcl; only the design and geometry differ
# (16 slots numbered 0..15, all usable, memory declared [0:15]).
#
# Staged proof: each `stage` proves a few properties with -with_proven, which
# lets them use everything already proven as known facts. The order is
# F -> H_range/H_occ -> H_mem -> H_post -> chk_data_match.
#
# Run (repo root):  jg -batch -tcl scripts/golden/golden_helpers.tcl -proj <own dir>
#        or GUI:    cd scripts/golden && jg -proj jgproject_helpers golden_helpers.tcl &
#
# PREDICTIONS (written 2026-11-11, before the first run)
#   elaboration: OK with +define+FV_MEM_ASCENDING (mem is [0:15])
#   stage F  chk_fv_full_when_occ_depth, chk_fv_empty_when_occ_zero: proven (22/22 golden)
#   stage 1  H_range (trivial on 4-bit 0..15 pointers), H_occ: proven
#   stage 2  H_mem: proven  -- if it CEXes, suspect the array direction first
#   stage 3  H_post: proven | stage 4 chk_data_match: proven (already proven unaided)
#   covers: all covered; cov_h_in_flight_deep at ~16+ cycles (15 entries ahead)
#   "M already proven" per stage: 0, 2, 6, 8, 10
#=============================================================================
clear -all
if {![info exists BATCH]} { set BATCH [info exists ::env(JG_BATCH)] }
set ROOT [exec git rev-parse --show-toplevel]
puts "ROOT = $ROOT"

analyze -sv09 $ROOT/golden_fifo/golden_afifo.sv
analyze -sv09 $ROOT/fv/fv_golden_afifo/fv_golden_afifo.sv
analyze -sv12 +define+FV_MEM_ASCENDING $ROOT/fv/fv_afifo/fv_afifo_helpers.sv
analyze -sv09 $ROOT/scripts/golden/fv_golden_afifo_bind.sv
analyze -sv12 $ROOT/scripts/golden/fv_golden_helpers_bind.sv
elaborate -top gold_top

# same environment as scripts/golden/golden_fifo.tcl
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
stage F {*chk_fv_full_when_occ_depth *chk_fv_empty_when_occ_zero}
stage 1 {*H_range_w *H_range_r *H_occ_w *H_occ_r}
stage 2 {*H_mem_w *H_mem_r}
stage 3 {*H_post_w *H_post_r}
stage 4 {*chk_data_match}

puts "=== stage 5: remaining properties (named list) ==="
set rest {}
foreach p [get_property_list -include {type assert}] {
   if {[string match *chk_data_match* $p]} continue
   if {[get_status $p] ne "proven"} { lappend rest $p }
}
foreach p [get_property_list -include {type cover}] { lappend rest $p }
prove -property $rest -with_proven

report -summary -force -file $ROOT/docs/runs/golden_helpers.txt
report -force -file $ROOT/docs/runs/golden_helpers_detail.txt
if {$BATCH} { exit }
