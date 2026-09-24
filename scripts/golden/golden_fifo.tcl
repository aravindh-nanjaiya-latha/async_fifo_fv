clear -all
set ROOT [file normalize [file join [file dirname [info script]] .. ..]]

analyze -sv09 $ROOT/golden_fifo/golden_afifo.sv
analyze -sv09 $ROOT/fv/fv_golden_afifo/fv_golden_afifo.sv
analyze -sv09 $ROOT/scripts/golden/fv_golden_afifo_bind.sv
elaborate -top gold_top

clock w_clk
clock r_clk
reset -expression {!wrst_n} {!rrst_n}
clock -rate {w_en data_in} w_clk
clock -rate {r_en} r_clk
prove -all
