# Asynchronous FIFO — Formal Property Verification & CDC Analysis

## Overview

This project applies Formal Property Verification (FPV) and Clock Domain Crossing (CDC) analysis to asynchronous FIFO designs using Cadence JasperGold.

The objective is to develop a reusable verification methodology, validate it against a reference FIFO generated with Claude and independently evaluated through formal verification, then apply the same methodology, unchanged, to an asynchronous FIFO that my friends and I designed and verified with UVM as a personal project in summer 2026, outside any course. That design passed its own simulation regression; this project asks what a formal flow finds that simulation did not.

This project is developed as part of ECE 506 — Project at Portland State University.

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
| Baseline FIFO | 45 | Non-power-of-two asynchronous FIFO, developed as a personal project (summer 2026) |

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
├── rtl/                  # Baseline FIFO RTL (unmodified at baseline tags)
├── uvm_tb/               # Original UVM verification environment
├── golden_fifo/          # Claude-generated reference FIFO
├── fv/
│   ├── fv_golden_afifo/  # Golden FIFO formal checker
│   └── fv_afifo/         # Baseline FIFO formal checker
├── scripts/
│   ├── golden/           # Golden FPV execution scripts
│   ├── afifo/            # Baseline FIFO FPV execution scripts
│   └── cdc/              # CDC scripts and Tcl reference
├── docs/
│   └── cdc/              # CDC methodology and reports
└── README.md
```

## Documentation

- [CDC Reference](docs/cdc/CDC_REFERENCE.md) — CDC concepts, methodology, and tool reference.
- [CDC Approach](docs/cdc/CDC_APPROACH.md) — Investigation process, configuration decisions, and lessons learned.

Additional verification documentation and bug analysis will be published following further review.

## Reproducibility and Baselines

Two Git tags preserve the original baseline FIFO:

- `baseline-upstream` — Original upstream repository snapshot.
- `baseline-renamed` — Directory restructuring only, without RTL modifications.
- `fv-infra` — Golden FIFO checker fully proven with `rtl/` untouched.

The `rtl/` directory is preserved as the unmodified baseline implementation during baseline verification. RTL corrections are developed separately, one commit per defect, to enable reproducible before-and-after comparisons with identical scripts.

## Current Progress

| Component | Status |
|---|---|
| Golden FIFO FPV | Completed — 22/22 assertions proven, all covers reached |
| Golden FIFO CDC | Completed with zero reported errors under documented constraints |
| Baseline FIFO FPV | In progress; preliminary run complete, defects identified |
| Baseline FIFO CDC | Pending |
| RTL corrections and regression | Pending |

## Tools

- Cadence JasperGold — Formal Property Verification
- Cadence JasperGold CDC — Clock Domain Crossing Analysis
- SystemVerilog and SystemVerilog Assertions
- Tcl — Verification automation
- Git and GitHub — Version control and reproducibility

## Original Design Attribution

The baseline asynchronous FIFO RTL and UVM testbench were developed in summer 2026 by Aravindh Nanjaiya Latha, Maithreyi Venkatesan and Raghavendra Davarapalli as a personal, ungraded project, outside any course and not previously submitted for credit.

Original project repository: [RaghaHanuma22/Async_FIFO](https://github.com/RaghaHanuma22/Async_FIFO)

The original RTL and UVM environment are retained, unmodified at the baseline tags, for verification and comparison. The formal verification infrastructure, CDC methodology, and all associated analysis in this repository are ECE 506 work by Aravindh Nanjaiya Latha.

The golden reference FIFO (`golden_fifo/`) was generated with Claude (Anthropic) and is declared as such in its file header. It is used only to validate the verification infrastructure and is evaluated by the same formal flow.

## Project Author

Aravindh Nanjaiya Latha

M.S. Electrical and Computer Engineering
Portland State University

Faculty Advisor: Dr. Xiaoyu Song
Project Coordinator: Pratibha Munnangi
