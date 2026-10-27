# Jasper CDC App — Working Reference

A practical reference for clock-domain-crossing and reset-domain-crossing verification
with the Jasper CDC App. Written while bringing up a CDC flow on an asynchronous FIFO
(Jasper 2026.06).

**How to read this.** Items marked ✅ were exercised and verified in this project — the
behaviour described was observed, not assumed. Items marked 📖 come from the tool
documentation and the companion reference script (`scripts/cdc/cdc_reference.tcl`) but
were not exercised here; confirm against the user guide for your version before relying
on them.

Companion documents:
- `docs/cdc/CDC_APPROACH.md` — what was actually done on this project and why
- `scripts/cdc/cdc_reference.tcl` — the full annotated command template
- `scripts/cdc/golden_cdc.tcl` — a complete working run

---

# Part 1 — What the app is, and the mental model

## 1.1 The three analysis phases

| Phase | Question it answers | Nature |
|---|---|---|
| **Structural** | Is there a recognized synchronizer on every crossing, and is the logic around it safe? | Pattern matching on the netlist. No proof engine. |
| **Functional** | Do the recognized synchronizers actually behave per their protocol? | Formal proofs (SVA). |
| **Metastability** | Does the design still meet its spec when synchronizers behave like real silicon? | Formal proofs with injected uncertainty. |

A fourth path exports checks to simulation, so the same properties can run in a dynamic
regression.

The phases are ordered for a reason: a structurally clean design can still fail
functionally, and a functionally clean design can still fail under metastability. Do not
skip forward.

## 1.2 How the tool thinks — five steps ✅

After elaboration the tool does not see "a FIFO". It sees flops joined by wires and
gates, and it proceeds like this:

1. **Build the netlist** — `analyze`, `elaborate`.
2. **Paint clock domains** — follow each declared clock through the clock tree and colour
   every flop it reaches. A flop's output carries its colour.
3. **Find crossings (pairs)** — for every flop→flop path, compare the two colours. If the
   domains are *asynchronous*, that path is a **CDC pair**.
4. **Match schemes** — at each pair's destination, pattern-match the structure against a
   library of synchronizer shapes (NDFF, mux, handshake, FIFO, pulse, edge, …).
5. **Check around the schemes** — look for hazards a synchronizer cannot fix:
   convergence, glitch, reset release.

`check_cdc -setup` performs steps 1–2 plus reset bookkeeping. `check_cdc -extract`
performs steps 3–5.

**Two consequences worth internalising:**

- **A "pair" is a connection between two registers, not a flop.** A 16-deep memory
  feeding one output register through a read mux produces **16 pairs**, even though it is
  128 flops. A 5-bit bus from one register to another is **1 pair** of 5 bits. ✅
- **"Passed" in step 4 means "I recognized a synchronizer shape here."** It does not mean
  the data crossing it is safe. A binary pointer through a correct 2-FF chain also
  "passes". That is why steps 5 and the functional phase exist. ✅

## 1.3 Division of labour: CDC app vs FPV ✅

| Hazard | Caught by |
|---|---|
| Values at clock edges — ordering, data integrity, pointer arithmetic | **FPV** |
| Combinational logic driving a synchronizer input (glitch) | **CDC app** (structural). FPV is blind: it has no sub-cycle time |
| Multi-bit crossing without a safe encoding | **CDC app** (structural) |
| Gray coding actually holding, including at the wrap | **FPV**. The CDC app *believes* a gray-code declaration, it does not prove it |
| Reconvergence of separately synchronized bits | **CDC app** (structural). FPV only with metastability injection |
| Reset-domain crossings | **CDC app** |
| A design's own guard (e.g. no pop on empty) | Either — as an FPV assertion, or as a **custom CDC protocol check** |

One line: **FPV checks what the values are at clock ticks; the CDC app checks whether the
structure could produce bad values between them.**

---

# Part 2 — Session and design setup

## 2.1 Starting a session ✅

```tcl
clear -all
check_cdc -init          ;# enables CDC-specific configuration, including SDC reuse
```

`check_cdc -init` must come before design read-in if you intend to use SDC data.

## 2.2 Performance knobs 📖

```tcl
set_parallel_synthesis_mode on     ;# multi-threaded elaboration
set_cdc_parallel_extraction 8      ;# parallel extraction workers (1 = sequential)
```

Irrelevant on a small block; matters on a real SoC where extraction dominates runtime.

## 2.3 Reading the design ✅

```tcl
analyze -sv09 <files>
elaborate -top <top>
```

Options worth knowing 📖:
- `elaborate -bbox_m {ip1 ip2}` — black-box modules you do not want analysed internally.
  Useful for third-party IP; note that black-boxing moves the obligation to the boundary.
- `liberty -load <lib>` — load Liberty models *before* elaboration so cell timing arcs
  can be used for clock-domain inference on hard macros.
- `read_sdc <file>` — import clock definitions, clock groups and port constraints
  instead of hand-writing them.

**Decide what to include.** For verifying a block's own crossings, analyse the RTL
**only**. Pulling a verification checker into the CDC session adds its auxiliary flops as
real crossings and buries the design's crossings in testbench noise. ✅

---

# Part 3 — Environment setup (where most mistakes live)

This is the part that decides whether the analysis is meaningful. Every item below
changes *what gets checked*, not just how it is reported.

## 3.1 Clocks ✅

```tcl
config_rtlds -clock -create w_clk
config_rtlds -clock -create r_clk
```

Declaring a clock tells the tool **where the clock tree is**. It says **nothing about the
relationship between clocks.**

### The single most dangerous default

```tcl
config_rtlds -rule -parameter {all_clocks_sync_by_default = false}
```

| Mode | Parameter | Meaning |
|---|---|---|
| **STA mode** (default) | `true` | Every declared clock is **synchronous** to every other until you say otherwise, e.g. with `set_clock_groups -async`. |
| **Async mode** | `false` | Every clock is **asynchronous** to every other unless declared synchronous. |

In STA mode with two undeclared-relationship clocks, **no path qualifies as a crossing**.
The run reports **zero pairs and zero violations** — a clean-looking report that checked
nothing. ✅ *This happened on this project and is the reason for the sanity check in
§8.1.*

Other clock facilities 📖:
```tcl
config_rtlds -clock -create clk -factor 2 -phase 1   ;# ratio / phase for related clocks
config_rtlds -clock -create ~clk_n                   ;# negative-edge clock
config_rtlds -clock -virtual vclk                    ;# off-chip clock domain
config_rtlds -clock -group -async {{clkA} {clkB}} -name GRP1
config_rtlds -clock -group -sync  {{clkA} {clkC}} -name GRP2
```
Group options also include `-logically_exclusive` and `-physically_exclusive` for clocks
that cannot be active at the same time.

To declare an *internal* net as a clock, remove its driver first
(`stopat -env <net>`), then create the clock on it. 📖

Related parameters 📖:
- `generated_clocks_sync_to_parents` — whether a generated clock is assumed synchronous
  to its source.
- `use_sdc_clock_period` — derive clock factors from SDC `create_clock -period`.

## 3.2 Resets ✅

```tcl
config_rtlds -reset -async        rst_n              -polarity low
config_rtlds -reset -sync         rst_n -clock clk   -polarity low
config_rtlds -reset -synchronized rst_n -clock clk   -polarity low
config_rtlds -reset -async        rst_n -polarity low -virtual
```

| Switch | Meaning |
|---|---|
| `-async` | Asynchronous assertion **and** release. The pessimistic model. |
| `-sync` | Fully synchronous assertion and release. Requires `-clock`. |
| `-synchronized` | Output of a reset synchronizer: async assertion, **synchronous release**. Requires `-clock`. |
| `-virtual` | Reset originating outside the current top boundary. |

**Only resets declared here are considered by the structural analysis.** An undeclared
reset is invisible — the tool says so explicitly in the log (ICDC030). ✅

**Why the choice matters.** Asserting an async reset is always safe. *Releasing* it is
the hazard: a release near a clock edge can violate recovery/removal timing, so flops may
go metastable or leave reset in different cycles. Declaring `-async` on a block that has
no internal reset synchronizer produces `RST_NO_SYNC` on every reset-domain crossing.
Declaring `-synchronized` states the contract that the reset was synchronized upstream —
which is **an assumption, and must be recorded as one**. ✅

Reset ordering 📖:
```tcl
check_cdc -reset -set_order {rstA rstB {rstC rstD}}
```
States that resets later in the list assert *before* earlier ones; sub-lists assert
simultaneously. The structural analysis uses this to auto-waive safe reset-domain
crossings. `-preview` lists what would be waived.

## 3.3 Port ratings ✅

A primary port has no internal flop to infer a domain from, so the tool cannot tell
whether a path through it crosses domains. Unrated ports produce `PRT_IS_UNCK`.

```tcl
config_rtlds -port {data_in w_en} -clock w_clk_n0
config_rtlds -port {r_en}         -clock r_clk_n1
config_rtlds -port {data_in w_en} -reset wrst_n
```

**The `-clock` argument takes the clock *name* (e.g. `w_clk_n0`), not the signal name.** ✅
The name is assigned when the clock is created and appears in the setup report's
*Declared Clocks* table.

Abstract ratings 📖:
- `sync_to_all` — synchronous to every clock in the design.
- `async_to_all` — asynchronous to every clock in the design.
- `config_rtlds -port <p> -external_sync -source_clock <c1> -destination_clock <c2>` —
  the port was already synchronized outside the block.
- `config_rtlds -port {pin} -module <bbox> -clock <clk>` — rate a black-box pin.

Global fallbacks 📖: `treat_data_ports_as_async` and `treat_data_ports_reset_as_async`
(`all | none | primary_inputs | …`) decide what happens to ports you did not rate.

**Port ratings are constraints on input behaviour**, so they can over-constrain. Confirm
they did not: after a proof, `:noConflict` and `:noDeadEnd` should be proven and `:live`
covered. ✅

### Ports used as both clock and data 📖
If a signal drives flop clock pins *and* ordinary logic, the clock rating propagates to
its fanout, the data fanout is analysed as data, and the tool raises `CLK_NO_DECL` for
any signal acting as an undeclared clock. Clock ports themselves commonly remain in
`PRT_IS_UNCK`; that is this case, not a gap. ✅

## 3.4 Signal configurations — design intent ✅/📖

These tell the tool facts about signal *behaviour* that structure cannot reveal.

```tcl
config_rtlds -signal -constant  {{test_mode 1'b0}}
config_rtlds -signal -static    {cfg_reg} -condition {enable}
config_rtlds -signal -exclusive {a_reg b_reg c_reg}
config_rtlds -signal -gray_code {wptr_gray}
config_rtlds -signal -false_path -from clkA -to clkB -through bypass
```

| Configuration | Claim |
|---|---|
| `-constant` | The signal is tied to a value. |
| `-static` | Quasi-static: constant during normal operation (config registers). Makes its crossings inactive. |
| `-exclusive` | Only one signal of the group toggles in any cycle. Prevents false convergence/glitch reports. |
| `-gray_code` | Multi-bit bus changes at most one bit at a time. |
| `-false_path` | Deactivate specific crossings. |

### Three traps with signal configurations

1. **The tool believes them.** A signal configuration is an *assumption*, not a proven
   fact, and it can auto-waive violations. Declaring something false silently removes the
   violation that would have exposed it. ✅

   *Concrete example from this project:* a FIFO with a non-power-of-two depth wraps its
   gray pointer with a **two-bit** change. Declaring that pointer `-gray_code` would
   assert something false and auto-waive the convergence violation that reveals it. The
   claim was left to an FPV property instead.

2. **Declaring several signals in one command builds one expression over the
   concatenation.** ✅ Observed:
   ```
   ##1 $changed({rgray, wgray}) |-> $onehot({rgray, wgray} ^ $past({rgray, wgray}))
   ```
   If both buses each advance one bit in the same sampled instant, two bits differ and
   the claim fails — although both behaved correctly. **Declare one signal per command.**

3. **A configuration can be inert.** Its effect depends on what else is enabled. Verify
   by running with and without it and diffing the violation report; do not assume a
   setting is load-bearing because it looks important. ✅

`config_rtlds -signal -prove` 📖 formally checks whether constant / static / exclusive
constraints actually hold in the RTL — worth running rather than trusting the
declarations.

### Safe-RDC and low-power constraints 📖
```tcl
config_rtlds -signal -reset <rst> -on_assert   -inactive_clock {clk}
config_rtlds -signal -reset <rst> -on_deassert -constant_data {{d 1'b0}}
config_rtlds -signal -power_control iso_ctrl -both -inactive_clock clk
```
State that the clock is inactive or data constant when a reset or power-control signal
changes, making the crossing safe by construction.

---

# Part 4 — Scheme recognition

## 4.1 Automatic detection ✅/📖

The tool matches structures against a built-in library. Each detector has its own switch:

| Parameter | Detects | Default |
|---|---|---|
| `automatic_scheme_detection` | master switch (also governs reset synchronizer detection) | true |
| `ndff_detection` | N-flop synchronizer chains | true |
| `pulse_detection`, `edge_detection` | pulse and edge synchronizers | true |
| `gated_clock_detection` | clock-gating structures | true |
| `mux_loop_detection` | mux feedback loop | true |
| `mux_ndff_detection`, `mux_pulse_detection` | mux schemes with NDFF/pulse control | false |
| `handshake_detection` | req/ack handshakes | **false** |
| `fifo_detection` | asynchronous FIFOs | **false** |

### The FIFO-detection trap ✅

`fifo_detection` defaults to **false**. Without it, a FIFO's memory-to-output path is
matched to a generic mux/enable scheme, and the tool generates a data-stability check:
*the selected word must not change while the capture enable is high.*

A **correct** FIFO fails that check: back-to-back reads advance the read pointer, so the
read-mux output legitimately changes. The result is a functional counterexample on a
design that is working as intended. Enabling FIFO detection collapses all the related
pairs into one FIFO scheme and generates the appropriate checks
(`PSH_ON_FULL` / `POP_ON_EMTY`) instead.

**Generalisation: a functional CEX may indicate the wrong *model*, not a design bug.**
Before debugging a trace, check what scheme type the tool assigned:
```tcl
check_cdc -list schemes
```

Chain-strictness parameters 📖: `strict_ndff_detection` (all chain flops in one
hierarchy), `allow_sync_chain_logic` (logic between chain flops),
`allow_sync_chain_fanout` (taps off intermediate stages), `sync_chain_logic` (which logic
is tolerated), and `n_min` (minimum flops to qualify as an NDFF).

## 4.2 User-defined schemes ✅

```tcl
check_cdc -scheme -add <type> -module <module> -map {{<formal> <actual>} …}
```

Supported types and their required formal signals 📖:

| Type | Formal signals |
|---|---|
| `ndff` | data, dout |
| `mux_loop` | data, dout, dready |
| `mux_ndff` | data, dout, sready, dready |
| `mux_pulse` | data, dout, sready, dready, enable |
| `fifo` | wfull, rempty, winc, rinc, wptr, rptr, wdata, rdata |
| `handshake` | data, sreq, dreq, dack, sack |
| `pulse` | data, dout, enable |
| `edge` | data, dout, activity, sensitivity |
| `sync_enabler` | enable, srcdomain/srcdomainlist, dstdomain |
| `glitch_protector` | dout, gpdata, control |
| `reset` | srst, dclk (+ fsrst / snrst / dout) |
| `icg` | clkin, enable, clkout (+ testenable) |

Custom types can be created and then mapped:
```tcl
check_cdc -scheme -create my_sync -formal_list {Data Dout Enable}   ;# 'dout' is mandatory
check_cdc -scheme -add my_sync -module my_mod -map {{Data din} {Dout dout} {Enable en}}
```

### Two hard limits found the hard way ✅

1. **Every `-map` entry must be a *port* of the module.** An expression such as
   `{rinc {r_en & ~empty}}` or an internal net is rejected (`WCDC113`).
2. **One bad entry drops the entire map** (`WCDC115`) and the tool silently falls back to
   automatic detection. The run continues and looks fine. Always verify afterwards:
   ```tcl
   check_cdc -list schemes      ;# check "Detection Type": UserDefined vs Automatic
   ```

**Consequence:** a `-module` user-defined scheme is a *black-box, port-level*
description. When one was accepted on a design whose internals mattered, the resulting
scheme lost its pointer signals, the synchronizer stage flops and the NDFF chains — the
tool stopped looking inside. For a block whose internals are the subject of verification,
**automatic detection is strictly better**; reserve user-defined schemes for genuine IP
black boxes.

Glitch-free cells 📖:
```tcl
check_cdc -glitch_free -add -module {gf_mux gf_and}
```
Marks custom combinational cells as glitch-free so they stop producing glitch violations.

---

# Part 5 — Structural analysis

```tcl
check_cdc -setup       ;# clocks, resets, ports, consistency
check_cdc -extract     ;# crossings, schemes, convergence, glitch, RDC
```

## 5.1 Violation domains ✅

Results are grouped into three domains, each reported separately:

| Domain | Covers |
|---|---|
| **SETUP** | declaration and consistency problems (`PRT_IS_UNCK`, `CLK_NO_DECL`, `RST_NO_DECL`, …) |
| **CDC** | synchronization, convergence, glitch, functional protocol checks |
| **RDC** | reset synchronization and reset-domain crossings |

Always read the **setup** domain first. Violations there mean the analysis itself may be
wrong, which makes everything downstream untrustworthy.

## 5.2 Tags worth knowing ✅/📖

| Tag | Meaning |
|---|---|
| `CDC_NO_SYNC` | crossing with no recognized synchronizer |
| `CDC_PR_LOGC` | combinational logic directly on the crossing data path |
| `SYN_DF_SLGC` | logic inside a synchronizer chain |
| `SYN_DF_FOUT` | fanout from an intermediate synchronizer stage |
| `CNV_ST_CONV` | convergence: independently synchronized signals meeting in logic |
| `CNV_ST_GLCH` | glitch: combinational reconvergence that can glitch |
| `PSH_ON_FULL` / `POP_ON_EMTY` | FIFO scheme: write when full / read when empty |
| `DAT_NO_STBL` / `CTL_NO_STBL` / `PLS_NO_STBL` | data / control / pulse not stable long enough |
| `RST_NO_SYNC` | reset not synchronized to the destination clock |
| `RDC_RS_DFRS` | reset-domain crossing: source and destination in different reset domains |
| `RST_RS_CONV` | reset convergence |
| `PRT_IS_UNCK` | port with no clock association |
| `USR_FN_PROP` | a user-supplied functional property failed |

## 5.3 Violation grouping — read the real count ✅

```tcl
check_cdc -violation -group (none | basic | advanced)
```

Grouping collapses related violations and shows only a primary. **The headline number is
not the occurrence count.** In this project `RST_NO_SYNC` displayed as **2** while the
detailed waiver report listed **10** distinct occurrences. Report the real number: use
`-grouping none`, or cross-check against a detailed report.

## 5.4 Convergence and glitch parameters 📖

| Parameter | Effect |
|---|---|
| `depth` | how many flop stages past synchronization convergence is tracked |
| `src_unit_domain` / `src_unit_signal` | restrict convergence to same/different source clocks or signals |
| `convergence_inside_ctrl_sync` | check convergence inside control-synchronizer logic |
| `ignore_unsync_paths_in_convergence` | ignore unsynchronized paths in convergence analysis |
| `group_fsm_convergences` | group multi-bit convergence on FSM state registers |
| `ignore_convergence_from_complex_schemes` | suppress convergence when inputs come from FIFO/handshake/mux schemes |
| `glitch_check` (`all` \| `covered`) | glitch analysis over all reconvergences or only those feeding a synchronizer |

## 5.5 RDC parameters 📖

| Parameter | Effect |
|---|---|
| `auto_reset_sync_detection` | detect reset synchronizers automatically |
| `strict_reset_scheme_detection` | require all reset-sync flops in one hierarchy |
| `allow_reset_sync_chain_logic` | permit logic in the reset-sync chain |
| `report_violations_on_undeclared_reset` | pessimistic mode: flag paths from undeclared resets |
| `ignore_internal_non_declared_resets` | do not flag internal nets feeding reset pins |
| `ignore_non_resettable_flop` | suppress RDC when the destination has no reset pin |
| `ignore_rdc_from_same_reset_source` | ignore RDC when source and destination share a root reset |
| `autowaive_rdc_with_ndff` | auto-waive RDC when the data path has an NDFF |
| `treat_boundaries_as_rdc` | flag boundary ports without reset association |

---

# Part 6 — Functional analysis

```tcl
check_cdc -protocol_check -generate
check_cdc -protocol_check -prove
```

`-generate` creates SVA properties for every recognized scheme (data stability, FIFO
flag protocol, handshake phases, …); `-prove` runs the formal engine on them.
`-generate -include_failed_schemes` 📖 also covers schemes with structural violations.

## 6.1 Custom protocol checks — the most useful facility here ✅

```tcl
check_cdc -protocol_check -add <name> \
  -expression {<SVA template using %formal_signals>} \
  -scheme <scheme_type>
```

The template is written against the scheme's **formal** signal names prefixed with `%`,
and the tool substitutes the actual signals **from the scheme's connection map**.

**Why this matters.** On an automatically detected scheme, the connection map is already
bound to internal nets. So a template referring to `%rptr` reaches the design's internal
pointer — **without** the port-only restriction that blocks `check_cdc -scheme -map`.
This is the way to express a design-specific claim about internal signals.

Working example from this project:

```tcl
check_cdc -protocol_check -add no_pop_on_empty \
  -expression {@(posedge %dclk) (%rinc && %rempty) |=> $stable(%rptr)} -scheme fifo

check_cdc -protocol_check -add no_push_on_full \
  -expression {@(posedge %sclk) (%winc && %wfull) |=> $stable(%wptr)} -scheme fifo
```

Both **proven**. Add them **before** `-generate`, which is what instantiates them per
scheme.

## 6.2 Built-in checks may ask the wrong question ✅

The built-in `POP_ON_EMTY` maps `Rinc` to the raw request port, so it asks
*"does anyone ever request a read while empty?"* — a question about the **environment**.
A FIFO whose contract permits such a request and ignores it internally will CEX on a
correct design.

The useful question is *"does such a request do anything?"* — a question about the
**design**. That is what the custom checks above express.

**The decision rule:**

> If the design protects itself, **assert its guard and prove it**.
> If it does not, the obligation is **external** — declare it and record it as an
> assumption.
> An assumption standing in for a guard that exists is never acceptable: it deletes
> exactly the traces that would expose a broken guard.

## 6.3 Exporting to simulation 📖

```tcl
check_cdc -protocol_check -export -file checks.sv -force -default_clock <clk>
check_cdc -export -type signal_config_property -file sig.sv -force
check_cdc -export -type waiver_cond_property   -file wvr.sv -force
```
Runs the same protocol checks, signal-config checks and conditional waivers inside a
simulation regression.

---

# Part 7 — Waivers

## 7.1 The three honest ways to close a violation ✅

1. **Fix the design.**
2. **Fix the setup** — the violation came from an incomplete or wrong environment.
3. **Waive it with evidence.**

A waiver's quality *is* the quality of its evidence.

## 7.2 Waiver types ✅

```tcl
check_cdc -waiver -add -reason <reason> [-comment <text>]
         ( -filter <filter_id> [-expression <sva>] | -hierarchy <module_or_instance> )
```

| Form | Use |
|---|---|
| `-filter <id>` | waive the violations a filter selects |
| `-hierarchy <inst>` | suppress internal violations of third-party IP while keeping boundary checks |
| `-expression <sva>` | attach a **condition** the tool can prove — a *conditional waiver* |
| `-reason <R>` | a built-in reason the tool converts to a formal expression |

Filters select violations by many criteria — `-tag`, `-violation_key`, `-severity`,
`-module`, `-scheme`, `-detection_type`, and more:
```tcl
set f [check_cdc -filter -add -tag POP_ON_EMTY]
```

## 7.3 Smart waivers: generate and prove ✅

```tcl
check_cdc -list waiver_reasons      ;# which reasons apply to which tags
check_cdc -waiver -generate [-filter <id>] [-reason {<list>}]
check_cdc -waiver -prove   [-id {<ids>}] [-task <task>]
check_cdc -report -waiver -detailed
```

Reasons include `STATIC_SRC`, `INACTIVE_SRC_CLK`, `INACTIVE_SRC_RST`,
`INACTIVE_DST_CLK`, `INACTIVE_DST_RST`, `UNREACHABLE_DST`, `EXCLUSIVE_CLOCKS`,
`INACTIVE_ENABLE`, `SRC_ONEBIT_CHANGE`.

A proven waiver is **Safe**; a refuted one is **Unsafe**. This is the valuable part: the
tool tries to *break* your justification.

### What to watch ✅

- **Reasons are tag-specific.** Run `check_cdc -list waiver_reasons` first. In this
  project **no reason existed for `POP_ON_EMTY` / `PSH_ON_FULL`**, so `-waiver -generate`
  never attempted them — "not attempted" is very different from "attempted and passed".
- **`SEE_COMMENTS` is always available and always `Unvalidatable`.** It cannot be checked
  by the formal engine. It is acceptable only when the comment cites evidence proven
  elsewhere — and the comment text appears inline in the violation report, so write it
  for a reviewer.
- **`check_cdc -waiver -prove` changes the session**: it switches clock sampling to both
  edges (`WCDC250`) and invalidates existing proof results. Re-run the functional phase
  afterwards, or do waiver proving last.
- **`-waiver -accept`** marks waivers as user waivers that are *always* considered valid
  regardless of status. Use with care — it defeats the point of proving them.
- `-export` / `-import` move waivers between sessions; `-export` writes them as
  `check_cdc -waiver -add` commands.

## 7.4 Conditional waivers 📖/✅

A waiver carrying `-expression` sits **Unprocessed** until proved, then becomes Safe or
yields a CEX. With an implication operator (`|->` / `|=>`) the tool also derives a cover
from the antecedent, guarding against a vacuous precondition. This is the mechanism to
use when a built-in reason does not fit but the claim *is* provable.

---

# Part 8 — Discipline: making a clean report mean something

## 8.1 Predict, then assert the prediction ✅

Before reading any report, write down the crossings you expect. Then make the script fail
loudly if reality disagrees:

```tcl
puts "clock_synchronicity: \[[check_cdc -list clock_synchronicity]\]"
set pairs [check_cdc -list pairs]
puts "CDC pairs found: [dict size $pairs]  (expected N)"
if {[dict size $pairs] == 0} {
    puts "ERROR: zero CDC pairs -- clocks treated as synchronous?"
} elseif {[dict size $pairs] != N} {
    puts "WARNING: pair count changed from the documented baseline of N."
}
```

Zero pairs is indistinguishable from a clean result unless you assert otherwise. This
check is what caught the STA-mode default on this project.

## 8.2 Verify that configuration took effect ✅

Several commands fail *soft*: a rejected scheme map falls back to automatic detection; an
inert signal config changes nothing. After configuring, confirm:

```tcl
check_cdc -list schemes          ;# Detection Type, connection map completeness
check_cdc -list signal_config    ;# what was actually recorded, and the exact expression
check_cdc -report -setup         ;# Declared Clocks / Declared Resets / Clock Rating of Ports
```

## 8.3 Record the expected result in the script ✅

Put a short expected-result block in the header (setup violations, pair count, scheme
type, property statuses). It turns the script into a reproducible baseline, and a future
run becomes a diff rather than a fresh interpretation.

## 8.4 Write assumptions where a reviewer will find them ✅

Every `-synchronized` reset, every signal configuration, every `SEE_COMMENTS` waiver is
an obligation moved elsewhere. Keep them in a dedicated document (`docs/assumptions.md`)
and reference it from the script. An unrecorded assumption is a hidden hole.

---

# Part 9 — Metastability analysis 📖

```tcl
check_cdc -metastability -inject [-include_reset] [-include_protocol_check]
check_cdc -metastability -prove
```

Injection models real synchronizer behaviour — a crossing may resolve to the old or the
new value, taking 2 *or* 3 cycles — inside the cone of influence of user properties, then
re-proves them. This is the phase that exposes **reconvergence** bugs, which ordinary
FPV cannot see because it models synchronizers as exactly-2-cycle ideal flops.

Supporting commands:
```tcl
check_cdc -metastability -disable -pair <key>        ;# root-cause debug
check_cdc -metastability -injection_status -pair
check_cdc -metastability -export -time_window 2ns -dir ./sim_msi -report -force
check_cdc -metastability -export -to_formal -file ms.tcl
```
The simulation export generates injection models for a dynamic regression;
`-include_comboglitch` adds combinational-glitch injection (enabled in the simulator with
a `+define+`).

**Note on scope:** the properties re-proved here are *your* properties. A CDC run with no
user properties has nothing to re-prove, which is the natural point to bring an FPV
checker into the flow.

---

# Part 10 — Reporting and debug ✅

```tcl
file mkdir ./reports
check_cdc -report -setup     -file ./reports/setup.txt      -force
check_cdc -report -violation -detailed -file ./reports/violations.txt -force
check_cdc -report -property  -file ./reports/properties.txt -force
check_cdc -report -waiver -detailed -file ./reports/waivers.txt -force
check_cdc -report -signoff   -file ./reports/signoff.txt    -force
check_cdc -list pairs -file ./reports/pairs -force          ;# writes .csv
```

| Report | Contents |
|---|---|
| `-setup` | design statistics, every rule parameter in force, declared clocks/resets/port ratings, applied constraints |
| `-violation -detailed` | all violations with messages, keys and waiver status |
| `-property` | generated properties and their proof status |
| `-waiver -detailed` | waivers, their comments, and the checks each covers |
| `-signoff` | one bundled artifact: statistics, configuration delta, violations, waived violations, waivers |

Formats: text (default), `-html`, `-xml`, `-csv`.
Filters: `-severity`, `-domain`, `-category`, `-tag`, `-instance`,
`-waived (none | only …)`, `-grouping`.

**Order matters:** generate reports *after* adding waivers, or violations appear as
Error rather than Waived. ✅ Also ensure the output directory exists before the first
report write. ✅

Listing and debug:
```tcl
check_cdc -list ( pairs | schemes | violations | waivers | waiver_reasons
                | signal_config | domains | clock_groups | clock_matrix
                | clock_synchronicity | reset_order | rdc_pairs | user_properties
                | inactive_pairs | setup | ports | … )

check_cdc -debug -show_clock_domain <net>
check_cdc -debug -show_reset_domain <net>
check_cdc -show_schematic -signal <net> [-all | -driver | -port] [-context (cdc|rdc)]
```

Tool-internal nets appear in generated properties with a leading colon (e.g. `:tmp_757`)
and **cannot be added to a waveform**. Map them back to RTL signals through the relevant
RTL assignment and plot those instead. ✅

---

# Part 11 — Quick troubleshooting index ✅

| Symptom | Likely cause | Check |
|---|---|---|
| 0 CDC pairs, clean report | STA mode: clocks assumed synchronous | `check_cdc -list clock_synchronicity`; set `all_clocks_sync_by_default = false` |
| Data-stability CEX on a correct FIFO | `fifo_detection = false`, matched as a mux scheme | `check_cdc -list schemes` → Scheme Type |
| User-defined scheme ignored | a `-map` entry is not a port (`WCDC113` → `WCDC115`) | `check_cdc -list schemes` → Detection Type |
| Scheme accepted but analysis weaker | `-module` scheme is a black box; lost pointers/Q1/NDFF chain | compare connection maps |
| `PRT_IS_UNCK` | unrated primary ports | `config_rtlds -port … -clock <clock NAME>` |
| Property not generated, "unable to determine clock" | the scheme's connection map lacks the needed signal | `check_cdc -list schemes`, look for the missing formal signal |
| `RST_NO_SYNC` everywhere | resets declared `-async`, no reset synchronizer | fix the design or declare `-synchronized` **and record the assumption** |
| `-waiver -generate` produced nothing for a tag | no built-in reason exists for that tag | `check_cdc -list waiver_reasons` |
| Proof results vanished | `-waiver -prove` switched to both-edge sampling (`WCDC250`) | re-run the functional phase |
| Violation count looks too small | grouping | `-grouping none`, or read the detailed report |
| Report shows Error, not Waived | reports generated before waivers | move report commands after the waivers |
| `cd $ROOT` fails in the shell | `$ROOT` is a Tcl variable inside Jasper only | `export ROOT=$(git rev-parse --show-toplevel)` |

---

# Part 12 — A minimal correct flow ✅

```tcl
clear -all
check_cdc -init

analyze -sv09 <rtl files>          ;# RTL only, no verification checker
elaborate -top <top>

# clocks + relationship
config_rtlds -clock -create <clkA>
config_rtlds -clock -create <clkB>
config_rtlds -rule -parameter {all_clocks_sync_by_default = false}

# resets (choose the type deliberately; record any assumption)
config_rtlds -reset -synchronized <rstA> -clock <clkA_name> -polarity low

# scheme detection for the structures present
config_rtlds -rule -parameter {fifo_detection = true}

# port ratings (clock NAME, not signal name)
config_rtlds -port {<inputs>}  -clock <clkA_name>
config_rtlds -port {<outputs>} -clock <clkB_name>

check_cdc -setup
check_cdc -extract

# assert the prediction
set pairs [check_cdc -list pairs]
puts "CDC pairs found: [dict size $pairs]"
if {[dict size $pairs] == 0} { puts "ERROR: zero pairs -- clocks synchronous?" }

# custom design-specific checks, then functional proof
check_cdc -protocol_check -add <name> -expression {<template>} -scheme <type>
check_cdc -protocol_check -generate
check_cdc -protocol_check -prove

# waivers with evidence, then reports
set f [check_cdc -filter -add -tag <TAG>]
check_cdc -waiver -add -reason <reason> -filter $f -comment {<why, citing evidence>}

file mkdir ./reports
check_cdc -report -setup     -file ./reports/setup.txt -force
check_cdc -report -violation -detailed -file ./reports/violations.txt -force
check_cdc -report -property  -file ./reports/properties.txt -force
check_cdc -report -waiver -detailed -file ./reports/waivers.txt -force
check_cdc -report -signoff   -file ./reports/signoff.txt -force
```

---

## Closing principle

A CDC report is only as strong as the setup behind it. The two failure modes that matter
are **a clean report that checked nothing** and **a violation closed by assuming it
away**. Guard against the first by predicting results and asserting the prediction;
guard against the second by closing every violation with a fix, a proof, or a written
assumption — and never with an assumption that substitutes for a guard the design
already has.
