#=============================================================================
# fv_afifo.tcl -- the MAIN formal (FPV) run for the baseline async FIFO
#                 (design rtl/, top module `top`)
#
# WHAT IT DOES, STEP BY STEP
#   1. analyze   : read (compile) the RTL files and the checker
#   2. elaborate : build the design hierarchy with the checker bound inside it
#   3. clock / reset : tell Jasper which inputs are clocks and how to reset
#   4. prove     : try to prove every assertion and reach every cover
#   It uses the same flow that is proven on the golden FIFO
#   (scripts/golden/golden_fifo.tcl), so a difference in results is a
#   difference in the design, not in the setup.
#
# HOW TO RUN (from anywhere in the repo; paths come from `git rev-parse`)
#   GUI   : cd scripts/afifo && jg fv_afifo.tcl &
#   batch : jg -batch -tcl scripts/afifo/fv_afifo.tcl -proj <own project dir>
#   Options, set in the Jasper console BEFORE sourcing this file:
#     set DW 2       data width (default 8)
#     set NOPROVE 1  stop after setup, then prove chosen properties by hand with
#                    `prove -property {...}` (project rule: do not `prove -all`
#                    while chk_data_match may run for hours on a shared machine)
#
# BEFORE / AFTER EVIDENCE
#   The same checker and this same script are run on the untouched baseline RTL
#   (git tag baseline-renamed) and again after each fix (tags fix-bugN).
#   Reports are kept in docs/runs/. Run on baseline-renamed, the results ARE
#   the baseline.
#
# The block below is the set of predictions written BEFORE the very first run
# (project principle 1: write down what you expect, then compare). It is kept
# unchanged as a record, including the predictions that turned out wrong.
#
# PREDICTIONS (written before the first run -- principle 1):
#   CEX    chk_fv_empty_after_reset            Bug 1  (sync resets 0 vs gray(9))
#   CEX    chk_fv_empty_when_occ_zero          Bug 1 / Bug 3b
#   CEX    chk_fv_same_r_ptr_on_no_read        Bug 3  (ungated read wrap)   ~45+ cycles
#   CEX    chk_fv_same_w_ptr_on_no_write       Bug 3b (ungated write wrap)  ~45  cycles
#   CEX    chk_data_match                      Bug 3 / 3b
#   CEX    chk_wgray_onehot0, chk_rgray_onehot0 Bug 4 (53->9 flips 2 bits)
#   proven chk_*gray_correct_encoding, chk_fv_stable_dout, chk_fv_no_full_after_reset
#   ?      bounded-response pair, occ==DEPTH_EFF -> full   (depends on Bug 1 / 3b reach)
#
# WHAT ACTUALLY HAPPENED (added later, for readers; reports in docs/runs/)
#   Baseline with the calibrated checker: 13/20 proven, 7 CEX. Correct
#   predictions: data_match, same_r_ptr, empty_when_occ_zero CEX. Wrong ones:
#   chk_fv_empty_after_reset PROVEN (Bug 1 showed up in empty_when_occ_zero
#   instead); same_w_ptr PROVEN (Bug 3b refuted); both gray_onehot0 PROVEN
#   (Bug 4 refuted: the wrap is 54 -> 9, and gray(54) -> gray(9) is a 1-bit change).
#   After fixes for Bugs 1, 1b, 3, 5: 19/20 proven; chk_data_match proven later
#   with the helper properties (scripts/afifo/fv_afifo_helpers.tcl).
#=============================================================================
clear -all

if {![info exists DW]} { set DW 8 }   ;# data width of the FIFO; override with: set DW 2, then source this file
puts "DW    = $DW"

set ROOT [exec git rev-parse --show-toplevel]   ;# repo root, so the script runs from any directory
puts "ROOT  = $ROOT"
puts "AFIFO = $ROOT/rtl"

#--- analyze the RTL (leaf modules first, top last).
#    rtl/ is only ever changed by a bug-fix commit, never by verification work.
analyze -sv09 $ROOT/rtl/fifo_mem.sv
analyze -sv09 $ROOT/rtl/read_ptr.sv
analyze -sv09 $ROOT/rtl/synchronizer.sv
analyze -sv09 $ROOT/rtl/write_ptr.sv
analyze -sv09 $ROOT/rtl/top.sv

#--- the contract checker, then the bind that attaches it inside `top`.
#    FV_DW passes the data width to the bind.
analyze -sv12 $ROOT/fv/fv_afifo/fv_afifo.sv
analyze -sv12 +define+FV_DW=$DW $ROOT/scripts/afifo/fv_afifo_bind.sv

#--- elaborate the design (DUT = design under test) at the chosen data width
elaborate -top top -parameter top.data_width $DW

#--- clocks: two independent, free-running clocks. No frequency ratio is
#    fixed (clock -factor is deliberately not used), so the proof covers every
#    possible relationship between w_clk and r_clk. Same as the golden run.
clock w_clk
clock r_clk

#--- resets: both are active-low; the proof starts from the reset state
reset -expression {!wrst_n} {!rrst_n}

#--- clock rating: each input changes only on its own domain's clock, as a real
#    synchronous source would drive it
clock -rate {w_en data_in} w_clk
clock -rate {r_en} r_clk

#--- prove everything in the background, unless NOPROVE was set
if {[info exists NOPROVE]} { puts "NOPROVE set: elaborated only" } else { prove -bg -all }
