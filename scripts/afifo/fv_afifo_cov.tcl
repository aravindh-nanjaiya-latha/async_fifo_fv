#=============================================================================
# fv_afifo_cov.tcl -- formal coverage (Jasper Coverage App) for BOTH designs.
#
# IN ONE PARAGRAPH
#   Passing properties only say that the properties that exist are true. This
#   run asks the complementary question: how much of the RTL do those
#   properties actually constrain? Three measures are taken at statement,
#   branch and expression level -- stimuli (what the checker's environment can
#   reach), COI (what lies in the cone of influence of at least one assertion),
#   and proof core (what the engines actually NEEDED to close each proof).
#
# ONE SCRIPT, BOTH DESIGNS (project rule: same script before and after).
#   set DESIGN golden   -> gold_top   (the control; ALWAYS run this first)
#   set DESIGN afifo  -> top        (the design under verification)
#
# HOW TO RUN  (from the repo root)
#   addpkg_shell
#   cd scripts/afifo
#   jg -proj jgproject_cov fv_afifo_cov.tcl &            ;# DESIGN=golden, DW=1
#
#   then, for the baseline FIFO, in a FRESH session (or `unset` first):
#   jg -proj jgproject_cov fv_afifo_cov.tcl &
#   # in the console, before sourcing:  set DESIGN afifo ; set DW 8
#   # or non-interactively:
#   #   echo 'set DESIGN afifo; set DW 8; source fv_afifo_cov.tcl' > /tmp/s.tcl
#   #   JG_BATCH=1 jg -batch -proj jgproject_cov /tmp/s.tcl
#
#   Knobs: DESIGN (golden|afifo), DW (afifo only), MEAS_JOBS, MEAS_TIME.
#   Coverage items are source statements/branches/expressions, so the ITEM SET
#   is the same at DW=1 and DW=8; DW=1 is the cheap flow-validation run and
#   DW=8 is the one to quote in the report.
#
# WHY THIS IS BUILT ON THE HELPER FLOW, NOT ON fv_afifo.tcl
#   Proof-core coverage is only meaningful for proofs that actually CLOSED. On
#   the plain contract run chk_data_match is inconclusive (bound 117 after
#   17.3 h), so its proof core would say nothing. The staged helper flow closes
#   every property in seconds, so this script reuses it verbatim.
#
#   CONSEQUENCE, and it must be stated in the report: with `-with_proven`,
#   chk_data_match is proven ASSUMING the helper properties. Its own proof core is
#   therefore small and will NOT contain the memory logic -- f_mem shows up in
#   the core of H_mem_w / H_mem_r instead. The honest figure is the UNION of
#   the cores over {contract assertions} + {helper properties}, because together
#   they are the proof. Reporting chk_data_match's core alone understates what
#   was proven; reporting it without saying the helpers are assumed overstates
#   it. `-enable_prove_based_proof_core` (below) is what makes the staged
#   proves contribute their core data at all.
#
#-----------------------------------------------------------------------------
# SYNTAX PROVENANCE
#   Checked against docs/Jasper_Coverage_Tcl_Command_Guide.docx (author's own
#   command guide compiled from the Jasper Apps Command Reference 2026.06;
#   printed pp. 345-375 for the check_cov family). Four things that the first
#   draft of this script got wrong, kept here so the mistakes are not repeated:
#     1. -init goes BEFORE analyze/elaborate (confirmed: "preferably before
#        elaborate; required for some instrumentation"). It cannot be added later.
#     2. The report file switch is -report_file, NOT -file.
#     3. There is no `-report -type proof`. Report types are checker, stimuli,
#        formal and bounded; WHICH checker metric you get is selected
#        separately by `check_cov -configure -checker_mode coi|proof_core`.
#     4. -type proof, proof_core_high_precision and mutation are MUTUALLY
#        EXCLUSIVE at init. This script selects `proof`.
#
#   STILL UNVERIFIED (the only two; confirm from the run log, not by guessing):
#     U1  Whether -exclude_bind_hierarchies drops both binds (contract checker
#         and helpers) from the scored hierarchy. The intent is to score rtl/
#         only. If the item counts look inflated, check the hierarchy report.
#     U2  Whether proof-core attribution is sound for a proof obtained with
#         `-with_proven`. The guide does not discuss -with_proven. If the cores
#         look empty or implausible, fall back to the hand union described
#         above, and say so in the report.
#
# STATUS KEYWORD MAP -- this is the whole point of the run, so get it right:
#     stimuli   : `unreachable`  = not reachable under the environment.
#                 NOT automatically dead RTL (guide, closure checklist).
#     COI       : `undetectable` = outside every assertion's COI
#                 -> a genuine PROPERTY-SET GAP. This is measure 5's real test.
#     proof core: `unchecked`    = inside some COI but outside the proof core
#                 -> the properties are weaker than the COI suggests.
#     `covered_and_checked` = reachable and genuinely constrained.
#
#-----------------------------------------------------------------------------
# PREDICTIONS -- written 2026-11-16, BEFORE the first run (project rule).
#   Amend before running; do not amend afterwards.
#
#   GOLDEN (gold_top)
#   G1  stimuli: 0 `unreachable` items. The environment has ONE assume (the
#       stable symbolic tag) and it does not constrain the DUT. Any unreachable
#       item here indicts the CHECKER, not the design.
#   G2  COI: 0 `undetectable` items. gold_top is small and every signal feeds a
#       flag, a pointer or the data path, all of which carry assertions.
#   G3  proof core: `unchecked` > 0, and that is expected, not a defect. Items
#       in a COI but in no core are items the engines did not need.
#   G4  The golden run calibrates the measure: whatever shape its gaps have,
#       the same shape on the baseline FIFO is a property-set artefact and not
#       a finding about the baseline FIFO RTL.
#
#   BASELINE FIFO (top)
#   S1  stimuli: `unreachable` items are expected ONLY where the 9..54 pointer
#       range makes an arm dead (e.g. a branch that would produce 55). That is
#       a legitimate justification and the single most likely true unreachable.
#   S2  COI: 0 `undetectable`. Anything in rtl/ outside every COI is a hole in
#       the property set needing a property or a written justification. Nothing
#       expected, but this is the measure most likely to surprise.
#   S3  proof core: data_in -> f_mem -> data_out participates ONLY through the
#       chk_data_match chain, so the memory's core comes entirely from
#       H_mem_w / H_mem_r. See the CONSEQUENCE note above.
#   S4  The designers' commented-out assertions and the debug-only $error text
#       carry no coverage items, so they neither help nor hurt the numbers.
#   S5  The synchroniser flops are in the COI of the flag properties (B7, B8,
#       B13, B14), but the CDC app remains the real check on them (B22-B24).
#       Coverage is not a substitute for the structural run.
#
# OUTCOME -- observations only; the predictions above are left as written.
#   GOLDEN (2026-11-16, deimos). 38 items. COI 38/38 = 100%. Stimuli 22/38.
#     Proof core 22/38. Formal 22/38. Proof side 30/30 assertions, 33/33 covers.
#     RUN DIED at the -html line: "ECOV016: -html cannot be used with -type
#     formal", so no gap lists and no .db. -exclude_bind_hierarchies WORKED
#     (tc_checker_inst and tc_helpers_inst both 0/0), so U1 is RESOLVED.
#     G1 refuted as written (predicted 0 unreachable, got 16); see the baseline-FIFO
#     run below for the confirmed cause. G2 CONFIRMED (COI 100%). G3 held.
#     FOLLOW-UP (2026-11-17, same session): -exclude {reset} re-report gives
#     gold_top 22/22 = 100%, excluded 16, uncovered 0, unreachable 0, deadcode 0.
#     The golden control now reads the same way as the baseline FIFO.
#   BASELINE FIFO (2026-11-16, deimos, DW=8). Ran clean to the end, 0 errors.
#     54 items. COI 54/54 = 100%. Stimuli 38/54 raw, 38/38 = 100% excluding
#     reset. Proof core 38/54 raw, 38/38 = 100% excluding reset. Formal same.
#     Gap lists: undetectable 0, unchecked 0, uncovered 0, unreachable 16.
#     ALL 16 unreachable are negated reset expressions (~r_inst.rrst_n,
#     ~w_inst.wrst_n, ~sync_instR.rst, ~sync_instW.rst, ~f_memory_inst.arstn).
#     S1 was PARTLY WRONG: it expected a dead arm from the 9..54 range; there
#     is none, the only unreachables are reset. S2 CONFIRMED (0 undetectable).
#     S3 consistent but NOT demonstrated: per-property attribution stopped at
#     "Completed 1 out of 21 properties". FOLLOW-UP (2026-11-17): tried
#     `check_cov -get_target_info [check_cov -get_assert_id] -name -coi
#     -proof_core` in the live session. Every one of the 33 assertions returns
#     coi -1 and proof_core -1, except the 5 unprocessed hlp_* which return a
#     coi count (38/46/38/38/38) and still proof_core -1. So there is NO
#     per-property proof-core data in this configuration at all, not merely a
#     truncated set. U2 is CLOSED AS UNOBTAINABLE here. If it is wanted, the
#     only documented route is a fresh run instrumented with toggle items
#     (-model {... toggle}) plus `check_cov -measure -type per_property_checker`,
#     which the guide says considers toggle items only.
#   LICENCE: 'jasper_coverage' checkout failed on both runs ("No such feature
#     exists"); both ran under 'jasper_pcov'. Say so before claiming full
#     Coverage App use.
#=============================================================================
clear -all

if {![info exists DESIGN]}   { set DESIGN golden }   ;# golden-first, always
if {![info exists DW]}       { set DW 1 }
if {![info exists MEAS_JOBS]} { set MEAS_JOBS 8 }    ;# lower to 4 on a busy box
if {![info exists MEAS_TIME]} { set MEAS_TIME 30m }
if {![info exists BATCH]}    { set BATCH [info exists ::env(JG_BATCH)] }

if {$DESIGN ne "golden" && $DESIGN ne "afifo"} {
   error "DESIGN must be golden or afifo, got '$DESIGN'"
}

set ROOT [exec git rev-parse --show-toplevel]
set RUNS $ROOT/docs/runs
if {$DESIGN eq "golden"} { set TAG golden } else { set TAG afifo_dw$DW }
set COVTOP [expr {$DESIGN eq "golden" ? "gold_top" : "top"}]

puts "DESIGN = $DESIGN   DW = $DW   COVTOP = $COVTOP"
puts "ROOT   = $ROOT"

#--- 1. INSTRUMENT. Must precede analyze/elaborate; cannot be added later.
#    -model: the three levels the report promises. (toggle/fsm not promised,
#            and they would only dilute the percentages.)
#    -type : stimuli + coi + proof + bound. proof excludes mutation.
#    -covdut: score the DUT hierarchy only.
#    -exclude_bind_hierarchies: keep the checker and helper binds out of the
#            scored code -- we are measuring rtl/, not fv/.  (U1)
#    -enable_prove_based_proof_core: collect core data during the staged
#            proves below, which is the only way the -with_proven stages
#            contribute anything to the core.  (U2)
check_cov -init \
   -model {statement branch expression} \
   -type {stimuli coi proof bound} \
   -covdut $COVTOP \
   -exclude_bind_hierarchies \
   -enable_prove_based_proof_core

#--- 2. SOURCES: identical to the proof scripts this is built on.
if {$DESIGN eq "golden"} {
   # same as scripts/golden/golden_helpers.tcl
   analyze -sv09 $ROOT/golden_fifo/golden_afifo.sv
   analyze -sv09 $ROOT/fv/fv_golden_afifo/fv_golden_afifo.sv
   analyze -sv12 +define+FV_MEM_ASCENDING $ROOT/fv/fv_afifo/fv_afifo_helpers.sv
   analyze -sv09 $ROOT/scripts/golden/fv_golden_afifo_bind.sv
   analyze -sv12 $ROOT/scripts/golden/fv_golden_helpers_bind.sv
   elaborate -top gold_top
} else {
   # same as scripts/afifo/fv_afifo_helpers.tcl (leaf modules first)
   analyze -sv09 $ROOT/rtl/fifo_mem.sv
   analyze -sv09 $ROOT/rtl/read_ptr.sv
   analyze -sv09 $ROOT/rtl/synchronizer.sv
   analyze -sv09 $ROOT/rtl/write_ptr.sv
   analyze -sv09 $ROOT/rtl/top.sv
   analyze -sv12 $ROOT/fv/fv_afifo/fv_afifo.sv
   analyze -sv12 $ROOT/fv/fv_afifo/fv_afifo_helpers.sv
   analyze -sv12 +define+FV_DW=$DW $ROOT/scripts/afifo/fv_afifo_bind.sv
   analyze -sv12 +define+FV_DW=$DW $ROOT/scripts/afifo/fv_afifo_helpers_bind.sv
   elaborate -top top -parameter top.data_width $DW
}

#--- 3. Identical clocks, resets and input ratings, so the numbers compare.
clock w_clk
clock r_clk
reset -expression {!wrst_n} {!rrst_n}
clock -rate {w_en data_in} w_clk
clock -rate {r_en} r_clk

set_proofgrid_max_local_jobs 4

#--- 4. STAGED PROOF. Every property must CLOSE or the proof core says nothing.
proc stage {label patterns} {
   puts "=== stage $label: $patterns ==="
   prove -property $patterns -with_proven
}

stage F {*chk_fv_full_when_occ_depth *chk_fv_empty_when_occ_zero}
stage 1 {*H_range_w *H_range_r *H_occ_w *H_occ_r}
stage 2 {*H_mem_w *H_mem_r}
stage 3 {*H_post_w *H_post_r}
stage 4 {*chk_data_match}

# stage 5: NAMED list, never `prove -all` (project rule -- prove -all put the
# heavy engines back on chk_data_match and Jasper's own process hit 45.8 GB).
puts "=== stage 5: remaining properties (named list) ==="
set rest {}
foreach p [get_property_list -include {type assert}] {
   if {[string match *chk_data_match* $p]} continue
   if {[get_status $p] ne "proven"} { lappend rest $p }
}
foreach p [get_property_list -include {type cover}] { lappend rest $p }
if {[llength $rest]} { prove -property $rest -with_proven }

report -summary
report -summary -force -file $RUNS/${TAG}_coverage_proofsummary.txt

#--- 5. GATE: refuse to pretend coverage is sign-off against an unfinished proof.
set notproven {}
foreach p [get_property_list -include {type assert}] {
   if {[get_status $p] ne "proven"} { lappend notproven $p }
}
if {[llength $notproven]} {
   puts "########################################################"
   puts "WARNING: measuring coverage with these assertions NOT proven:"
   foreach p $notproven { puts "   $p  ([get_status $p])" }
   puts "Proof-core numbers are NOT usable for sign-off. Fix first."
   puts "########################################################"
} else {
   puts "=== gate OK: every contract and helper assertion is proven ==="
}

#--- 6. MEASURE. Background + explicit wait (guide: wait before reporting).
puts "=== measuring coverage (jobs $MEAS_JOBS, limit $MEAS_TIME) ==="
set mid [check_cov -measure \
            -type {stimuli coi proof bound} \
            -time_limit $MEAS_TIME -max_jobs $MEAS_JOBS -bg]
check_cov -measure -wait -id $mid
puts "=== measurement $mid complete ==="

#--- 7. REPORT. The checker metric is chosen by -checker_mode, not by -type.
check_cov -report -type stimuli -model {statement branch expression} \
   -report_file $RUNS/${TAG}_coverage_stimuli.txt -force

check_cov -configure -checker_mode coi
check_cov -report -type checker -model {statement branch expression} \
   -report_file $RUNS/${TAG}_coverage_coi.txt -force

check_cov -configure -checker_mode proof_core
check_cov -report -type checker -model {statement branch expression} \
   -report_file $RUNS/${TAG}_coverage_proofcore.txt -force

check_cov -report -type formal -model {statement branch expression} \
   -report_file $RUNS/${TAG}_coverage_formal.txt -force

# ECOV016: -html cannot be combined with -type formal. Default type only.
check_cov -report -report_file $RUNS/${TAG}_coverage.html -html -force

#--- 7b. The same three measures with reset items excluded.
#    A formal reset ESTABLISHES the reset state rather than executing the reset
#    sequence, so the `if (!rst_n)` arms are never exercised and are reported
#    unreachable by construction. They are not a gap in the property set. The
#    guide's -exclude filter has a `reset` category for exactly this; both the
#    raw and the excluding-reset numbers are reported so nothing is hidden.
check_cov -report -type stimuli -model {statement branch expression} \
   -exclude {reset} -report_file $RUNS/${TAG}_coverage_stimuli_noreset.txt -force
check_cov -configure -checker_mode proof_core
check_cov -report -type checker -model {statement branch expression} \
   -exclude {reset} -report_file $RUNS/${TAG}_coverage_proofcore_noreset.txt -force
check_cov -report -type formal -model {statement branch expression} \
   -exclude {reset} -report_file $RUNS/${TAG}_coverage_formal_noreset.txt -force

#--- 8. THE GAPS. These three lists are what actually goes in the report.
# Wrapped in catch: a gap dump that fails must NOT take the run down before
# the database export (that is exactly what -html did on the first run).
proc dump_gaps {status outfile note} {
   if {[catch {
      set ids [check_cov -list -status $status -cid -silent]
      set fh [open $outfile w]
      puts $fh "# status '$status' -- $note"
      puts $fh "# count: [llength $ids]"
      if {[llength $ids]} {
         if {[catch {check_cov -get_cover_item_info $ids \
                        -source_location -expression -prove_status} info]} {
            # -expression is not returned by default and may be refused; retry thinner
            set info [check_cov -get_cover_item_info $ids -source_location -prove_status]
         }
         foreach d $info { puts $fh $d }
      }
      close $fh
      puts "   $status: [llength $ids] item(s) -> $outfile"
   } err]} {
      puts "   WARNING: gap dump for '$status' failed: $err"
   }
}

puts "=== gap lists ==="
check_cov -configure -checker_mode coi
dump_gaps undetectable $RUNS/${TAG}_gaps_outside_coi.txt \
   "outside EVERY assertion COI = property-set gap (prediction S2/G2: expect 0)"
check_cov -configure -checker_mode proof_core
dump_gaps unchecked $RUNS/${TAG}_gaps_outside_proofcore.txt \
   "in a COI but not in any proof core = properties weaker than the COI suggests"
dump_gaps unreachable $RUNS/${TAG}_gaps_unreachable.txt \
   "PROVEN not reachable under the environment -- NOT automatically dead RTL; justify each"
dump_gaps uncovered $RUNS/${TAG}_gaps_uncovered.txt \
   "UNDETERMINED -- the measure did not settle these; not the same as unreachable"

#--- 9. ARCHIVE so the numbers can be re-derived without re-proving.
check_cov -export $RUNS/${TAG}_covdb.db -force

puts "=== coverage written to docs/runs/${TAG}_coverage*.txt (+ gaps, .db) ==="
puts "=== now fill in the OUTCOME block at the top of this script ==="
if {$BATCH} { exit }
