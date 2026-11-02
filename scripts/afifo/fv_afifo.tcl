#=============================================================================
# fv_afifo.tcl -- FPV of the STUDENT async FIFO (rtl/, top `top`) with the same
# checker flow that was proven on the golden FIFO (scripts/golden/golden_fifo.tcl).
#
# Run on baseline-renamed with rtl/ untouched: the results ARE the baseline.
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
#=============================================================================
clear -all

set ROOT [exec git rev-parse --show-toplevel]   ;# same as the CDC script; info-script-relative paths broke before
puts "ROOT  = $ROOT"
puts "AFIFO = $ROOT/rtl"

#--- analyze the RTL (leaf modules first, top last) -- rtl/ is PRISTINE, never edit it here
analyze -sv09 $ROOT/rtl/fifo_mem.sv
analyze -sv09 $ROOT/rtl/read_ptr.sv
analyze -sv09 $ROOT/rtl/synchronizer.sv
analyze -sv09 $ROOT/rtl/write_ptr.sv
analyze -sv09 $ROOT/rtl/top.sv

#--- checker + bind
analyze -sv12 $ROOT/fv/fv_afifo/fv_afifo.sv
analyze -sv12 $ROOT/scripts/afifo/fv_afifo_bind.sv

#--- elaborate the DUT top
elaborate -top top

#--- clocks: free running, same declaration as the golden run so results are comparable
#    (clock -factor would fix a frequency ratio; deliberately not used)
clock w_clk
clock r_clk

#--- resets (active low)
reset -expression {!wrst_n} {!rrst_n}

#--- clock rating: inputs change only on their own domain's clock
clock -rate {w_en data_in} w_clk
clock -rate {r_en} r_clk

#--- prove
prove -bg -all
