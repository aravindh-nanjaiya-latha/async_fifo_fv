clear -all
set ROOT [exec git rev-parse --show-toplevel]   ;# same as the CDC script; info-script-relative paths broke before

puts "ROOT   = $ROOT"
puts "GOLDEN = $ROOT/golden_fifo/golden_afifo.sv"

analyze -sv09 $ROOT/golden_fifo/golden_afifo.sv
analyze -sv09 $ROOT/fv/fv_golden_afifo/fv_golden_afifo.sv
analyze -sv09 $ROOT/scripts/golden/fv_golden_afifo_bind.sv
elaborate -top gold_top

clock w_clk
clock r_clk
reset -expression {!wrst_n} {!rrst_n}
clock -rate {w_en data_in} w_clk
clock -rate {r_en} r_clk
prove -bg -all
