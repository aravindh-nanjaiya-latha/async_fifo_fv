# CDC Verification — Approach and Decision Record

How CDC verification was brought up on this project, what went wrong, what was decided
and why. Written so that someone reviewing the repository can judge whether the clean
report means anything.

Companion documents:
- `docs/cdc/CDC_REFERENCE.md` — what the Jasper CDC App can do and how
- `docs/assumptions.md` — the obligations the results depend on
- `scripts/cdc/golden_cdc.tcl` — the runnable, annotated script
- `docs/cdc/golden_*.txt`, `golden_pairs.csv` — the tool output committed alongside

---

## 1. Objective and scope

Verify the clock-domain crossings of an asynchronous FIFO, and in doing so build a CDC
flow that is reproducible and whose results are defensible.

Two designs are involved:

| | Role |
|---|---|
| **Golden FIFO** (`golden_fifo/golden_afifo.sv`) | Known-good reference. Depth 16, `AW=4`, `DW=8`, gray-coded pointers, 2-FF synchronizers, registered read. |
| **Student FIFO** (`rtl/`) | The design under investigation. Depth 45 (non-power-of-two), pointers running 9→53, gray-coded, 2-FF synchronizers. Known bugs recorded in `docs/bug_report.md`. |

This document covers the golden run, which is complete. The student run follows.

---

## 2. Method: validate the environment before trusting it

The same principle used for the formal property checker was applied to the CDC setup:
**establish the environment on a design known to be correct, then move to the design
under investigation.**

The reasoning is specific rather than decorative. On a correct design:

- any violation is either a real property of the design, or a defect in the setup;
- any *clean* result can be checked against a prediction of what should have been found.

That second point turned out to matter more than the first. Two of the three significant
problems in this project were **false clean results** — the tool reporting nothing wrong
because it had been told to look at the wrong thing.

A deliberate scoping decision: the CDC run analyses **RTL only**. The formal property
checker and its bind are excluded, because the checker's scoreboard adds flops in the
write domain feeding properties in the read domain. Those would be identified as genuine
clock-domain crossings and would bury the design's own crossings in testbench noise.

---

## 3. Environment

| | |
|---|---|
| Tool | Jasper CDC App 2026.06 |
| Host | `deimos` (via `addpkg_shell`) |
| Not usable | `ruby` — Jasper is unsupported on its OS and sessions die with SIGBUS |
| Path handling | scripts resolve the repository root with `git rev-parse --show-toplevel`, so they run from any directory |

---

## 4. Chronology of problems and decisions

### 4.1 A clean report that checked nothing — clock synchronicity

**Observed.** First run: zero CDC pairs, zero violations.

**Expected.** Three crossings had been predicted in advance from the design structure:
the write gray pointer into the read domain, the read gray pointer into the write domain,
and the memory array into the registered output.

**Diagnosis.** The app defaults to STA mode (`all_clocks_sync_by_default = true`), in
which every declared clock is assumed synchronous to every other. With both clocks in one
family, no path qualifies as a crossing at all.

**Decision.** Switch to asynchronous mode:
```tcl
config_rtlds -rule -parameter {all_clocks_sync_by_default = false}
```
Result: 18 pairs, matching the prediction exactly — 1 for each gray pointer, 16 for the
memory words feeding the output register through the read mux.

**Process change adopted.** The prediction was the only thing that distinguished this
failure from success, so it was made part of the script rather than a habit:

```tcl
set pairs [check_cdc -list pairs]
if {[dict size $pairs] == 0} {
    puts "ERROR: zero CDC pairs -- clocks treated as synchronous?"
} elseif {[dict size $pairs] != 18} {
    puts "WARNING: pair count changed from the documented baseline of 18."
}
```

### 4.2 A counterexample on a correct design — wrong scheme type

**Observed.** With crossings now visible, the functional phase produced a `DAT_NO_STBL`
counterexample on the golden FIFO: *data path not stable long enough to be captured by
the destination clock*.

**Diagnosis.** `fifo_detection` defaults to **false**. Without it the tool matched the
memory-to-output path to a generic mux/enable scheme and generated the corresponding
check: *the selected word must not change while the capture enable is high*. A correct
FIFO violates that by design — back-to-back reads advance the read pointer, so the
read-mux output legitimately changes.

**Decision.** Enable FIFO recognition:
```tcl
config_rtlds -rule -parameter {fifo_detection = true}
```
All 18 pairs then collapsed into a single FIFO scheme (`Detection Type: Automatic`), with
the connection map binding the internal gray pointers, the synchronizer stage flops and
the NDFF chains. `DAT_NO_STBL` disappeared, as did the convergence violations at the
full/empty comparators — the FIFO scheme now owns those pointers.

**Generalisation recorded.** A functional counterexample may indicate the wrong *model*
rather than a design bug. Check the assigned scheme type before debugging a trace.

### 4.3 The central problem — the built-in FIFO checks ask an environment question

**Observed.** With the FIFO scheme in place, two new checks appeared and both failed on
the correct golden design:

| Check | Result |
|---|---|
| `POP_ON_EMTY` (`no_read_on_empty`) | CEX, 1 cycle |
| `PSH_ON_FULL` (`no_write_on_full`) | CEX, 17 cycles |

**Diagnosis.** The scheme's connection map binds `Rinc` to the raw request port `r_en`
and `Winc` to `w_en`. The checks therefore ask: *does anyone ever request a read while
empty?* That is a question about the **environment**, and the environment is
unconstrained. The design's protection is internal:

```systemverilog
assign rbin_next = rbin + (r_en & ~empty);
```

A request made while empty is legal at the interface and simply has no effect.

*(The 17-cycle length of the write-side counterexample is itself consistent: 16 writes to
fill a depth-16 FIFO, then one more request.)*

**Three candidate resolutions were considered.**

| Route | Mechanism | Outcome |
|---|---|---|
| **A** | `assume !(r_en && empty)` — constrain the environment | **Rejected** |
| **B1** | Wrapper module exposing an "effective pop" port, used in a user-defined scheme | **Rejected** |
| **B2 / C** | Express the design's own guard as a check and prove it | **Adopted** |

**Why A was rejected.** An assumption removes traces from every proof in the session.
The student FIFO's Bug 3 is an unguarded wrap branch:

```systemverilog
b_rptr_next = (b_rptr == 6'h36) ? 6'h09 : b_rptr + (r_en & ~empty);
```

Its failing trace is exactly `r_en = 1` while `empty = 1`. Assuming that away makes the
bug unreachable and the report comes back clean. The tool's own guidance suggests writing
such assumptions "if the FIFO itself is the DUT", with the caveat *confirm the assumptions
are valid in the given design scenario*. In this scenario the valid statement is an
assertion about the design, not an assumption about the environment — the same intent,
with the arrow pointing the other way.

**Why B1 was rejected.** See 4.4.

### 4.4 User-defined schemes are port-level, and fail soft

An attempt to remap `Rinc` to the effective pop condition through a user-defined scheme:

```tcl
check_cdc -scheme -add fifo -module gold_top -map { … {rinc {r_en & ~empty}} … }
```

produced:

```
WARNING (WCDC113): The argument "rinc" must be a port of the module.
WARNING (WCDC115): No valid arguments found for map. Ignoring the command.
```

Two findings, both important beyond this case:

1. **Every `-map` entry must be a port.** Neither an expression nor an internal net is
   accepted.
2. **One bad entry drops the entire map** and the tool falls back to automatic detection
   *silently* — the run completes and looks normal. Only
   `check_cdc -list schemes` reveals `Detection Type: Automatic` instead of
   `UserDefined`.

A map that *was* accepted (all ports, no expressions) turned out to be worse than useless
here: the resulting scheme lost `Wptr`/`Rptr`, the `Q1` synchronizer flops and the NDFF
chains. A `-module` scheme describes the block as a **black box**. For a design whose
internals are the subject of verification, automatic detection is strictly better.

**Decision.** Keep automatic detection. Remove the user-defined scheme entirely. A
control run with the command commented out produced byte-identical results, confirming it
had been inert.

### 4.5 The resolution — custom protocol checks on the auto-detected scheme

`check_cdc -protocol_check -add` takes an SVA template written against the scheme's
**formal** signal names, which the tool resolves from the scheme's connection map. On an
automatically detected scheme that map is already bound to internal nets — so a template
referring to `%rptr` reaches the internal gray pointer, without the port restriction that
blocked the scheme remap.

```tcl
check_cdc -protocol_check -add no_pop_on_empty \
  -expression {@(posedge %dclk) (%rinc && %rempty) |=> $stable(%rptr)} -scheme fifo

check_cdc -protocol_check -add no_push_on_full \
  -expression {@(posedge %sclk) (%winc && %wfull) |=> $stable(%wptr)} -scheme fifo
```

In words: *a request made while the FIFO cannot service it must not move the pointer.*

Result on the golden:

| Property | Status |
|---|---|
| `CDC_data_out_no_pop_on_empty` | **proven** |
| `CDC_data_out_no_push_on_full` | **proven** |
| `CDC_data_out_no_read_on_empty` (built-in) | cex, 1 cycle |
| `CDC_data_out_no_write_on_full` (built-in) | cex, 17 cycles |

Two properties about the design's own guard, proven by the tool, with **no assumption
added** — every trace remains reachable.

**Why the condition is not a tautology.** It asserts *the pointer did not move*, not
*the guard expression is true*. Mapping it to a hand-written `r_en && !empty` would make
the check true by construction and it would pass on any design, including a broken one.
Because it is written in terms of observable pointer movement, the student FIFO's
unguarded wrap branch should produce a counterexample.

### 4.6 Closing the built-in checks — waivers with cited evidence

`check_cdc -list waiver_reasons` showed **no built-in reason exists for `POP_ON_EMTY` or
`PSH_ON_FULL`**. Consequently `check_cdc -waiver -generate` never attempted them; all 20
auto-generated waivers in the session targeted `RST_NO_SYNC`, and all 20 came back
**Unsafe** — both standard hypotheses (*source reset inactive*, *destination clock
inactive when reset is deasserted*) were refuted by the prover.

That left `SEE_COMMENTS`, which is `Unvalidatable` by construction. It was used
deliberately, with the comment carrying the evidence:

```tcl
set f_pop [check_cdc -filter -add -tag POP_ON_EMTY]
check_cdc -waiver -add -reason SEE_COMMENTS -filter $f_pop \
  -comment {Rinc maps to the raw request port r_en, so this check asks whether the
  environment ever requests a read while empty. The FIFO guards pops internally
  (rbin_next = rbin + (r_en & ~empty)), so a request on empty has no effect. Proven in
  this session by CDC_data_out_no_pop_on_empty.}
```

**The distinction being relied on:** an assumption *deletes* an obligation; a waiver
backed by a proof *discharges* it elsewhere. The waiver text appears inline in the
violation report, so a reviewer sees the claim and the name of the property that
establishes it without opening another file.

### 4.7 Port ratings, and a hypothesis that failed

Seven `PRT_IS_UNCK` warnings: primary ports have no internal flop from which to infer a
domain, so the tool cannot tell whether paths through them cross domains.

```tcl
config_rtlds -port {w_en data_in} -clock w_clk_n0    ;# clock NAME, not signal name
config_rtlds -port {r_en}         -clock r_clk_n1
config_rtlds -port {w_ptr}        -clock w_clk_n0
config_rtlds -port {r_ptr}        -clock r_clk_n1
config_rtlds -port {w_en data_in w_ptr} -reset wrst_n
config_rtlds -port {r_en r_ptr}         -reset rrst_n
```

Setup violations fell from 7 to 2. The two that remain are the clock ports `w_clk` and
`r_clk` themselves — the "port used as both clock and data" case, which is expected
rather than a gap.

**A hypothesis that was wrong, recorded because the correction is the useful part.** Two
FIFO data-stability checks were not being generated:

```
WARNING (WCDC238): Unable to generate property "CDC_data_out_put_not_stable" …
                   Reason: "Unable to determine clock."
```

These were predicted to be caused by the unrated ports. Adding the ratings changed
nothing. Inspection of the scheme's connection map gave a better explanation: it binds
`Rdata` but has **no `Wdata` entry at all**, because `data_in` never crosses a clock
domain in this design — it is captured by the memory array in the write domain, and only
the memory-to-output path crosses. With no write-data signal bound to the scheme, the
put-side check has nothing to build from.

This remains a stated hypothesis rather than a confirmed root cause: the tool's message
says "unable to determine clock", which does not literally mean "missing signal". The
read-side equivalent is covered on the formal-property side by `chk_fv_stable_dout`.

**Side benefit confirmed.** Port ratings constrain input behaviour, so they can
over-constrain. `:noConflict` and `:noDeadEnd` proven and `:live` covered showed they did
not.

### 4.8 The gray-code declaration — inert here, dangerous later

The declaration `config_rtlds -signal -gray_code {wgray rgray}` had been added to
auto-waive the convergence violations at the full/empty comparators. Two findings:

**It became inert.** Once FIFO detection was enabled those convergence violations no
longer appeared at all. Verified empirically: the violation report is byte-identical with
and without the declaration (two runs, one minute apart, `diff` of both files empty). It
was removed — an inert setting that looks meaningful misleads the next reader.

**Declaring several signals in one command is wrong.** `check_cdc -list signal_config`
showed the tool had built a single expression over the **concatenation**:

```
##1 $changed({rgray, wgray}) |-> $onehot({rgray, wgray} ^ $past({rgray, wgray}))
```

A sampling instant in which each pointer independently advances by one bit shows two set
bits and fails, although both behaved correctly. The two pointers are in unrelated clock
domains and nothing prevents them moving at the same sampled instant. If the declaration
is ever needed, it must be one signal per command.

**The carry-forward, which is the important part.** The tool **believes** signal
configurations; it does not prove them. On the student FIFO the wrap `gray(53) → gray(9)`
changes **two** bits — the declaration would be false, and would auto-waive the very
convergence violation that exposes it. Decision recorded: **do not declare gray coding on
the student design.** The claim belongs to the formal property `chk_wgray_onehot0`, which
will produce a counterexample at the wrap.

The division of labour agreed here: CDC states design intent; FPV establishes whether the
design honours it. With one condition — once FPV disproves the claim, the declaration
cannot stay. A declaration known to be false is not an assumption, it is a defect in the
setup.

### 4.9 Resets — where an assumption *is* the right answer

Ten `RST_NO_SYNC` occurrences (displayed as 2 because of violation grouping):
`wrst_n` → full, wbin, wgray, rgray_sync, rq1 and `rrst_n` → empty, rbin, rgray,
wgray_sync, wq1.

`gold_top` has no reset synchronizer; both resets drive the flops' asynchronous reset pins
directly. Asserting an async reset is safe; *releasing* it is the hazard — a release close
to a clock edge can violate recovery/removal timing, leaving flops metastable or exiting
reset in different cycles.

Three options were weighed: fix the RTL by adding reset synchronizers; declare the reset
type; or waive. Waiving was weakest — both auto-generated reasons had already been
refuted by the prover.

**Decision: declare the reset type, and record the assumption.**

```tcl
config_rtlds -reset -synchronized wrst_n -clock w_clk_n0 -polarity low
config_rtlds -reset -synchronized rrst_n -clock r_clk_n1 -polarity low
```

`-synchronized` means *output of a reset synchronizer*: asynchronous assertion,
synchronous de-assertion. It states the block's interface contract. The RDC section then
disappeared from the violation report.

**Why an assumption is acceptable here when it was rejected in 4.3.** In the push/pop
case the design protects itself, so there was an internal guard to assert and prove.
Reset release timing is genuinely a property of whoever drives the reset — there is
nothing internal to assert. The obligation is external, and the honest action is to
declare it and write it down. It is recorded as **A1** in `docs/assumptions.md`, with the
evidence of what happens without it.

> **The rule that came out of this project:** if the design protects itself, assert the
> guard and prove it. If it does not, the obligation is external — declare it and record
> it. An assumption standing in for a guard that exists is never acceptable.

Note that this is a different issue from student **Bug 1**, which concerns the
synchronizer's reset *value* (reset to 0 where gray(9) is required), not release timing.

---

## 5. Final state — golden FIFO

| | |
|---|---|
| Setup violations | **2** warnings (`PRT_IS_UNCK` on the clock ports) |
| CDC pairs | **18**, matching the prediction |
| Scheme | **1 FIFO**, `Detection Type: Automatic`, internals bound |
| Custom protocol checks | **2 proven** |
| Built-in request-side checks | **2 waived**, each citing a proven property |
| RDC | **none** — closed by assumption A1 |
| **Errors** | **0** |

Every violation is absent, waived against a proof produced in the same session, or
standing against a written assumption. The script carries an expected-result block in its
header and reproduces this state from a clean checkout.

### Open items

1. **`WCDC238` ×2** — `put_not_stable` / `get_not_stable` not generated. The
   auto-detected scheme binds `Rdata` but not `Wdata`; `data_in` does not cross a clock
   domain in this RTL. Read-side data stability is covered by FPV `chk_fv_stable_dout`.
2. **`PRT_IS_UNCK` ×2** — the clock ports themselves; the "port used as both clock and
   data" case.
3. **Metastability phase not yet run.** It re-proves *user* properties under injected
   synchronizer uncertainty, so it becomes meaningful once the formal checker is brought
   into the flow. That is the natural next escalation after the student run.

---

## 6. What carries to the student FIFO

1. **Do not declare the pointers gray-coded.** The 53→9 wrap is a two-bit change; the
   declaration would be false and would auto-waive the violation that exposes it (4.8).
2. **Check whether the FIFO scheme is auto-detected at all** at depth 45 with pointers
   based at 9. If it is not, the convergence violations return and the triage changes
   shape — and the gray-code question in (1) becomes live immediately.
3. **The two custom protocol checks should produce counterexamples**, because Bug 3's
   wrap branch moves the read pointer regardless of `empty`. The same check that proved
   on a correct design catching the bug on a broken one is the result this approach was
   built to produce.
4. **Reset handling differs.** The student design's Bug 1 is a synchronizer reset
   *value* problem, not a release-timing problem, so assumption A1 does not transfer
   unexamined.

---

## 7. Principles this project produced

1. **Predict before you read.** A report that found nothing is indistinguishable from a
   correct design unless you wrote down what you expected to find. Two of three major
   problems here were false clean results.
2. **Assert the prediction in the script.** Habits fail; a failing script does not.
3. **Verify that configuration took effect.** Several commands fail soft — a rejected
   scheme map falls back to automatic detection, an inert signal config changes nothing.
   `check_cdc -list schemes` and `-list signal_config` are the checks.
4. **A counterexample may indict the model, not the design.** Confirm the scheme type and
   what the generated property actually says before debugging a trace.
5. **Close violations with a fix, a proof, or a written assumption — never by assuming
   away the trace that would expose a bug.**
6. **Record assumptions where a reviewer will find them.** A clean report plus an
   unrecorded assumption is worse than an honest violation.
7. **Tools believe their configuration.** Signal configurations, scheme maps and reset
   types are claims. Some are provable; make the provable ones proven, and write the rest
   down.
