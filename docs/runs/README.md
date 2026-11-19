# docs/runs: FPV reports

Every file here is a Jasper report (`*.txt`) or a run log (`*.log`, local only). `X.txt` is
the summary and `X_detail.txt` lists every property with its result, engine, bound and time.
How to read a row: `proven ... Infinite` = proven for all time; `cex N` = counterexample of
N cycles; `undetermined ... N` = no failure up to N cycles, not proven; `covered N` = the
cover was reached in N cycles (`a - b` = the engine's lower bound, then the trace length).

| Report | Design / RTL state | What it shows |
|---|---|---|
| `afifo_baseline*` | baseline FIFO, pristine RTL (tag `student-baseline`) | 13/20 proven, 7 CEX: the "before" column |
| `afifo_after_bug1*` | + Bug 1 fix | same count; every CEX moves to >= 51 cycles |
| `afifo_after_bug3*` | + Bug 3 fix | 19/20; only `chk_data_match` fails (51 cycles -> Bug 5) |
| `afifo_after_bug5_dw8_bounded*` | + Bug 5 fix | 19/20 proven, `chk_data_match` bounded at 117 cycles (17.3 h), no CEX |
| `afifo_after_bug6*` | + Bug 6 fix | 19/19 contract assertions proven (regression; `chk_data_match` proven separately below) |
| `afifo_helpers_dw8*` | Bug-6-fixed RTL + helper properties, checker after the `hlp_*` removal | re-run 18 Nov: 28 assertions all proven, 34/34 covers; `chk_data_match` proven unbounded |
| `afifo_helpers_dw1*` | same RTL and checker, data width 1 | re-run 18 Nov: 28/28 proven, 34/34 covers; every row identical to DW=8 in status, bound and trace length |
| `golden_helpers*` | golden FIFO + helper properties | golden-first: 30/30 proven, 33/33 covers |
| `golden_helpers_negctl.txt` | golden, deliberately wrong memory wiring | negative control: `H_mem` fails in 2 cycles, so the helper property is not vacuous |
| `e6_*`, `exp_*`, `afifo_h5_*` | state-space campaign (5-6 Nov) | the 46-way slot case split that also proves `chk_data_match`, plus experiments |
