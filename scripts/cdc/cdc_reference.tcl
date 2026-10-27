# ==============================================================================
# MASTER REFERENCE TCL FOR JASPER CDC / RDC RUNS
# ==============================================================================
# This template contains the complete reference flow for Jasper CDC analysis,
# compiled directly from the Jasper CDC User Guide and Checks Reference Manual.
# Explanations and options are fully commented; functional commands remain active.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. INITIALIZATION & MULTI-THREADING SETUP
# ------------------------------------------------------------------------------
# Clear all previous design and formal session databases
clear -all

# Initialize the Jasper CDC verification environment
check_cdc -init

# set_parallel_synthesis_mode:
# Enables multi-threaded parallel compilation/synthesis across jg_frontend
# processes to significantly accelerate elaboration time for complex designs.
# Values: on | off (Default: off)
set_parallel_synthesis_mode on

# set_cdc_parallel_extraction:
# Splits the extraction rules across concurrent worker threads to reduce runtime.
# Values: <N> (0: allocate max threads, 1: sequential, 8: recommended; Default: 1)
set_cdc_parallel_extraction 8

# ------------------------------------------------------------------------------
# 2. DESIGN COMPILATION & ELABORATION
# ------------------------------------------------------------------------------
# analyze:
# Parses HDL source files (Verilog, SystemVerilog, VHDL).
# Syntax: analyze -sv09 | -sv | -v2k <file_list>
analyze -sv design.sv

# liberty -load:
# Loads Synopsys Liberty (.lib / .lib.gz) files for standard cells or hard macros.
# Must be executed prior to design elaboration so the tool infers clock/timing arcs.
liberty -load sample.lib

# config_rtlds -rule -load:
# Loads a customized CDC/RDC rule specification file (.def) overriding defaults.
config_rtlds -rule -load cdc.def

# elaborate:
# Builds the design hierarchy.
# -top: Specifies the top-level module
# -bbox_m: Treats listed modules as black-boxes
# -bbox_a: Treats parameterized architectures/modules as black-boxes
elaborate -top top -bbox_m {ip_block1 ip_block2}

# read_sdc:
# Loads Synopsys Design Constraints (SDC) to import clocks, groups, and port delays.
# Set 'set_cte_enable_session_tcl_env_restore true' prior to read_sdc to pass Tcl variables.
read_sdc design.sdc

# ------------------------------------------------------------------------------
# 3. GLOBAL CDC & RDC ENGINE PARAMETERS
# ------------------------------------------------------------------------------
# all_clocks_sync_by_default:
# Sets the clock analysis mode:
# - true  : STA Mode. All declared clocks are assumed synchronous by default.
# - false : Async Mode. All declared clocks are assumed asynchronous by default.
# (Default: true)
config_rtlds -rule -parameter {all_clocks_sync_by_default = false}

# automatic_scheme_detection:
# Controls whether automatic structural detection of synchronizer schemes runs.
# Disabling this also turns off automatic reset synchronizer detection.
# Values: true | false (Default: true)
config_rtlds -rule -parameter {automatic_scheme_detection = true}

# ndff_detection:
# Automatically detects N-flop (NDFF) synchronizer chains.
# Values: true | false (Default: true)
config_rtlds -rule -parameter {ndff_detection = true}

# strict_ndff_detection:
# If true, requires all flops in the NDFF synchronizer chain to belong strictly
# to the same hierarchy or parent instance.
# Values: true | false (Default: RTL = true, Gate-level = false)
config_rtlds -rule -parameter {strict_ndff_detection = true}

# allow_sync_chain_logic:
# Allows combinational logic between flops of an NDFF chain.
# When false, logic must conform to the sync_chain_logic parameter.
# Values: true | false (Default: false)
config_rtlds -rule -parameter {allow_sync_chain_logic = false}

# allow_sync_chain_fanout:
# Allows intermediate fanouts from internal stages of an NDFF synchronizer chain.
# Values: true | false (Default: false)
config_rtlds -rule -parameter {allow_sync_chain_fanout = false}

# pulse_detection / edge_detection:
# Automatically detects pulse and edge (AND/OR transition detector) synchronizers.
# Values: true | false (Default: true)
config_rtlds -rule -parameter {pulse_detection = true}
config_rtlds -rule -parameter {edge_detection = true}

# mux_loop_detection / mux_ndff_detection / mux_pulse_detection:
# Detects mux-based synchronizers. MUX_LOOP represents the core feedback loop.
# In releases >= 2024.12, mux_loop_detection defaults to true while mux_ndff_detection
# and mux_pulse_detection default to false.
config_rtlds -rule -parameter {mux_loop_detection = true}
config_rtlds -rule -parameter {mux_ndff_detection = false}
config_rtlds -rule -parameter {mux_pulse_detection = false}

# handshake_detection / fifo_detection:
# Controls automatic structural detection for handshake protocols and async FIFOs.
# Values: true | false (Default: false)
config_rtlds -rule -parameter {handshake_detection = true}
config_rtlds -rule -parameter {fifo_detection = true}

# gated_clock_detection:
# Automatically detects discrete clock gating structures.
# Values: true | false (Default: true)
config_rtlds -rule -parameter {gated_clock_detection = true}

# generated_clocks_sync_to_parents:
# Assumes generated clocks are structurally synchronous to their parent clock source.
# Values: true | false (Default: false)
config_rtlds -rule -parameter {generated_clocks_sync_to_parents = false}

# use_sdc_clock_period:
# Uses the -period switch from SDC create_clock to infer tool clock periods/factors.
# Values: true | false (Default: true)
config_rtlds -rule -parameter {use_sdc_clock_period = true}

# add_stopat_for_internal_constants / override_sdc_constants:
# Automatically creates environmental stopats at internal constants, top outputs,
# or blackbox inputs configured as constants in RTLDS or SDC.
# Values: true | false (Default: add_stopat=false, override_sdc=true)
config_rtlds -rule -parameter {add_stopat_for_internal_constants = false}
config_rtlds -rule -parameter {override_sdc_constants = true}

# report_violations_on_constant_load / report_violations_on_unconnected_load:
# Controls reporting of violations on constant or unconnected/dangling fanouts.
# Values: true | false (Default: false)
config_rtlds -rule -parameter {report_violations_on_constant_load = false}
config_rtlds -rule -parameter {report_violations_on_unconnected_load = false}

# apply_auto_waivers:
# Automatically waives structurally safe violations (e.g., constant/static loads).
# Values: true | false (Default: false)
config_rtlds -rule -parameter {apply_auto_waivers = true}

# treat_data_ports_as_async:
# Treats unrated design ports as asynchronous to all other internal logic.
# Values: all | none | primary_inputs | primary_outputs | primary_inouts | bbox_inputs | bbox_outputs
# (Default: none)
config_rtlds -rule -parameter {treat_data_ports_as_async = none}

# treat_undriven_as_units:
# Treats undriven nets as independent units in clock analysis.
# Values: true | false (Default: false)
config_rtlds -rule -parameter {treat_undriven_as_units = false}

# set_cdc_gate_level_analysis_mode:
# Enables gate-level CDC optimizations, loads cdc_gate_level.def, and enables
# Liberty function synthesis.
# Values: true | false (Default: false)
set_cdc_gate_level_analysis_mode false

# ------------------------------------------------------------------------------
# 4. CDC DOMAIN & CONVERGENCE PARAMETERS (-domain CDC)
# ------------------------------------------------------------------------------
# depth:
# Number of sequential flop stages after synchronization where the engine tracks
# convergence. Violations occurring beyond (n_min + depth) stages are ignored.
# Values: Integer >= 0 (Default: 0)
config_rtlds -rule -parameter {depth = 2} -domain CDC

# src_unit_domain:
# Filters convergence reporting based on whether sources belong to the same clock,
# different clocks, or both.
# Values: same | diff | both (Default: both)
config_rtlds -rule -parameter {src_unit_domain = both} -domain CDC

# src_unit_signal:
# Specifies whether convergence checks track paths originating from the same signal,
# different signals, or both.
# Values: same | diff | both (Default: both)
config_rtlds -rule -parameter {src_unit_signal = both} -domain CDC

# convergence_inside_ctrl_sync:
# Enables convergence checks between bits inside the control synchronizer logic itself.
# Values: true | false (Default: false)
config_rtlds -rule -parameter {convergence_inside_ctrl_sync = false} -domain CDC

# ignore_unsync_paths_in_convergence:
# Ignores unsynchronized paths when analyzing convergence into control synchronizers.
# Values: true | false (Default: true)
config_rtlds -rule -parameter {ignore_unsync_paths_in_convergence = true} -domain CDC

# group_fsm_convergences:
# Groups multi-bit convergences landing on FSM state registers into a single violation.
# Automatically waives if only a single asynchronous source triggers transitions.
# Values: true | false (Default: false)
config_rtlds -rule -parameter {group_fsm_convergences = true} -domain CDC

# flop_constant_propagation / latch_constant_propagation:
# Optimistically propagates constant values through flops/latches to simplify logic
# and eliminate inactive CDC crossings regardless of reset/clock states.
# Values: true | false (Default: false)
config_rtlds -rule -parameter {flop_constant_propagation = false} -domain CDC
config_rtlds -rule -parameter {latch_constant_propagation = false} -domain CDC

# use_only_rtl_constants_for_glitch_simplification:
# Restricts glitch logic simplification solely to hardcoded RTL constants rather
# than constraints defined via Tcl/SDC.
# Values: true | false (Default: false)
config_rtlds -rule -parameter {use_only_rtl_constants_for_glitch_simplification = false} -domain CDC

# liberty_clock_pin_as_datapath:
# Treats Liberty cell clock pins as standard datapath inputs during analysis.
# Values: true | false (Default: false)
config_rtlds -rule -parameter {liberty_clock_pin_as_datapath = false} -domain CDC

# ignore_convergence_from_complex_schemes:
# Suppresses CNV_ST_CONV convergence violations when inputs are synchronized
# by valid complex schemes (FIFO, Handshake, MUX).
# Values: true | false (Default: false)
config_rtlds -rule -parameter {ignore_convergence_from_complex_schemes = true}

# ------------------------------------------------------------------------------
# 5. RDC PARAMETERS (-domain RDC)
# ------------------------------------------------------------------------------
# auto_reset_sync_detection:
# Automatically detects reset synchronizer structures for declared reset nets.
# Values: true | false (Default: true)
config_rtlds -rule -parameter {auto_reset_sync_detection = true} -domain RDC

# strict_reset_scheme_detection:
# Enforces that all flops of a reset synchronizer reside in the same hierarchy.
# Values: true | false (Default: RTL = true, Gate-level = false)
config_rtlds -rule -parameter {strict_reset_scheme_detection = true} -domain RDC

# allow_reset_sync_chain_logic:
# Permits combinational logic between stages of reset synchronization chains.
# Values: true | false (Default: false)
config_rtlds -rule -parameter {allow_reset_sync_chain_logic = false} -domain RDC

# report_violations_on_undeclared_reset:
# Pessimistic reset mode. Reports RDC violations on paths driven by undeclared resets.
# Values: true | false (Default: false)
config_rtlds -rule -parameter {report_violations_on_undeclared_reset = false} -domain RDC

# ignore_internal_non_declared_resets:
# Prevents internal combinational nets feeding reset pins from being flagged as undeclared.
# Values: true | false (Default: false)
config_rtlds -rule -parameter {ignore_internal_non_declared_resets = true} -domain RDC

# ignore_non_resettable_flop:
# Suppresses RDC_RS_DFRS violations when destination sequential elements lack a reset pin.
# Values: true | false (Default: true)
config_rtlds -rule -parameter {ignore_non_resettable_flop = true} -domain RDC

# ignore_rdc_from_same_reset_source:
# Ignores RDC violations if source and destination share the same root reset source,
# regardless of intervening combinational logic.
# Values: true | false (Default: true)
config_rtlds -rule -parameter {ignore_rdc_from_same_reset_source = true} -domain RDC

# rtl_constant_for_reset_scheme:
# Requires the first flop of a classic reset synchronizer to tie to a hardcoded RTL constant.
# Values: true | false (Default: false)
config_rtlds -rule -parameter {rtl_constant_for_reset_scheme = false} -domain RDC

# treat_data_ports_reset_as_async:
# Treats unrated data port resets as asynchronous to all design resets.
# Values: all | none | primary_inputs | primary_outputs | primary_inouts | bbox_inputs | bbox_outputs
# (Default: none)
config_rtlds -rule -parameter {treat_data_ports_reset_as_async = none} -domain RDC

# ------------------------------------------------------------------------------
# 6. TAG-SPECIFIC RULE PARAMETERS
# ------------------------------------------------------------------------------
# n_min (-tag CDC_NO_SYNC):
# Minimum number of sequential flops required to qualify as an NDFF synchronizer.
# Values: Integer >= 1 (Default: 2)
config_rtlds -rule -parameter {n_min = 2} -tag CDC_NO_SYNC

# cdc_pair_logic (-tag CDC_PR_LOGC):
# Combinational logic allowed directly on an asynchronous crossing datapath.
# Values: wire | buf | logic | latch (Default: buf)
config_rtlds -rule -parameter {cdc_pair_logic = buf} -tag CDC_PR_LOGC

# do_not_report_unsynchronized_pair_logic (-tag CDC_PR_LOGC):
# Suppresses reporting combo logic violations if the path is already unsynchronized
# (prevents redundant violations with CDC_NO_SYNC).
# Values: true | false (Default: true)
config_rtlds -rule -parameter {do_not_report_unsynchronized_pair_logic = true} -tag CDC_PR_LOGC

# autowaive_reset_clamp_pair_logic (-tag CDC_PR_LOGC):
# Automatically waives CDC_PR_LOGC when datapath logic consists of an AND-gate reset
# clamp tied to a synchronous reset synchronizer output.
# Values: true | false (Default: false)
config_rtlds -rule -parameter {autowaive_reset_clamp_pair_logic = true} -tag CDC_PR_LOGC

# sync_chain_logic (-tag SYN_DF_SLGC):
# Specifies allowable logic between consecutive flops inside an NDFF synchronizer.
# Values: wire | buf | logic | latch (Default: buf)
config_rtlds -rule -parameter {sync_chain_logic = buf} -tag SYN_DF_SLGC

# glitch_check (-tag CNV_ST_GLCH):
# Specifies whether glitch analysis checks all combo reconvergences or only those
# that subsequently feed a destination synchronizer.
# Values: all | covered (Default: covered)
config_rtlds -rule -parameter {glitch_check = covered} -tag CNV_ST_GLCH

# autowaive_liberty_unclocked_ports_noarc (-tag PRT_IS_UNCK):
# Automatically waives unclocked port warnings on Liberty pins lacking internal timing arcs.
# Values: true | false (Default: true)
config_rtlds -rule -parameter {autowaive_liberty_unclocked_ports_noarc = true} -tag PRT_IS_UNCK

# reset_min_dff (-tag RST_NO_SYNC):
# Minimum flop depth required for reset synchronizer validation.
# Values: Integer >= 1 (Default: 2)
config_rtlds -rule -parameter {reset_min_dff = 2} -tag RST_NO_SYNC

# reset_sync_chain_logic (-tag SYN_RS_SLGC):
# Logic type permitted inside the reset synchronizer chain.
# Values: wire | buf | logic | latch (Default: buf)
config_rtlds -rule -parameter {reset_sync_chain_logic = buf} -tag SYN_RS_SLGC

# autowaive_rdc_with_ndff (-tag RDC_RS_DFRS):
# Automatically waives RDC_RS_DFRS if the crossing datapath contains an NDFF synchronizer.
# Values: true | false (Default: true)
config_rtlds -rule -parameter {autowaive_rdc_with_ndff = true} -tag RDC_RS_DFRS

# treat_boundaries_as_rdc (-tag RDC_RS_DFRS):
# Reports RDC violations on boundary ports lacking explicit reset associations.
# Values: true | false (Default: false)
config_rtlds -rule -parameter {treat_boundaries_as_rdc = false} -tag RDC_RS_DFRS

# different_reset_in_clock_paths (-tag RDC_RS_DFRS):
# Controls reporting of RDC violations located directly on clock trees.
# Values: true | false (Default: false)
config_rtlds -rule -parameter {different_reset_in_clock_paths = false} -tag RDC_RS_DFRS

# autowaive_reset_clear_logic (-tag RST_RS_CONV):
# Waives reset convergence violations if combinational logic arises solely from
# synthesis clear/preset circuitry. Must be applied prior to elaboration.
# Values: true | false (Default: true)
config_rtlds -rule -parameter {autowaive_reset_clear_logic = true} -tag RST_RS_CONV

# ignore_reset_in_datapath_for_control_sync (-tag RST_RS_RIDP):
# Ignores reset-in-datapath violations if destination logic is part of a valid control scheme.
# Values: true | false (Default: true)
config_rtlds -rule -parameter {ignore_reset_in_datapath_for_control_sync = true} -tag RST_RS_RIDP

# ------------------------------------------------------------------------------
# 7. CLOCK DECLARATIONS & DOMAIN RELATIONSHIPS
# ------------------------------------------------------------------------------
# config_rtlds -clock -create:
# Declares primary, generated, or inverted clocks.
# -factor: Clock frequency ratio relative to engine or reference clock
# -phase: Edge alignment phase offset
# Use '~clk' prefix to declare negative-edge triggered clocks.
config_rtlds -clock -create clk_src -factor 1 -phase 1
config_rtlds -clock -create clk_dst -factor 2 -phase 2
config_rtlds -clock -create ~clk_inv -factor 1 -phase 1

# Declaring internal signals or flop outputs as clocks requires removing existing drivers:
# stopat -env chip.core.clkgen.core_clk
# config_rtlds -clock -create chip.core.clkgen.core_clk

# Virtual clocks: Used to represent off-chip asynchronous clock domains
config_rtlds -clock -virtual vclk

# config_rtlds -clock -group:
# Explicitly sets synchronicity relationships between clock domains.
# Options: -async | -sync | -logically_exclusive | -physically_exclusive
config_rtlds -clock -group -async {{clk_src} {clk_dst}} -name GRP_ASYNC_1
config_rtlds -clock -group -sync  {{clk_src} {vclk}}    -name GRP_SYNC_1

# ------------------------------------------------------------------------------
# 8. RESET DECLARATIONS & ORDER SPECIFICATIONS
# ------------------------------------------------------------------------------
# config_rtlds -reset:
# Declares reset pins and synchronization types.
# -async        : Asynchronous assertion and de-assertion
# -sync         : Fully synchronous assertion and de-assertion (requires -clock)
# -synchronized : Output of a reset synchronizer (async assertion, sync de-assertion; requires -clock)
# -polarity     : high | low
# -virtual      : Reset originating outside current top-level boundary
config_rtlds -reset -async rst_async_n -polarity low
config_rtlds -reset -sync rst_sync_n -clock clk_src -polarity low
config_rtlds -reset -synchronized rst_dst_sync_n -clock clk_dst -polarity low
config_rtlds -reset -async vreset_n -polarity low -virtual

# check_cdc -reset -set_order:
# Establishes reset assertion precedence. Resets later in the list are asserted BEFORE
# earlier resets. Sub-lists denote resets asserted simultaneously.
# Used by structural analysis to automatically waive safe RDC paths.
check_cdc -reset -set_order {rst_async_n rst_dst_sync_n}

# ------------------------------------------------------------------------------
# 9. PORT & BOUNDARY RATING CONSTRAINTS
# ------------------------------------------------------------------------------
# config_rtlds -port:
# Maps boundary ports to explicit clock domains or abstract ratings.
# Abstract keywords:
# - sync_to_all  : Synchronous to every clock in the design
# - async_to_all : Asynchronous to every clock in the design
config_rtlds -port {data_in} -clock clk_src
config_rtlds -port {data_out} -clock clk_dst
config_rtlds -port {cfg_bus} -clock sync_to_all
config_rtlds -port {async_event_in} -clock async_to_all

# -external_sync:
# Informs the tool that an incoming port has already been synchronized outside the block.
# Allows qualification in MUX_NDFF, sync_enabler, or glitch_protector schemes.
config_rtlds -port ext_ctrl_ready -external_sync -destination_clock clk_dst -source_clock clk_src

# Reset port association (overrides automatic inference):
config_rtlds -port {data_in} -reset rst_async_n

# Blackbox module pin rating:
# Maps blackbox data ports to corresponding clock/reset pins of that module.
config_rtlds -port {rdata} -module dpram -clock rclk
config_rtlds -port {rdata} -module dpram -reset rrstn

# ------------------------------------------------------------------------------
# 10. CDC SIGNAL CONFIGURATIONS & DESIGN INTENT
# ------------------------------------------------------------------------------
# Constants:
# Ties undriven or internal signals to constant values.
# -condition defines a precondition verified during functional analysis.
config_rtlds -signal -constant {{test_mode 1'b0}}
config_rtlds -signal -constant {{data_gate 1'b0}} -condition {!gate_enable}

# Pseudo-Statics:
# Identifies quasi-static signals (e.g., config registers) that remain constant during operations.
# Flops/ports marked static make their corresponding CDC crossings inactive.
config_rtlds -signal -static {cfg_reg} -condition {sys_enable == 1'b1}

# Mutually Toggle Exclusive:
# Informs the tool that only one signal in the group can toggle at any given clock cycle.
# Prevents false convergence/glitch reports on bus re-convergence.
config_rtlds -signal -exclusive {mode_a_reg mode_b_reg mode_c_reg} -condition {en == 1'b1}

# Gray-Coded Bus:
# Informs the engine that multi-bit bus transitions adhere to Gray-code (single-bit flip).
config_rtlds -signal -gray_code {wptr_gray rptr_gray}

# CDC False Path:
# Deactivates CDC pairs along specific from/to/through structures.
# -from / -to / -through accept objects, clocks, or regular expressions with -regexp.
config_rtlds -signal -false_path -from clk_src -to clk_dst -through test_bypass

# Safe RDC Constraints:
# Informs the tool that clock/data are inactive when reset transitions, making RDC safe.
config_rtlds -signal -reset rst_async_n -on_assert -inactive_clock {clk_dst}
config_rtlds -signal -reset rst_async_n -on_deassert -constant_data {{data_in 1'b0}}

# Low-Power Control Signal Constraints:
# Defines timing relationships for isolation and retention controls.
config_rtlds -signal -power_control iso_ctrl -both -inactive_clock clk_dst
config_rtlds -signal -power_control save_ctrl -inactive_clock clk_dst -inactive_reset rst_async_n

# ------------------------------------------------------------------------------
# 11. USER-DEFINED & CUSTOM SYNCHRONIZERS
# ------------------------------------------------------------------------------
# Module-based NDFF, Pulse, Edge, MUX, and FIFO Synchronizers:
# check_cdc -scheme -add <type> -module <module_name> -map {{<formal> <actual>}+}
check_cdc -scheme -add ndff -module dff_sync -map {{data din} {dout dout}}
check_cdc -scheme -add pulse -module pulse_sync -map {{data din} {dout dout}}
check_cdc -scheme -add edge -module edge_sync -map {{data din} {dout dout} {activity high} {sensitivity rising}}
check_cdc -scheme -add mux_ndff -module cdc_mux -map {{data din} {dout dout} {sready sready} {dready dready}}
check_cdc -scheme -add fifo -module async_fifo -map {{rdata dout} {wdata din} {wfull full} {rempty empty} {winc wr_en} {rinc rd_en} {sclk wclk} {dclk rclk}}
check_cdc -scheme -add reset -module rst_sync -map {{dout rst_out} {srst rst_in} {dclk clk}}

# User-Defined Glitch Protector (AND-based):
check_cdc -scheme -add glitch_protector -module gp_cell -map {{dout gp_out} {gpdata gp_data} {control gp_en}}

# Synchronization Enabler:
# Informs the tool that control signal 'en_sync' safely qualifies crossings from source clocks to destination clock.
check_cdc -scheme -add sync_enabler -map {{enable en_sync} {srcdomainlist {clk_src}} {dstdomain clk_dst}}

# User-Defined ICG (Integrated Clock Gating) Cell:
check_cdc -scheme -add icg -module my_icg -map {{clkin clk_in} {enable en} {testenable te} {clkout clk_out}}

# Custom Synchronizer Scheme Definition:
# 1. Create custom synchronizer definition with formal signal interface
check_cdc -scheme -create my_custom_sync -formal_list {Data Dout Enable}
# 2. Map custom scheme to RTL module
check_cdc -scheme -add my_custom_sync -module custom_sync_mod -map {{Data din} {Dout dout} {Enable en}}
# 3. Add custom protocol assertions to verify custom scheme
check_cdc -protocol_check -add custom_sync_stability -expression {@(posedge %dclk) (%Enable) ##1 $stable(%Data)} -scheme my_custom_sync

# Glitch-free structural cells:
# Designates custom combinational cells as glitch-free to suppress false glitch violations.
check_cdc -glitch_free -add -module {glitch_free_mux glitch_free_and}

# ------------------------------------------------------------------------------
# 12. RUNNING CDC ANALYSIS (SETUP & STRUCTURAL)
# ------------------------------------------------------------------------------
# Rule Tag Severity/Enable Overrides:
config_rtlds -rule -enable -tag {CKS_IS_CONV CLK_IS_CONV CDC_PR_LOGC CNV_ST_BCNV CNV_ST_CONV CNV_ST_GLCH}
config_rtlds -rule -enable -tag {SYN_DF_RDND SYN_NO_TARG CDC_PR_INAC}

# check_cdc -setup:
# Validates clock/reset declarations, constant conflicts, unclocked ports, and SDC consistency
# before running heavy structural extraction.
check_cdc -setup

# check_cdc -extract:
# Executes full structural analysis (clock/reset trees, NDFF, convergence, glitches, and RDC).
check_cdc -extract

# Grouping violations:
# Contextually groups violations with common root causes on the Violation tree.
# Values: none | basic | advanced
check_cdc -violation -group basic

# ------------------------------------------------------------------------------
# 13. SMART WAIVERS & CONDITIONAL WAIVERS
# ------------------------------------------------------------------------------
# Structural Hierarchy Waiver:
# Waives all internal structural violations inside third-party/legacy IP while preserving boundary checks.
check_cdc -waiver -add -hierarchy {top.u_legacy_ip}

# Tag/Occurrence-based manual waivers:
check_cdc -waiver -add -filter [check_cdc -filter -add -tag CDC_NO_SYNC] -comment "Waived after manual architecture review"

# Smart Waivers (Reason-based formal waivers):
# Pre-defined reasons: STATIC_SRC, INACTIVE_SRC_RST, INACTIVE_SRC_CLK,
# SRC_ONEBIT_CHANGE, EXCLUSIVE_CLOCKS, INACTIVE_ENABLE, INACTIVE_DST_CLK,
# INACTIVE_DST_RST, UNREACHABLE_DST
check_cdc -waiver -add -filter [check_cdc -filter -add -tag CDC_NO_SYNC] -reason STATIC_SRC -comment "Source register is quasi-static"

# Auto-generating and proving Smart Waivers:
# Automatically generates SVA expressions for all possible smart waiver reasons and formalizes them.
check_cdc -waiver -generate
check_cdc -waiver -prove

# SDC / RTLDS Signal Configuration Proof:
# Formally verifies whether pseudo-static, constant, and exclusive constraints hold true in RTL.
config_rtlds -signal -prove

# ------------------------------------------------------------------------------
# 14. FUNCTIONAL ANALYSIS (PROTOCOL CHECKS)
# ------------------------------------------------------------------------------
# check_cdc -protocol_check -generate:
# Automatically generates SVA protocol assertions for all structurally verified synchronizers
# (data stability, FIFO full/empty flags, handshake 4-phase protocols, pulse stability).
check_cdc -protocol_check -generate

# check_cdc -protocol_check -prove:
# Formally verifies all protocol properties using the underlying Jasper formal engine.
check_cdc -protocol_check -prove

# Export protocol checks to simulation (for dynamic verification regression):
check_cdc -protocol_check -export -file formal_protocol_checks.sv -force -default_clock clk_dst

# Export signal configurations and conditional waivers to simulation:
check_cdc -export -type signal_config_property -default_clock clk_dst -file sim_signal_constraints.sv -force
check_cdc -export -type waiver_cond_property -user_assertions_only -default_clock clk_dst -file sim_waiver_checks.sv -force

# ------------------------------------------------------------------------------
# 15. METASTABILITY ANALYSIS (FORMAL & SIMULATION)
# ------------------------------------------------------------------------------
# Metastability Injection (MSI) in Formal:
# Injects random delay and metastability uncertainty into the cone-of-influence of user assertions.
check_cdc -metastability -inject -include_reset -include_protocol_check
check_cdc -metastability -prove

# Selectively disable/enable injection for root-cause debug:
# check_cdc -metastability -disable -pair <cdc_pair_key>
# check_cdc -metastability -enable -pair <cdc_pair_key>

# Metastability Injection (MSI) in Simulation:
# Generates SystemVerilog metastability injection models for Cadence Xcelium simulation.
# Produces 'global_meta_injection.sv' and '<top>_meta_injection.sv'.
# -time_window: Setup/hold violation window for random injection
# -include_comboglitch: Includes combinatorial glitch injection logic (+define+CDC_COMBOGLITCH in xrun)
check_cdc -metastability -export -file top_meta_injection.sv -time_window 2ns -dir ./sim_msi -include_reset -include_comboglitch -report -force

# ------------------------------------------------------------------------------
# 16. REPORTING & DEBUGGING UTILITIES
# ------------------------------------------------------------------------------
# Create reports directory
file mkdir ./cdc_reports

# check_cdc -report:
# Outputs comprehensive design status, setup issues, violations, and properties into files.
check_cdc -report -setup -file ./cdc_reports/setup_report.txt -force
check_cdc -report -violation -detailed -file ./cdc_reports/violations_detailed.rpt -force
check_cdc -report pairs -file ./cdc_reports/pairs_summary.csv -force
check_cdc -report rules -file ./cdc_reports/rules_summary.csv -force
check_cdc -report convergence_schemes -file ./cdc_reports/convergence_schemes.rpt -force
check_cdc -report -property -file ./cdc_reports/functional_properties.rpt -force

# Diagnostic and netlist tracing utilities (available after -extract):
# Query clock domain for target net:
# check_cdc -debug -show_clock_domain <signal_name>

# Query reset domain for target net:
# check_cdc -debug -show_reset_domain <signal_name>

# Lists active configurations, clocks, schemes, and pairs in console:
puts [check_cdc -list clock_synchronicity]
puts [check_cdc -list signal_config]
puts [check_cdc -list reset_order]
puts [check_cdc -list schemes]
puts [check_cdc -list pairs]
puts [check_cdc -list inactive_pairs]