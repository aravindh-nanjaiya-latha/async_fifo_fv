# ECE 506 Proposal Addendum: Behavior List and Coverage Plan

Aravindh Nanjaiya Latha · Formal Verification and CDC Analysis of an Asynchronous FIFO · November 2026

This addendum answers the coordinator's request of 11 November 2026. It does two things.
It maps every behavior of the FIFO to the property or check that verifies it, with the
result on the baseline RTL and on the current RTL. It also sets out how formal coverage
will be measured, so the project can show that the properties check the whole design and
not just that the existing properties pass.

Design under verification: `rtl/` (top module `top`). It has 6-bit binary pointers over
9..54 (46 slots). Full is detected one slot early, so 45 entries are usable. Empty is
registered and full is combinational. Checker: `fv/fv_afifo/fv_afifo.sv`.

Result key: **P** = proven (unbounded, `bound Infinite`). **CEX *n*** = counterexample of
length *n* cycles. **B *n*** = inconclusive, no counterexample up to bound *n*.
**Covered by** = no dedicated property; the behavior is established by the properties named.

Baseline = tag `baseline-renamed` (`docs/runs/afifo_baseline_detail.txt`, 2 Nov).
Current = after fixes for Bugs 1, 1b, 3 and 5 (`docs/runs/afifo_after_bug5_dw8_bounded_detail.txt`, 3 Nov).
The B17–B19 and CDC results are on the Bug 6-fixed RTL (`docs/runs/afifo_helpers_dw8*.txt`,
`docs/cdc/afifo_after_bug6*`, 11 Nov). The fix registers the gray write pointer, and
`chk_wgray_correct_encoding`, proven on the fixed RTL, shows it leaves every signal's value
unchanged on every cycle.

## 1. Behavior list

### 1.1 Reset

| # | Behavior | Property / Check | Baseline | Current |
|---|---|---|---|---|
| B1 | Empty is asserted when read-side reset is released | `chk_fv_empty_after_reset` | P | P |
| B2 | Full is deasserted when write-side reset is released | `chk_fv_no_full_after_reset` | P | P |
| B3 | Pointers reset to 9 (binary) and gray(9) (gray), in both domains, including the synchroniser outputs | Covered by B1, B2, B13 and the pointer step/hold properties (B4, B6, B10, B12) | CEX via B13 (Bug 1) | P |

B1 passed at baseline, but Bug 1 (the synchroniser resets to 0 instead of gray(9)) was
caught by B13 two cycles later. B3 has no dedicated property. A wrong reset value shows up
through what it breaks: B13 (Bug 1, 2 cycles), or the step/hold properties for a pointer.
The one case nothing observes is Bug 1b (write-side synchroniser reset 0), which has no
functional effect: `full` can never compare equal to 0. It was found by reading the RTL and
fixed for consistency. A dedicated reset-value assertion was considered and not added,
because it would check internal signals and only add a more direct name for a failure
that is already caught.

### 1.2 Write side

| # | Behavior | Property / Check | Baseline | Current |
|---|---|---|---|---|
| B4 | An accepted write (`w_en && !full`) advances `b_wptr` to its ring successor, including 54→9 | `chk_wrptr` | P | P |
| B5 | A write while full is dropped: the pointer holds (overflow protection) | `chk_no_increment_when_full` | P | P |
| B6 | Without an accepted write, `b_wptr` holds | `chk_fv_same_w_ptr_on_no_write` | P | P |
| B7 | Full is asserted when 45 entries are held | `chk_fv_full_when_occ_depth` | CEX 21 | P |
| B8 | After a read frees a slot, full deasserts within 2 `w_clk` (the synchroniser latency) | `chk_fv_full_deasserts_within_sync_lat` | CEX 7 | P |
| B9 | `full == (b_wptr_next == b_rptr_sync)` (the designers' own RTL assertion) | `top.w_inst._assert_1` | P | P |

### 1.3 Read side

| # | Behavior | Property / Check | Baseline | Current |
|---|---|---|---|---|
| B10 | An accepted read (`r_en && !empty`) advances `b_rptr` to its ring successor, including 54→9 | `chk_rptr` | P | P |
| B11 | A read while empty is ignored: the pointer holds (underflow protection) | `chk_no_increment_when_empty` | CEX 51 | P |
| B12 | Without an accepted read, `b_rptr` holds | `chk_fv_same_r_ptr_on_no_read` | CEX 28 | P |
| B13 | Empty is asserted when occupancy is 0 | `chk_fv_empty_when_occ_zero` | CEX 2 | P |
| B14 | After a write, empty deasserts within 3 `r_clk` (2 sync flops + registered flag) | `chk_fv_empty_deasserts_within_sync_lat` | CEX 50 | P |
| B15 | Empty follows `g_wptr_sync == g_rptr_next` one cycle later (the designers' own RTL assertion) | `top.r_inst._assert_1` | P | P |
| B16 | `data_out` is stable when there is no accepted read | `chk_fv_stable_dout` | P | P |

### 1.4 Data path

| # | Behavior | Property / Check | Baseline | Current |
|---|---|---|---|---|
| B17 | Every accepted word is read out once, in order, with the correct value: integrity, ordering, no drop, no duplicate. Data appears on the cycle after the accepted read. | `chk_data_match` (symbolic-tag scoreboard) | CEX 45 | **P** with helper properties, at DW=1 and DW=8. Slot case split P (pending author review). B 117 without helpers. |
| B18 | Pointers stay in 9..54, and every memory access is inside the declared array | `H_range_w`, `H_range_r` (range); array bound via B17 (`chk_data_match`) | CEX via B17 (Bug 5) | P |
| B19 | A slot holding unread data is never overwritten | Covered by B17. Also helper properties `H_mem_{w,r}` (the in-flight slot still holds the tracked value) | n/a | P (helper properties) |

**Note on B17.** Without help, `chk_data_match` stops at bound 117 with no counterexample,
which is inconclusive. The engine has to discover how the scoreboard state relates to the RTL
state on its own, and it can't: the scoreboard counts mod 64 while the pointers count mod 46
over 9..54.

Two independent proofs close it. Neither changes the contract checker.

1. **Helper properties** (`fv/fv_afifo/fv_afifo_helpers.sv`, run by
   `scripts/afifo/fv_afifo_helpers.tcl`). Four white-box invariants, each asserted on both
   clocks, are proven in order. Each stage assumes only the properties already proven:
   - `H_range`: the pointers stay in 9..54.
   - `H_occ`: occupancy counted from port events equals the cyclic pointer distance.
   - `H_mem`: while the tagged entry is in flight, its slot holds the tracked value.
   - `H_post`: just after the tagged read, `data_out` equals the tracked value.

   `chk_data_match` then proves in 0.026 s at DW=8 (0.002 s at DW=1), on the Bug 6-fixed RTL
   (`docs/runs/afifo_helpers_dw8*.txt` and `_dw1*.txt`, both re-run 18 Nov). 34/34 covers are reached, including the
   tagged entry held 44 deep and held across the 54→9 wrap.

   DW=1 and DW=8 give identical statuses, bounds and trace lengths for all 63 properties,
   which is consistent with the data path being bit-sliced.
2. **Slot case split** (reports `docs/runs/e6_*`). The tracked memory slot is split into
   46 cases, each proven separately (46/46 P), and a proven range property shows the cases cover
   every slot. `chk_data_match` then proves in 1902 s with engine C at DW=8. This proof is
   pending author review.

In both proofs the tag stays fully symbolic and there are no environment assumptions. The
helpers were also proven on `gold_top` (30/30 assertions, 33/33 covers;
`docs/runs/golden_helpers*.txt`). In a negative control, wiring the memory with the wrong
index direction makes `H_mem` fail in 2 cycles, which shows the helper property is not vacuous.

Bug 5 (memory declared `[53:9]`) was found by a distinguishing experiment. After Bug 3 was
fixed, `chk_data_match` still failed at 51 cycles, which is the first time the pointer
reaches slot 54. Reading the array declaration then confirmed that slot 54 did not exist.
`H_range` (B18) proves the pointers stay in 9..54, but it does not compare them with the
array's declared bounds, so on its own it would **not** have flagged Bug 5. Bug 5 was caught
by `chk_data_match` (B17): the word written to the missing slot came back wrong. A
dedicated address-in-array check (`b_wptr <= $high(f_mem)`)
would have named the defect directly. It was considered and not added, because B17 already
proves that every accepted word is stored and returned correctly, which rules out any
out-of-range access on the fixed RTL.

### 1.5 Gray coding and clock-domain crossing

| # | Behavior | Property / Check | Baseline | Current |
|---|---|---|---|---|
| B20 | The gray pointer is the correct encoding of the binary pointer (both sides) | `chk_wgray_correct_encoding`, `chk_rgray_correct_encoding` | P | P |
| B21 | The gray pointer changes at most one bit per cycle, including at the 54→9 wrap (both sides) | `chk_wgray_onehot0`, `chk_rgray_onehot0` | P | P |
| B22 | Every crossing goes through a recognised synchroniser, with no unsynchronised paths, no logic in the crossing, and no convergence or divergence | Jasper CDC app: structural and scheme checks (`scripts/cdc/afifo_cdc.tcl`) | 47 pairs, 1 FIFO scheme, 2×2-FF | 48 pairs, 1 FIFO scheme. The diagnostic run (FIFO detection off) flagged `CDC_PR_LOGC`: combinational logic on the `b_wptr` → `sync_instR.q1` crossing (Bug 6). **After the fix (registered `g_wptr`), that violation is gone.** The diagnostic run now matches the golden control. |
| B23 | Push/pop guards hold: a request while full or empty does not move the pointer. Proven as custom CDC protocol checks, not assumed. | `no_pop_on_empty`, `no_push_on_full` (custom); built-in `POP_ON_EMTY` / `PSH_ON_FULL` waived only against these | pop **CEX** (Bug 3), push P | P, P; both built-ins waived; 0 errors |
| B24 | Reset domains are consistent and reset release is safe | CDC reset-domain analysis, with resets declared synchronised (assumption A1) | no RDC violations | no RDC violations |

### 1.6 Assumptions and out-of-scope behaviors

| Item | Treatment |
|---|---|
| Symbolic tag is stable (`chk_fv_asm_stable_tag`) | The only `assume`. It does not restrict the DUT: it lets the engine treat the tag as an arbitrary constant. |
| Reset release is synchronised upstream | Integrator obligation. It is recorded as an explicit assumption and is not checked. |
| One domain reset while the other keeps running | Out of scope for FPV, because the checker assumes both domains are reset together. B24 covers it in CDC. |
| Metastability resolution and MTBF | Physical behavior that formal analysis cannot see. Out of scope. |

**Totals.** There are 24 behaviors. 21 have a dedicated FPV check (B1, B2, B4–B21), and all
21 are proven at DW=8 as well as DW=1. B3 is covered by B1, B2, B13 and the pointer
properties. B22–B24 are covered by the CDC run (11 Nov). B23 and B24 are clean. B22 had one
design finding, Bug 6, which is fixed (tag `fix-bug6`), and the CDC re-run
confirms it. No further properties are planned.

Assertions in the regular 20-assertion run: the baseline is 13/20 proven (7 CEX) with the
calibrated checker. The proposal's 11/20 was measured before calibration, when two checker
constants were wrong (see `docs/runs/README.md` and the `fv_afifo.tcl` header). With the helper properties, the
current RTL is 20/20 proven at DW=8.

## 2. Reachability: cover properties

Every property also gets an automatic precondition cover, which shows that its antecedent
can actually occur and so is a vacuity check. Current run: **27/27 covered, 0 unreachable**.
That is the 9 explicit covers below plus 18 precondition covers.

| Cover | What it shows | Baseline depth | Current depth |
|---|---|---|---|
| `cov_full_after_empty` | The FIFO fills from empty | 5 | 43 |
| `cov_empty_after_full` | The FIFO drains from full | 48 | 81 |
| `cov_fv_data_captured` | The scoreboard captures the tagged word | 2 | 2 |
| `cov_fv_data_checked` | The scoreboard checks the tagged word | 2 | 5 |
| `cov_fv_check_second_lap` | The same tag is checked twice, which exercises tag reuse after wrap | 66 | 69 |
| `cov_fv_wptr_wrap` | Write pointer wraps 54→9 | 18 | 44 |
| `cov_fv_rptr_wrap` | Read pointer wraps 54→9 | 35 | 51 |
| `cov_fv_empty_bound_tight` | The empty bound (3) is hit exactly, so it is tight | 7 | 5 |
| `cov_fv_full_bound_tight` | The full bound (2) is hit exactly, so it is tight | 7 | 47 |

The depths say something about the design. At baseline the FIFO "filled" in 5 cycles,
which is impossible with 45 entries; that was Bug 1. After the fixes, filling takes 43
cycles, which is consistent with 45 writes at a free clock ratio. The deepest cover is
`cov_empty_after_full` at 81 cycles. B17's bound of 117 is above that, which is
supporting evidence only and does not count as a proof.

The scenarios that matter most are also reached, through the automatic precondition covers:
- FIFO holds exactly 45 entries: `chk_fv_full_when_occ_depth:precondition1`, 46 cycles.
- A write attempted while full, which B5 must reject: `chk_no_increment_when_full:precondition1`, 46 cycles.
- A read attempted while empty, which B11 must reject: `chk_no_increment_when_empty:precondition1`, 1 cycle.
- The helper module's own covers: tagged word in flight 44 deep (`cov_h_in_flight_deep`, 46
  cycles), in flight across the 54→9 wrap (`cov_h_in_flight_wrapped`, 48), and the
  post-read state (`cov_h_post`, 6).

All 34 covers are reached (`docs/runs/afifo_helpers_dw8_detail.txt`, re-run 18 Nov). The count
fell from 38 to 34 when the five abandoned `hlp_*` helper properties were removed from the checker: four of
them carried an automatic precondition cover, and those four went with them. The 34 are the 9
checker covers, the 3 helper covers and 22 precondition covers.

## 3. Formal coverage plan (Jasper Coverage App)

Passing properties show only that the properties that exist are true. Coverage shows how
much of the RTL those properties actually constrain. Three measures will be reported for
`gold_top` first and then for `top`. Each will be given at the statement, branch and
expression level.

| Measure | Question it answers | Target / action |
|---|---|---|
| **Stimuli (reachability) coverage** | Can every RTL line, branch and expression be reached under the checker's constraints? An unreachable item means either over-constraint or dead code. | 100% reachable, or each unreachable item justified (for example the `+1` arm of a pointer can never produce 55). With a single `assume` that does not touch the DUT, over-constraint is not expected. |
| **COI coverage** | Is every RTL item in the cone of influence of at least one assertion? An item outside every COI is logic that nothing checks. | Union over all assertions = 100% of design items. Any gap gets a new property or a written justification. |
| **Proof-core coverage** | Which items did the engines actually need to complete each proof? An item that is in the COI but in no proof core means the properties are weaker than the COI suggests. | Report per property group. Each gap is examined: either add an assertion that needs that logic, or explain why it is redundant. |
| **Bound coverage** (inconclusive properties only) | For a bounded result, which items are reachable within the bound? | Applies to B17's run without helpers (B 117). It is reported next to the two full proofs. |

Each assertion will be reported as **proven**, **failed (CEX, length)** or
**inconclusive (bound)**. The final report will include the behavior table above, updated
with final results.

**Procedure.** One script, `scripts/afifo/fv_afifo_cov.tcl`, will be run unchanged on
both designs, in the same way as the FPV and CDC scripts. Its header will carry predicted
results, written before the run. Its outline is below. Exact command options will be
confirmed against the Jasper Coverage App guide before the first run.

```tcl
check_cov -init -type all          ;# instrument statement/branch/expression items
# ... same analyze / elaborate / clock / reset as fv_afifo.tcl ...
prove -all
check_cov -measure -type {stimuli coi proof}
check_cov -report -file docs/runs/<design>_coverage.txt
```

Proof-core coverage for `chk_data_match` will come from the decomposed run, because that
is the run that proves it. This will be stated explicitly in the report.

**Expected findings.** These are predictions to check against the results.
1. `data_in` → `f_mem` → `data_out` will be in COI only through `chk_data_match`, so
   proof-core for the memory will depend entirely on the decomposed proof.
2. The designers' commented-out assertions and debug-only `$error` text carry no coverage
   items, so they have no effect.
3. The synchroniser flops will be in the COI of the flag properties (B7, B8, B13, B14), but
   the CDC app is the real check on them (B22–B24).

## 4. Schedule update

| Week | Work |
|---|---|
| 11 Nov | Done: CDC on the baseline FIFO; Bug 6 found, fixed and tagged; `chk_data_match` proven with helper properties (DW=1 and DW=8); helpers proven on `gold_top`. |
| by 15 Nov | Author review of all results and documents; commit and push. |
| 16–20 Nov | Coverage app run (COI and proof-core) on `gold_top`, then `top`, once the `check_cov` syntax is confirmed against the licensed guide. |
| 21 Nov – 2 Dec | Report, presentation and demo recording. |

Weekly progress will be pushed to GitHub every Friday.
