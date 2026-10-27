# Asynchronous FIFO — Formal Property Verification & CDC Analysis

## Overview

This project focuses on **Formal Property Verification (FPV)** and **Clock Domain Crossing (CDC)** analysis of asynchronous FIFO designs using Cadence JasperGold.

The objective is to develop a reusable verification methodology, validate it against a reference FIFO generated using Claude and independently evaluated through formal verification, then apply the same methodology to an asynchronous FIFO developed by me and my teammates as part of **ECE 593 — Pre-Silicon Validation**, where the original focus was simulation-based verification using UVM.

This project is developed as part of **ECE 506 — Project** at Portland State University.

## Verification Methodology

The project follows four stages:

1. **Reference Design:** Use a Claude-generated asynchronous FIFO as the golden reference design.
2. **Checker Validation:** Develop SystemVerilog Assertions (SVA), a symbolic transaction scoreboard, and a CDC analysis flow. Validate them against the golden FIFO.
3. **Formal Analysis of the ECE 593 Design:** Apply the verification methodology to the original ECE 593 FIFO without modifying its RTL. Investigate counterexamples and CDC violations.
4. **Corrections and Regression:** Implement RTL fixes separately and rerun the same SVA and CDC checks to evaluate their effectiveness.

This approach helps distinguish defects in the design under verification from errors in the verification infrastructure itself.

## Designs Under Verification

| Design | Depth | Description |
|---|---|---|
| Golden FIFO | 16 | Claude-generated reference asynchronous FIFO using Gray-coded pointers and two-flop synchronizers |
| ECE 593 FIFO | 45 | Non-power-of-two asynchronous FIFO with pointer range 9–53, developed as part of a team project |

The golden FIFO is used to validate the verification infrastructure. The original ECE 593 FIFO serves as the experimental baseline.

## Verification Components

### Formal Property Verification

The FPV environment includes checks for:

- Reset behavior
- FIFO overflow and underflow protection
- Read-data stability
- Data integrity and ordering through a symbolic transaction scoreboard
- Read and write pointer progression
- Gray-code pointer correctness

### Clock Domain Crossing Analysis

The CDC methodology includes:

- Asynchronous clock-domain configuration
- Synchronizer and crossing identification
- FIFO scheme detection
- Functional CDC protocol verification
- Reset-domain crossing analysis

Cadence JasperGold CDC supports structural and formal CDC/RDC analysis. This project currently focuses on RTL-level verification.

## Repository Structure

```text
async_fifo_fv/
├── rtl/                  # Original ECE 593 FIFO RTL
├── uvm_tb/               # Original UVM verification environment
├── golden_fifo/          # Claude-generated reference FIFO
├── fv/
│   ├── fv_golden_afifo/  # Golden FIFO formal checker
│   └── fv_afifo/         # ECE 593 FIFO formal checker
├── scripts/
│   ├── golden/           # Golden FPV execution scripts
│   ├── afifo/            # ECE 593 FPV execution scripts
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

Two Git tags preserve the original ECE 593 design:

- `baseline-upstream` — Original upstream repository snapshot.
- `baseline-renamed` — Directory restructuring only, without RTL modifications.

The `rtl/` directory is preserved as the unmodified ECE 593 implementation during baseline verification. RTL corrections are developed separately to enable reproducible before-and-after comparisons.

## Current Progress

| Component | Status |
|---|---|
| Golden FIFO FPV | Checker implemented; final proof regression pending |
| Golden FIFO CDC | Completed with zero reported errors under documented constraints |
| ECE 593 FIFO FPV | In progress; defects identified |
| ECE 593 FIFO CDC | Pending |
| RTL corrections and regression | Pending |

## Tools

- Cadence JasperGold — Formal Property Verification
- Cadence JasperGold CDC — Clock Domain Crossing Analysis
- SystemVerilog and SystemVerilog Assertions
- Tcl — Verification automation
- Git and GitHub — Version control and reproducibility

## Original Design Attribution

The ECE 593 asynchronous FIFO RTL and UVM testbench were developed collaboratively as part of the Pre-Silicon Validation coursework.

Original project repository: [RaghaHanuma22/Async_FIFO](https://github.com/RaghaHanuma22/Async_FIFO)

**Original team members:**

- Aravindh Nanjaiya Latha
- Maithreyi Venkatesan
- Raghavendra Davarapalli

The original RTL and UVM environment are retained for verification and comparison. The subsequent formal verification infrastructure, CDC methodology, and associated analysis are part of the ECE 506 project.

## Project Author

**Aravindh Nanjaiya Latha**

M.S. Electrical and Computer Engineering  
Portland State University

**Faculty Advisor:** Dr. Xiaoyu Song  
**Project Coordinator:** Pratibha Munnangi