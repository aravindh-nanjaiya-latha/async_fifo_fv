# Asynchronous FIFO: Formal Property Verification & CDC Analysis

## Overview

This project applies Formal Property Verification (FPV) and Clock Domain Crossing (CDC) analysis to asynchronous FIFO designs using Cadence JasperGold.

The objective is to develop a reusable verification methodology, validate it against a reference FIFO generated with Claude and independently evaluated through formal verification, then apply the same methodology, unchanged, to an asynchronous FIFO that my friends and I designed and verified with UVM as a personal project in summer 2025, outside any course. That design came with its own UVM testbench, which had not reported a failure; this project asks what a formal flow finds that simulation did not.

This project is developed as part of ECE 506 (Project) at Portland State University.

## Documents

| Document | What it contains |
|---|---|
| [`ECE506_AsyncFIFO_FV_Report.pdf`](ECE506_AsyncFIFO_FV_Report.pdf) | **Final report** (14 pages): designs, verification setup, results by run, the four defects with their fixes, formal coverage, limitations |
| [`ECE506_Proposal_AsyncFIFO_FV.pdf`](ECE506_Proposal_AsyncFIFO_FV.pdf) | Project proposal, as submitted on 6 November 2026 |
| [`docs/proposal/behavior_coverage.md`](docs/proposal/behavior_coverage.md) | The 24 behaviours, each mapped to the check that decides it, with baseline and final results |
| [`docs/cdc/CDC_APPROACH.md`](docs/cdc/CDC_APPROACH.md) | CDC method and decision record, including the Bug 6 finding |
| [`docs/runs/README.md`](docs/runs/README.md) | Index of every FPV report and how to read it |

Every number in the report is taken from a tool report in `docs/runs/` or `docs/cdc/`, and the file is named next to it.

## Verification Methodology

The project follows four stages:

1. **Reference design.** Use a Claude-generated asynchronous FIFO as the golden reference.
2. **Checker validation.** Develop SystemVerilog Assertions (SVA), a symbolic transaction scoreboard, and a CDC analysis flow. Validate them against the golden FIFO.
3. **Formal analysis of the baseline FIFO.** Apply the verification methodology to the original baseline FIFO without modifying its RTL. Investigate counterexamples and CDC violations.
4. **Corrections and regression.** Implement RTL fixes separately and rerun the same SVA and CDC checks to evaluate their effectiveness.

Validating the checkers on a known-good design first separates defects in the design under verification from errors in the verification infrastructure itself.

## Designs Under Verification

| Design | Depth | Description |
|---|---|---|
| Golden FIFO | 16 | Claude-generated reference asynchronous FIFO using Gray-coded pointers and two-flop synchronizers |
| Baseline FIFO | 45 | Non-power-of-two asynchronous FIFO, developed as a personal project (summer 2025) |

The golden FIFO is used to validate the verification infrastructure. The baseline FIFO is the design under verification and the experimental baseline.

## Verification Components

### Formal Property Verification

The FPV environment includes checks for:

- Reset behavior
- FIFO overflow and underflow protection
- Read-data stability
- Data integrity and ordering through a symbolic transaction scoreboard
- Read and write pointer progression
- Gray-code pointer correctness, including at the wrap
- Occupancy-versus-flag consistency and bounded flag response

### Clock Domain Crossing Analysis

The CDC methodology includes:

- Asynchronous clock-domain configuration
- Synchronizer and crossing identification
- FIFO scheme detection
- Functional CDC protocol verification
- Reset-domain crossing analysis

Cadence JasperGold CDC supports structural and formal CDC/RDC analysis. This project currently focuses on RTL-level verification.

## Repository Structure

```
async_fifo_fv/
├── rtl/                  # Baseline FIFO RTL (pristine at the baseline tags; one commit per fix since)
├── golden_fifo/          # Claude-generated reference FIFO (gold_top)
├── uvm_tb/               # Original UVM verification environment (unchanged)
├── fv/
│   ├── fv_golden_afifo/  # Golden FIFO formal checker
│   └── fv_afifo/         # Baseline FIFO formal checker + helper properties for the data-integrity proof
├── scripts/
│   ├── golden/           # Golden FPV scripts (checker run, helper-property run) and binds
│   ├── afifo/            # Baseline FPV scripts (main run, data-integrity proof, regressions) and binds
│   └── cdc/              # CDC scripts (golden, baseline) and a Tcl reference
├── docs/
│   ├── proposal/         # Proposal addendum: behaviour list and coverage plan
│   ├── cdc/              # CDC methodology, reference, and every CDC report
│   └── runs/             # Every FPV report (see docs/runs/README.md)
├── ECE506_AsyncFIFO_FV_Report.pdf    # Final report
├── ECE506_Proposal_AsyncFIFO_FV.pdf  # Proposal, as submitted
└── README.md
```

Every script resolves the repository root with `git rev-parse --show-toplevel`, so it can be
run from any directory. Each script header explains what it runs and records the expected
result, written before the run.

## How to Run (Cadence Jasper, PSU CECS deimos)

```sh
# FPV, baseline FIFO: full checker
cd scripts/afifo && jg fv_afifo.tcl
# FPV, baseline FIFO: staged proof of data integrity (chk_data_match) with helper properties
cd scripts/afifo && jg -proj jgproject_helpers fv_afifo_helpers.tcl
# FPV, golden FIFO: checker, then the same helper properties (golden-first)
jg scripts/golden/golden_fifo.tcl
jg scripts/golden/golden_helpers.tcl
# CDC, golden and baseline (CDC_TAG names the report set; CDC_FIFO_DET=0 is the diagnostic run)
jg -cdc scripts/cdc/golden_cdc.tcl
CDC_TAG=afifo_after_bug6 jg -cdc scripts/cdc/afifo_cdc.tcl
# Batch mode needs the licence environment:
/pkgs/pkgs/bin/addpkg_shell bash -c "cd <repo> && jg -batch -tcl <script.tcl> -proj <own project dir>"
```

## Seeing a counterexample for yourself

No waveform captures are shipped. They are not needed: every counterexample quoted in the report
is reproducible from the tags in this repository, and once a property fails the trace is available
in the Jasper GUI, which is better than a static screenshot because you can step it.

Only `rtl/` is swapped; the checker and scripts stay at the current version, which is the
project rule (same checker before and after every fix). Checking out a whole tag would also
roll back the checker and scripts to whatever existed at that point.

```sh
# 1. the RTL exactly as it was handed over, before any fix (checker and scripts unchanged)
git checkout baseline-renamed -- rtl/
cd scripts/afifo && jg fv_afifo.tcl
#    expect: 20 assertions, 13 proven, 7 CEX, 27/27 covers
#    (docs/runs/afifo_baseline.txt is the logged copy of this run)

# 2. open any failing property in the GUI to step its trace, for example
#    (lengths below are quoted exactly as the tool reports them, ranges included,
#     from docs/runs/afifo_baseline_detail.txt)
#    chk_fv_empty_when_occ_zero             CEX 2         -> Bug 1, synchroniser reset value
#    chk_fv_full_deasserts_within_sync_lat  CEX 7         -> Bug 1, the false full it also causes
#    chk_fv_same_r_ptr_on_no_read           CEX 28 - 51   -> Bug 3, ungated read-pointer wrap
#    chk_no_increment_when_empty            CEX 51        -> Bug 3, same cause
#    chk_data_match                         CEX 45 - 226  -> Bug 5, memory one slot short

# 3. walk the fixes one at a time and watch the trace lengths move
git checkout fix-bug1 -- rtl/   # then fix-bug3, fix-bug5, fix-bug6, re-running step 1 each time

# 4. put the current RTL back
git checkout HEAD -- rtl/
```

Bug 6 is structural and has no counterexample trace. It appears in the CDC run only with
automatic FIFO recognition disabled:

```sh
# export the pristine RTL to a scratch directory; the working tree is not touched
mkdir -p /tmp/afifo_baseline && git archive baseline-renamed rtl | tar -x -C /tmp/afifo_baseline
CDC_RTL=/tmp/afifo_baseline/rtl CDC_TAG=my_check CDC_FIFO_DET=0 jg -cdc scripts/cdc/afifo_cdc.tcl
#    expect CDC_PR_LOGC on w_inst.b_wptr -> sync_instR.q1
#    the same setting on the golden FIFO (scripts/cdc/golden_cdc.tcl) reports no such violation,
#    which is what makes it a finding about the design rather than about the setting
```

Note: the five abandoned `hlp_*` helper properties were removed from the checker on 2026-11-18, so a run
today reports 20 assertions rather than the 25 some older logs show. The contract properties are
unchanged.

## Reproducibility and Baselines

Git tags preserve the original baseline FIFO and every step after it:

- `baseline-upstream`: original upstream repository snapshot.
- `baseline-renamed`: directory restructuring only, without RTL modifications.
- `fv-infra`: golden FIFO checker fully proven, with `rtl/` untouched.
- `student-baseline`: calibrated baseline-FIFO checker and its first run, on the untouched RTL. (The tag keeps its
  original name because it is already published; the files it produced are now named `afifo_baseline*`.)
- `fix-bug1`, `fix-bug3`, `fix-bug5`, `fix-bug6`: one commit per RTL fix, in order.

`git diff --stat baseline-renamed -- rtl/` lists exactly the files the fixes touched.

The `rtl/` directory is preserved as the unmodified baseline implementation during baseline verification. RTL corrections are developed separately, one commit per defect, to enable reproducible before-and-after comparisons with identical scripts.

## Current Progress

| Component | Status |
|---|---|
| Golden FIFO FPV | Completed: 22/22 assertions proven, all covers reached; helper properties also proven on it (30/30) |
| Golden FIFO CDC | Completed: zero errors under documented constraints |
| Baseline FIFO FPV | 13/20 assertions proven on the untouched RTL; 20/20 after the fixes, including data integrity (`chk_data_match`) proven unbounded at DW=1 and DW=8 |
| Baseline FIFO CDC | 2 errors on the untouched RTL; 0 after the fixes, including a diagnostic run with FIFO detection off |
| RTL corrections and regression | Defects fixed one at a time and re-verified with identical scripts; reports in `docs/runs/` and `docs/cdc/` |
| Formal coverage (stimuli / COI / proof-core) | Run on both designs at DW=8; reports in `docs/runs/golden_coverage_*` and `docs/runs/afifo_dw8_coverage_*` |
| Final report | Completed: [`ECE506_AsyncFIFO_FV_Report.pdf`](ECE506_AsyncFIFO_FV_Report.pdf) |

## Tools

- Cadence JasperGold: Formal Property Verification
- Cadence JasperGold CDC: Clock Domain Crossing Analysis
- SystemVerilog and SystemVerilog Assertions
- Tcl: verification automation
- Git and GitHub: version control and reproducibility

## Original Design Attribution

The baseline asynchronous FIFO RTL and UVM testbench were developed in summer 2025 by Aravindh Nanjaiya Latha, Maithreyi Venkatesan and Raghavendra Davarapalli as a personal, ungraded project, outside any course and not previously submitted for credit.

Original project repository: [RaghaHanuma22/Async_FIFO](https://github.com/RaghaHanuma22/Async_FIFO)

The original RTL and UVM environment are retained, unmodified at the baseline tags, for verification and comparison. The formal verification infrastructure, CDC methodology, and all associated analysis in this repository are ECE 506 work by Aravindh Nanjaiya Latha.

The golden reference FIFO (`golden_fifo/`) was generated with Claude (Anthropic) and is declared as such in its file header. It is used only to validate the verification infrastructure and is evaluated by the same formal flow.

## Project Author

Aravindh Nanjaiya Latha

M.S. Electrical and Computer Engineering
Portland State University

Faculty Advisor: Dr. Xiaoyu Song
Project Coordinator: Pratibha Munnangi
