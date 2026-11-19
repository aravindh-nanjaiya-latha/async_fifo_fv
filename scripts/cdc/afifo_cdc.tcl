#=============================================================================
#  afifo_cdc.tcl -- Jasper CDC App run on the BASELINE async FIFO (top "top")
#
#  CDC IN PLAIN WORDS (for readers new to it)
#    A clock-domain crossing (CDC) is any signal launched by a flop on one clock
#    and captured by a flop on another, unrelated clock. If the data changes too
#    close to the capturing edge, the capturing flop can go "metastable" (settle
#    late, to a random value). Safe designs pass such signals through a
#    SYNCHRONISER (2 flops in a row on the destination clock) and, for multi-bit
#    values like pointers, use GRAY CODE so only one bit changes at a time.
#    The Jasper CDC App checks this STRUCTURALLY (from the netlist, no stimulus):
#      pair      = one source-flop -> destination-flop crossing it found
#      scheme    = a recognised safe structure (here: a FIFO scheme)
#      violation = a crossing or structure that breaks a rule
#      waiver    = a violation closed with a written, cited justification
#    and FUNCTIONALLY, by formally proving protocol properties around each
#    scheme (e.g. "no pop while empty").
#
#  RESULT SUMMARY (details in the OUTCOME blocks below and docs/cdc/CDC_APPROACH.md section 8)
#    baseline : custom no_pop_on_empty CEX (Bug 3 again, found independently)
#    after Bugs 1/1b/3/5 : 0 errors, BUT the diagnostic run with FIFO detection
#               off showed CDC_PR_LOGC = combinational logic on the write-pointer
#               crossing -> Bug 6 (g_wptr was XOR logic, not a register)
#    after Bug 6 fix : 0 errors; diagnostic run matches the golden control
#
#  Same flow as scripts/cdc/golden_cdc.tcl (validated: golden 0 errors), with
#  only the design-specific lines changed (file list, port names, waiver text).
#  Rationale for every setting is in golden_cdc.tcl and docs/cdc/CDC_APPROACH.md.
#
#  ONE SCRIPT, TWO RUNS (before/after evidence):
#    CDC_RTL  = directory holding the 5 RTL files     (default: $ROOT/rtl)
#    CDC_TAG  = report prefix under docs/cdc/          (default: afifo_current)
#
#  Baseline run (pristine RTL at tag baseline-renamed, exported, never edited):
#    git archive baseline-renamed rtl | tar -x -C <dir>
#    CDC_RTL=<dir>/rtl CDC_TAG=afifo_baseline jg -cdc -batch -tcl scripts/cdc/afifo_cdc.tcl -proj <proj1>
#  Current run:
#    CDC_TAG=afifo_current jg -cdc -batch -tcl scripts/cdc/afifo_cdc.tcl -proj <proj2>
#  (Batch needs the license env: /pkgs/pkgs/bin/addpkg_shell bash -c "...".
#   Give each run its own -proj.)
#
#  RTL ONLY -- the FPV checker and bind are NOT analyzed (they add w_clk flops
#  feeding r_clk properties = testbench crossings).
#
#  NEVER declare the pointers gray-coded here (config_rtlds -signal -gray_code).
#  The tool believes declarations; gray-safety is FPV's job (chk_*gray_onehot0).
#
#  PREDICTIONS (written 2026-11-11, BEFORE the first baseline-FIFO run)
#  ----------------------------------------------------------------------------
#                          baseline-renamed          current (bug1/1b/3/5 fixed)
#  setup violations        2 (PRT_IS_UNCK on w_clk/r_clk, same as golden)   same
#  CDC pairs               47 = 2 ptr + 45 mem       48 = 2 ptr + 46 mem
#                            g_wptr -> sync_instR.q1 (6b)
#                            g_rptr -> sync_instW.q1 (6b)
#                            f_mem[9..53] -> data_out  f_mem[9..54] -> data_out (8b)
#  synchronizers           2 x 2-FF (NDFF), both directions                  same
#  scheme                  1 FIFO, Automatic -- LOW CONFIDENCE: depth 46, base 9,
#                          no pointer ports. If NOT detected: the custom checks below
#                          bind to nothing, mem->data_out becomes a mux/enable scheme
#                          (DAT_NO_STBL expected, as on golden before fifo_detection),
#                          and convergence returns at full/empty. Triage changes shape.
#  custom no_pop_on_empty  CEX (Bug 3, ungated      PROVEN
#                          wrap 54->9; FPV CEX 51)
#  custom no_push_on_full  PROVEN                    PROVEN
#  built-in read_on_empty  CEX ~1 cycle (environment question; waived ONLY if our
#                          check proved -- so NOT waived on baseline)
#  built-in write_on_full  CEX ~46 cycles (45 writes + 1); waived iff ours proved
#  RDC                     none (resets declared -synchronized, assumption A1).
#                          Possible exception: f_mem (wrst_n) -> data_out (no reset).
#  Bug 1 / 1b              NOT visible to CDC: a reset VALUE bug, not a structural
#                          crossing. FPV found it (chk_fv_empty_when_occ_zero).
#  Bug 5                   not a CDC finding; shows only as pair count 47 vs 48.
#
#  RUN 1 OUTCOME (2026-11-11 18:58, kept for the record)
#    pairs 47 / 48 ............... as predicted
#    scheme ...................... 1 FIFO, Automatic, on both -- prediction held
#    no_pop_on_empty ............. baseline CEX (USR_FN_PROP) / current proven -- held
#    no_push_on_full ............. proven / proven -- held
#    built-in write_on_full ...... CEX 46 cycles -- held
#    setup warnings .............. 5, NOT 2: PRT_IS_UNCK also on outputs full,
#                                  empty, data_out -> output ratings added (sec 5)
#    waivers ..................... none applied: status lookup used the wrong
#                                  task -> fixed (prop_proven, sec 10)
#    NEW, not predicted .......... write-side pair source is w_inst.b_wptr, not
#                                  a gray register: g_wptr = b_wptr ^ (b_wptr>>1)
#                                  is COMBINATIONAL into sync_instR.q1 (read side
#                                  registers g_rptr). Not flagged although
#                                  cdc_pair_logic = Buf. Hypothesis: the FIFO
#                                  scheme suppresses pair-logic checks ->
#                                  diagnostic run CDC_FIFO_DET=0.
#
#  PREDICTIONS FOR RUN 2
#    current, FIFO_DET=1: setup 2 warnings (clock ports); 2 custom proven;
#      2 built-in CEX, both WAIVED; 0 errors.
#    baseline, FIFO_DET=1: no_pop_on_empty CEX -> POP_ON_EMTY NOT waived;
#      errors = 2 (USR_FN_PROP, POP_ON_EMTY); PSH_ON_FULL waived.
#    current, FIFO_DET=0 (diagnostic): CDC_PR_LOGC (or equivalent) on
#      w_inst.b_wptr -> sync_instR.q1; DAT_NO_STBL on f_mem -> data_out (as
#      golden before fifo_detection); possibly convergence at full/empty.
#    RUN 2 OUTCOME: all held. CDC_PR_LOGC + CDC_PR_FOUT on w_inst.b_wptr -> Bug 6.
#    (pre-fix "current" reports renamed docs/cdc/afifo_after_bug5_*)
#
#  PREDICTIONS FOR fix-bug6 (registered g_wptr), written before the fix
#    CDC_TAG=afifo_after_bug6, FIFO_DET=1: 48 pairs; write pair source becomes
#      w_inst.g_wptr with 6 pair bits (was w_inst.b_wptr, 11); 2 custom proven,
#      2 built-ins waived; setup 2 clock-port warnings; 0 errors.
#    CDC_TAG=afifo_after_bug6_nofifo, FIFO_DET=0: CDC_PR_LOGC and CDC_PR_FOUT
#      GONE; remaining = 2 CNV_ST_CONV (full, empty) + 1 DAT_NO_STBL -- exactly
#      the golden control (docs/cdc/golden_nofifo_violations.txt).
#=============================================================================

clear -all
set ROOT [exec git rev-parse --show-toplevel]
set RTL  [expr {[info exists ::env(CDC_RTL)] ? $::env(CDC_RTL) : "$ROOT/rtl"}]
set TAG  [expr {[info exists ::env(CDC_TAG)] ? $::env(CDC_TAG) : "afifo_current"}]
# CDC_FIFO_DET=0 -> diagnostic run with FIFO recognition OFF (proposal risk:
# the FIFO scheme may suppress pair-logic / convergence checks on the pointers)
set FIFO_DET [expr {[info exists ::env(CDC_FIFO_DET)] ? $::env(CDC_FIFO_DET) : 1}]
puts "FIFO_DET = $FIFO_DET"
puts "ROOT = $ROOT"
puts "RTL  = $RTL"
puts "TAG  = $TAG"

# leaf modules first, top last (same order as scripts/afifo/fv_afifo.tcl)
analyze -sv09 $RTL/fifo_mem.sv
analyze -sv09 $RTL/read_ptr.sv
analyze -sv09 $RTL/synchronizer.sv
analyze -sv09 $RTL/write_ptr.sv
analyze -sv09 $RTL/top.sv
elaborate -top top

#-----------------------------------------------------------------------------
# 1. CLOCKS -- async mode, otherwise 0 pairs (false clean)
#-----------------------------------------------------------------------------
config_rtlds -clock -create w_clk
config_rtlds -clock -create r_clk
config_rtlds -rule -parameter {all_clocks_sync_by_default = false}

#-----------------------------------------------------------------------------
# 2. RESETS -- assumption A1 (docs/cdc/CDC_APPROACH.md section 4.9): release synchronized upstream.
#    Re-examined for this design: like gold_top, top has no reset synchronizer;
#    wrst_n / rrst_n drive async reset pins directly. Bug 1 is a reset VALUE
#    problem, not release timing, so A1 is the same obligation, not a cover-up.
#-----------------------------------------------------------------------------
config_rtlds -reset -synchronized wrst_n -clock w_clk_n0 -polarity low
config_rtlds -reset -synchronized rrst_n -clock r_clk_n1 -polarity low

#-----------------------------------------------------------------------------
# 3. FIFO RECOGNITION
#-----------------------------------------------------------------------------
if {$FIFO_DET} {
  config_rtlds -rule -parameter {fifo_detection = true}
} else {
  config_rtlds -rule -parameter {fifo_detection = false}
}

#-----------------------------------------------------------------------------
# 4. GRAY-CODE SIGNAL CONFIG -- intentionally ABSENT (see header)
#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
# 5. PORT RATINGS -- top has no pointer ports (unlike gold_top)
#-----------------------------------------------------------------------------
config_rtlds -port {w_en data_in} -clock w_clk_n0
config_rtlds -port {r_en}         -clock r_clk_n1
config_rtlds -port {w_en data_in} -reset wrst_n
config_rtlds -port {r_en}         -reset rrst_n
# outputs: run 1 showed PRT_IS_UNCK on full/empty/data_out (golden had pointer
# OUTPUT ports rated instead). full is combinational in w_clk; empty and
# data_out are r_clk flops.
config_rtlds -port {full}           -clock w_clk_n0
config_rtlds -port {empty data_out} -clock r_clk_n1

#-----------------------------------------------------------------------------
# 6. STRUCTURAL ANALYSIS
#-----------------------------------------------------------------------------
check_cdc -setup
check_cdc -extract

#-----------------------------------------------------------------------------
# 7. SANITY CHECKS -- fail loudly instead of reporting a false clean
#-----------------------------------------------------------------------------
set EXP_PAIRS [expr {$TAG eq "afifo_baseline" ? 47 : 48}]
puts "clock_synchronicity: \[[check_cdc -list clock_synchronicity]\]"
set pairs [check_cdc -list pairs]
puts "CDC pairs found: [dict size $pairs]  (predicted $EXP_PAIRS)"
if {[dict size $pairs] == 0} {
    puts "ERROR: zero CDC pairs -- clocks treated as synchronous?"
} elseif {[dict size $pairs] != $EXP_PAIRS} {
    puts "WARNING: pair count differs from prediction ($EXP_PAIRS)."
}
# Was the FIFO scheme auto-detected? (prediction marked low confidence)
if {[catch {check_cdc -list schemes} sch]} {
    puts "NOTE: check_cdc -list schemes failed: $sch"
} else {
    puts "SCHEMES:\n$sch"
}

#-----------------------------------------------------------------------------
# 8. CUSTOM PROTOCOL CHECKS -- the design's own guards, asserted (never assumed)
#    Pointer did not move = not a tautology. Baseline Bug 3 should CEX the pop one.
#-----------------------------------------------------------------------------
check_cdc -protocol_check -add no_pop_on_empty \
  -expression {@(posedge %dclk) (%rinc && %rempty) |=> $stable(%rptr)} \
  -scheme fifo

check_cdc -protocol_check -add no_push_on_full \
  -expression {@(posedge %sclk) (%winc && %wfull) |=> $stable(%wptr)} \
  -scheme fifo

#-----------------------------------------------------------------------------
# 9. FUNCTIONAL ANALYSIS
#-----------------------------------------------------------------------------
check_cdc -protocol_check -generate
check_cdc -protocol_check -prove

# record every generated property name + status in the log
if {[catch {check_cdc -report -property -file $ROOT/docs/cdc/${TAG}_properties.txt -force} e]} {
    puts "NOTE: early property report failed: $e"
}

#-----------------------------------------------------------------------------
# 10. WAIVERS for the built-in request-side checks -- CONDITIONAL
#     A SEE_COMMENTS waiver cites a proof. It is added only if the cited custom
#     check is actually proven in THIS session; on a design whose guard is broken
#     (baseline Bug 3) the built-in violation stays an Error. Same script, honest
#     on both runs.
#-----------------------------------------------------------------------------
proc prop_proven {pattern} {
    # CDC scheme properties live in task <CDC_scheme_properties>, not <embedded>,
    # so get_status/get_property_list on the default task cannot see them (run 1).
    # check_cdc -list scheme_properties returns {name {Status Passed|Failed ...}}.
    if {[catch {check_cdc -list scheme_properties} d]} { puts "NOTE: scheme_properties query failed: $d"; return 0 }
    dict for {k v} $d {
        if {[string match $pattern $k]} {
            set st [dict get $v Status]
            puts "STATUS $k = $st"
            return [expr {$st eq "Passed"}]
        }
    }
    puts "NOTE: no scheme property matching $pattern"
    return 0
}

set pop_ok [prop_proven *no_pop_on_empty]
set psh_ok [prop_proven *no_push_on_full]
puts "custom no_pop_on_empty proven: $pop_ok   no_push_on_full proven: $psh_ok"

if {$pop_ok} {
  set f_pop [check_cdc -filter -add -tag POP_ON_EMTY]
  check_cdc -waiver -add -reason SEE_COMMENTS -filter $f_pop \
    -comment {Rinc maps to the raw request port r_en, so this check asks whether the environment ever requests a read while empty. The FIFO guards pops internally (b_rptr_next = (r_en & ~empty) ? next : b_rptr, read_ptr.sv; data_out updates only on ~empty && r_en, fifo_mem.sv), so a request on empty has no effect. Proven in this session by the custom check no_pop_on_empty.}
} else {
  puts "NOT WAIVING POP_ON_EMTY: custom no_pop_on_empty is not proven in this session."
}
if {$psh_ok} {
  set f_psh [check_cdc -filter -add -tag PSH_ON_FULL]
  check_cdc -waiver -add -reason SEE_COMMENTS -filter $f_psh \
    -comment {Winc maps to the raw request port w_en. The FIFO guards pushes internally (b_wptr advances only on wen && !full, write_ptr.sv; f_mem written only on w_en && ~full, fifo_mem.sv). Proven in this session by the custom check no_push_on_full.}
} else {
  puts "NOT WAIVING PSH_ON_FULL: custom no_push_on_full is not proven in this session."
}

#-----------------------------------------------------------------------------
# 11. REPORTS
#-----------------------------------------------------------------------------
file mkdir $ROOT/docs/cdc
check_cdc -report -setup              -file $ROOT/docs/cdc/${TAG}_setup.txt      -force
check_cdc -report -violation -detailed -file $ROOT/docs/cdc/${TAG}_violations.txt -force
check_cdc -report -property           -file $ROOT/docs/cdc/${TAG}_properties.txt -force
check_cdc -report -waiver -detailed   -file $ROOT/docs/cdc/${TAG}_waivers.txt    -force
check_cdc -report -signoff            -file $ROOT/docs/cdc/${TAG}_signoff.txt    -force
check_cdc -list pairs                 -file $ROOT/docs/cdc/${TAG}_pairs          -force

puts "CDC run complete ($TAG). Reports in docs/cdc/${TAG}_*."

# batch runs set CDC_BATCH=1 so the session closes; interactive runs stay open
if {[info exists ::env(CDC_BATCH)]} { exit }
