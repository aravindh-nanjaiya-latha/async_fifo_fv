#=============================================================================
# golden_fifo.tcl -- formal (FPV) run on the GOLDEN reference FIFO
#
# The golden FIFO (golden_fifo/golden_afifo.sv, top gold_top) is a known-good
# textbook design. Proving the checker on it first shows the checker itself is
# right; only then is the same checker style trusted on the baseline FIFO
# ("golden-first"). Expected and recorded result: 22/22 assertions proven.
#
# Steps: analyze (compile) -> elaborate (build hierarchy with the checker bound
# inside) -> declare clocks and resets -> prove everything.
#
# Run: cd scripts/golden && jg golden_fifo.tcl &
#      (batch: jg -batch -tcl scripts/golden/golden_fifo.tcl -proj <own dir>)
#=============================================================================
clear -all
set ROOT [exec git rev-parse --show-toplevel]   ;# repo root, so the script runs from any directory

puts "ROOT   = $ROOT"
puts "GOLDEN = $ROOT/golden_fifo/golden_afifo.sv"

# design, then checker, then the bind that attaches the checker inside gold_top
analyze -sv09 $ROOT/golden_fifo/golden_afifo.sv
analyze -sv09 $ROOT/fv/fv_golden_afifo/fv_golden_afifo.sv
analyze -sv09 $ROOT/scripts/golden/fv_golden_afifo_bind.sv
elaborate -top gold_top

# two independent, free-running clocks (no fixed ratio), so every timing
# relationship between the write and read sides is covered
clock w_clk
clock r_clk
# both resets are active-low; proofs start from the reset state
reset -expression {!wrst_n} {!rrst_n}
# each input changes only on its own domain's clock, like a real driver
clock -rate {w_en data_in} w_clk
clock -rate {r_en} r_clk
# prove every assertion and try every cover, in the background
prove -bg -all
