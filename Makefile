# Makefile - ALU-FIFO: Verilator verification and Sky130 HD implementation flow.
# Target names follow the Full-Adder project; the verification targets are new.
# Spec: docs/superpowers/specs/2026-10-19-alu-fifo-design.md

# Tool commands
VERILATOR ?= verilator
YOSYS     ?= yosys
OPENSTA   ?= sta
OPENROAD  ?= openroad
GTKWAVE   ?= gtkwave
PYTHON    ?= python3

# Run parameters (override on the command line, e.g. make sim SEED=7 DEPTH=4)
SEED          ?= 1
NCMD          ?= 20000
DEPTH         ?= 8
CLK_PERIOD_NS ?= 10.0
CORE_UTILIZATION ?= 40
# The clock period and the floorplan utilisation reach the SDC and the OpenROAD scripts through the environment.
export CLK_PERIOD_NS
export CORE_UTILIZATION

# Sources. The package is always first.
RTL := rtl/alu_pkg.sv rtl/alu.sv rtl/sync_fifo.sv rtl/alu_fifo_top.sv
# Checkers and binds (verif/), then the testbench. Yosys never reads these.
CHECKERS := verif/sync_fifo_checker.sv verif/alu_fifo_checker.sv verif/checker_binds.sv
VERIF    := $(CHECKERS) verif/tb_alu_fifo.sv
# absolute path: Verilator's generated sub-make runs inside the build directory
MAIN_CPP := $(abspath verif/sim_main.cpp)

BUILD_DIR   := build
REPORT_DIR  := $(BUILD_DIR)/reports
RESULTS_DIR := pnr_results

# Warnings relaxed for the testbench build only (never for rtl/, which lints with -Wall):
#  DECLFILENAME  the testbench file holds one module named tb_alu_fifo - harmless
#  UNUSEDSIGNAL  testbench signals are probed in waveforms, not all read
#  UNUSEDPARAM   likewise for parameters
TB_WNO := -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM

SIM_BUILD := $(BUILD_DIR)/sim_d$(DEPTH)
SIM_EXE   := $(SIM_BUILD)/Vtb_alu_fifo
VFLAGS    := --cc --exe --build --timing --assert --x-initial unique \
             --top-module tb_alu_fifo -GDEPTH=$(DEPTH) $(TB_WNO)
# Verilator's own seed (random memory init) must be in 1..2147483647, so map SEED into that range;
# the TB's +seed= takes SEED unchanged. Same SEED -> same VSEED -> same run.
VSEED     := $(shell echo $$(( ($(SEED) % 2147483646) + 1 )))
SIM_ARGS  := +seed=$(SEED) +ncmd=$(NCMD) +verilator+seed+$(VSEED) +verilator+rand+reset+2

# Seeds that must not produce degenerate stimulus: 0, and 0x9E3779B9 (the TB's xorshift state would
# be 0 for it without the nonzero guard).
SEED_LIST    := 0 2654435769
DEPTH_LIST   := 2 4 16
MIN_DISTINCT := 1000

.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "Available targets:"
	@echo "  make lint           - Verilator -Wall lint of rtl/ (zero warnings required)"
	@echo "  make rules          - RTL style gate (always_comb / always_ff @(posedge clk) only, no initial, SVA, tri-state)"
	@echo "  make rules-selftest - each bad fixture must be stopped by the one rule it is bound to"
	@echo "  make sim            - build and run the testbench (SEED=, NCMD=, DEPTH=); VCD in $(SIM_BUILD)/waveform.vcd"
	@echo "  make sim-seeds      - seeds 0 and 0x9E3779B9 give varied stimulus; SEED=1 reproduces exactly"
	@echo "  make sim-depths     - DEPTH=2, 4 and 16 build and pass"
	@echo "  make cov            - coverage run: every named cover bin hit, rtl/ lines covered (reports in $(REPORT_DIR)/)"
	@echo "  make cov-selftest   - cov_check.py must fail on a zero-hit bin, an uncovered line, a stale exclusion"
	@echo "  make synth          - Yosys synthesis to Sky130 HD -> $(BUILD_DIR)/synth.v, $(REPORT_DIR)/stat.txt"
	@echo "  make synth-selftest - each synthesis check must stop the bad input it is bound to"
	@echo "  make synth-selftest-deep - delete / neutralise each check in turn; the selftest must notice"
	@echo "  make sta            - OpenSTA on the netlist with the SDC; the SDC readback is checked -> timing.txt, power_report.txt"
	@echo "  make pnr            - OpenROAD floorplan, place, CTS, repair, route, extract -> $(RESULTS_DIR)/ (PNR_STOP_AFTER=repair to stop early)"
	@echo "  make pnr-selftest   - pnr_check.sh must reject a run that stopped early, a stale or mismatched results directory"
	@echo "  make pnr-check      - read the OpenROAD run back and fail on anything wrong (PNR_CHECK_MODE=partial|full)"
	@echo "  make all            - synth + sta + pnr (as in Full-Adder)"
	@echo "  make summary        - key figures read from the reports; NOT YET MEASURED where a report is missing"
	@echo "  make summary-selftest - summary.sh parsing and its NOT YET MEASURED fallback, on synthetic reports"
	@echo "  make view           - open the routed design in the OpenROAD GUI (needs a display)"
	@echo "  make sta-selftest   - check_sdc.py must reject a wrong period, delay, driving cell or load in the SDC readback"
	@echo "  make check          - lint, rules, sim, seeds, depths, cov, mutants and their self-tests"
	@echo "  make mutants        - inject each verif/mutants/*.mut bug; every one must be caught by its intended check"
	@echo "  make wave           - open the VCD in GTKWave"
	@echo "  make clean          - remove build/"
	@echo "  make distclean      - remove build/ and $(RESULTS_DIR)/"
	@echo "Override: make SEED=7 DEPTH=4 CLK_PERIOD_NS=10.0"

# --------------- Lint and RTL style gate ---------------

.PHONY: lint
lint:
	@echo "[LINT] verilator --lint-only -Wall rtl/"
	@$(VERILATOR) --lint-only -Wall --top-module alu_fifo_top $(RTL) && echo "[LINT] clean"

.PHONY: rules
rules:
	@scripts/rules.sh rtl && echo "rules: clean"

.PHONY: rules-selftest
rules-selftest:
	@scripts/rules_selftest.sh

# --------------- Simulation ---------------

$(SIM_EXE): $(RTL) $(VERIF) $(MAIN_CPP)
	@echo "[SIM ] Building testbench (DEPTH=$(DEPTH))..."
	@mkdir -p $(SIM_BUILD)
	@$(VERILATOR) $(VFLAGS) --trace --Mdir $(SIM_BUILD) $(RTL) $(VERIF) $(MAIN_CPP) \
	    > $(SIM_BUILD)/verilator.log 2>&1 || { tail -n 40 $(SIM_BUILD)/verilator.log; exit 1; }

.PHONY: sim
sim: $(SIM_EXE)
	@echo "[SIM ] Running (SEED=$(SEED) DEPTH=$(DEPTH))..."
	@$(SIM_EXE) $(SIM_ARGS) +vcd=$(SIM_BUILD)/waveform.vcd > $(SIM_BUILD)/run.log 2>&1; rc=$$?; \
	    cat $(SIM_BUILD)/run.log; \
	    if [ $$rc -ne 0 ] || ! grep -q '^TB PASS' $(SIM_BUILD)/run.log; then \
	        echo "[SIM ] FAILED (exit $$rc)"; exit 1; fi

.PHONY: wave
wave:
	@$(GTKWAVE) $(SIM_BUILD)/waveform.vcd >/dev/null 2>&1 &

# Review Focus 4: odd seeds give varied stimulus, and one seed reproduces its run exactly.
.PHONY: sim-seeds
sim-seeds: $(SIM_EXE)
	@set -e; for s in $(SEED_LIST); do \
	    out=$$($(MAKE) --no-print-directory sim SEED=$$s 2>&1) || { echo "$$out"; echo "[SEEDS] seed $$s FAILED"; exit 1; }; \
	    d=$$(echo "$$out" | sed -n 's/^TB STATS distinct_cmds=\([0-9][0-9]*\).*/\1/p'); \
	    if [ -z "$$d" ] || [ "$$d" -lt $(MIN_DISTINCT) ]; then echo "$$out"; \
	        echo "[SEEDS] seed $$s: distinct_cmds='$$d' (< $(MIN_DISTINCT)): degenerate stimulus"; exit 1; fi; \
	    echo "[SEEDS] seed $$s ok (distinct_cmds=$$d)"; \
	done; \
	a=$$($(MAKE) --no-print-directory sim SEED=1 2>&1 | grep -E '^TB (PASS|STATS)'); \
	b=$$($(MAKE) --no-print-directory sim SEED=1 2>&1 | grep -E '^TB (PASS|STATS)'); \
	if [ -z "$$a" ] || [ "$$a" != "$$b" ]; then echo "[SEEDS] SEED=1 is not reproducible:"; echo "$$a"; echo "$$b"; exit 1; fi; \
	echo "[SEEDS] SEED=1 reproduces byte-identically"

# Review Focus 5: the design is parameterised, so DEPTH other than 8 must build and pass.
.PHONY: sim-depths
sim-depths:
	@set -e; for d in $(DEPTH_LIST); do \
	    out=$$($(MAKE) --no-print-directory sim DEPTH=$$d 2>&1) || { echo "$$out"; echo "[DEPTHS] DEPTH=$$d FAILED"; exit 1; }; \
	    echo "[DEPTHS] DEPTH=$$d: $$(echo "$$out" | grep '^TB PASS')"; \
	done

# --------------- Coverage ---------------
# Same testbench, built with --coverage (line, toggle and the named cover property bins).
# scripts/cov_check.py fails the target on any zero-hit bin or any uncovered rtl/ line that is
# not listed, with a reason, in verif/cov_exclusions.txt.

COV_BUILD := $(BUILD_DIR)/cov_d$(DEPTH)
COV_EXE   := $(COV_BUILD)/Vtb_alu_fifo
COV_DAT   := $(COV_BUILD)/coverage.dat
COV_CHECK  = $(PYTHON) -I scripts/cov_check.py $(1) --rtl-dir rtl --exclusions verif/cov_exclusions.txt \
                 --bins-out $(REPORT_DIR)/coverage_bins.txt --summary-out $(REPORT_DIR)/coverage_summary.txt \
                 --toggle-out $(REPORT_DIR)/coverage_toggle_unhit.txt

$(COV_EXE): $(RTL) $(VERIF) $(MAIN_CPP)
	@echo "[COV ] Building coverage testbench (DEPTH=$(DEPTH))..."
	@mkdir -p $(COV_BUILD)
	@$(VERILATOR) $(VFLAGS) --coverage --Mdir $(COV_BUILD) $(RTL) $(VERIF) $(MAIN_CPP) \
	    > $(COV_BUILD)/verilator.log 2>&1 || { tail -n 40 $(COV_BUILD)/verilator.log; exit 1; }

.PHONY: cov
cov: $(COV_EXE)
	@mkdir -p $(REPORT_DIR)
	@echo "[COV ] Running (SEED=$(SEED) DEPTH=$(DEPTH))..."
	@$(COV_EXE) $(SIM_ARGS) +cov_file=$(COV_DAT) > $(COV_BUILD)/run.log 2>&1; rc=$$?; \
	    if [ $$rc -ne 0 ] || ! grep -q '^TB PASS' $(COV_BUILD)/run.log; then \
	        tail -n 20 $(COV_BUILD)/run.log; echo "[COV ] testbench FAILED (exit $$rc)"; exit 1; fi
	@$(call COV_CHECK,$(COV_DAT))
	@rm -rf $(REPORT_DIR)/cov_annotated
	@verilator_coverage --annotate $(REPORT_DIR)/cov_annotated $(COV_DAT) > /dev/null
	@echo "[COV ] reports: $(REPORT_DIR)/coverage_bins.txt coverage_summary.txt coverage_toggle_unhit.txt cov_annotated/"

.PHONY: cov-selftest
cov-selftest:
	@scripts/cov_selftest.sh

# --------------- Mutation run: do the checks catch real bugs? ---------------
# Each verif/mutants/*.mut is one deliberate RTL bug (applied to a copy of rtl/). scripts/mutants.py
# builds and runs each with the checkers, reports which checks fired, and re-runs it with the intended
# assertion removed to show whether another check still catches it. Slow: two Verilator builds per mutant.
MUTANT_JOBS ?= $(shell echo $$(( ($$(nproc) + 1) / 2 )))

.PHONY: mutants-selftest
mutants-selftest:
	@$(PYTHON) -I scripts/mutants.py --selftest

.PHONY: mutants
mutants: mutants-selftest
	@mkdir -p $(REPORT_DIR)
	@$(PYTHON) -I scripts/mutants.py --vflags "$(VFLAGS)" --rtl $(RTL) --verif $(VERIF) --main-cpp $(MAIN_CPP) \
	    --sim-args "$(SIM_ARGS)" --jobs $(MUTANT_JOBS) --report $(REPORT_DIR)/mutants.txt $(if $(MUTANT_ONLY),--only $(MUTANT_ONLY))

# Everything that can fail, in one command: the RTL gates, the simulations, the coverage gate and the
# mutation run, plus the self-tests that prove those gates can fail. Exits non-zero on the first failure.
.PHONY: check
check: lint rules rules-selftest sim sim-seeds sim-depths cov cov-selftest mutants
	@echo "[CHECK] all gates passed"

# --------------- Synthesis (Yosys) ---------------
# scripts/synth.ys runs the RTL-level checks and maps to Sky130 HD; scripts/netlist_check.ys then reads the
# written netlist back and checks the artifact itself. Both are templates: the Makefile fills in the
# sources, the clock period (single source: CLK_PERIOD_NS) and the library paths.
PERIOD_PS   := $(shell awk 'BEGIN{printf "%d", $(CLK_PERIOD_NS)*1000}')
FULL_LIB    := sky130hd/sky130hd_tt.lib
SYNTH_LIB   := $(BUILD_DIR)/sky130hd_synth.lib
NETLIST     := $(BUILD_DIR)/synth.v
STAT_RPT    := $(REPORT_DIR)/stat.txt
TOP         := alu_fifo_top

$(SYNTH_LIB): $(FULL_LIB) scripts/prune_lib.py
	@mkdir -p $(BUILD_DIR)
	@$(PYTHON) -I scripts/prune_lib.py $(FULL_LIB) $(SYNTH_LIB) --drop sky130_fd_sc_hd__lpflow_ --drop sky130_fd_sc_hd__probe

.PHONY: synth
synth: $(NETLIST)
	@echo "[SYNTH] Netlist ready: $(NETLIST)"

# CLK_PERIOD_NS is not a file, so a stamp records it: the netlist (and later the layout) rebuild when it changes.
PERIOD_STAMP := $(BUILD_DIR)/period.stamp
.PHONY: FORCE
FORCE:
$(PERIOD_STAMP): FORCE
	@mkdir -p $(BUILD_DIR)
	@echo "$(CLK_PERIOD_NS)" | cmp -s - $@ || echo "$(CLK_PERIOD_NS)" > $@

$(NETLIST): $(RTL) scripts/synth.ys scripts/netlist_check.ys $(SYNTH_LIB) $(PERIOD_STAMP) Makefile
	@echo "[SYNTH] Running Yosys (CLK_PERIOD_NS=$(CLK_PERIOD_NS))..."
	@mkdir -p $(REPORT_DIR)
	@rm -f $(STAT_RPT) $(NETLIST)
	@sed -e "s|@SOURCES@|$(RTL)|g" -e "s|@TOP@|$(TOP)|g" -e "s|@LIB@|$(SYNTH_LIB)|g" \
	     -e "s|@PERIOD_PS@|$(PERIOD_PS)|g" -e "s|@OUTDIR@|$(BUILD_DIR)|g" scripts/synth.ys > $(BUILD_DIR)/synth_run.ys
	@$(YOSYS) -q -l $(BUILD_DIR)/synth.log -s $(BUILD_DIR)/synth_run.ys >/dev/null 2>&1 || { grep -E '^CHECK|ERROR' $(BUILD_DIR)/synth.log | tail -n 5; exit 1; }
	@echo "[SYNTH] Checking the written netlist..."
	@sed -e "s|@NETLIST@|$(NETLIST)|g" -e "s|@TOP@|$(TOP)|g" -e "s|@FULL_LIB@|$(FULL_LIB)|g" \
	     scripts/netlist_check.ys > $(BUILD_DIR)/netlist_check_run.ys
	@$(YOSYS) -q -l $(BUILD_DIR)/netlist_check.log -s $(BUILD_DIR)/netlist_check_run.ys >/dev/null 2>&1 || { grep -E '^CHECK|ERROR' $(BUILD_DIR)/netlist_check.log | tail -n 5; exit 1; }

.PHONY: synth-selftest
synth-selftest: $(SYNTH_LIB)
	@scripts/synth_selftest.sh

.PHONY: synth-selftest-deep
synth-selftest-deep: $(SYNTH_LIB)
	@scripts/synth_selftest.sh --deep

.PHONY: sta-selftest
sta-selftest:
	@scripts/sdc_selftest.sh

# --------------- Static timing (OpenSTA) ---------------
SDC := constraints/alu_fifo.sdc

.PHONY: sta
sta: $(NETLIST) $(SDC) scripts/sta.tcl
	@echo "[STA ] Running OpenSTA..."
	@mkdir -p $(REPORT_DIR)
	@rm -f $(REPORT_DIR)/timing.txt $(REPORT_DIR)/power_report.txt $(REPORT_DIR)/sdc_readback.sdc
	@SDC_FILE=$(SDC) $(OPENSTA) -no_splash -exit scripts/sta.tcl > $(REPORT_DIR)/sta.log 2>&1; \
	    if grep -qiE '^Error|Error:' $(REPORT_DIR)/sta.log; then grep -iE 'Error' $(REPORT_DIR)/sta.log | head -n 5; exit 1; fi
	@$(PYTHON) -I scripts/check_sdc.py $(REPORT_DIR)/sdc_readback.sdc $(CLK_PERIOD_NS) --netlist $(NETLIST)
	@echo "[STA ] Reports: $(REPORT_DIR)/timing.txt $(REPORT_DIR)/power_report.txt"

# --------------- Place and route (OpenROAD) ---------------
# PNR_STOP_AFTER=floorplan|place|cts|repair stops the flow early (environment variable, not a make variable).

.PHONY: pnr
pnr: $(NETLIST) $(SDC) scripts/pnr_flow.tcl config/floorplan.tcl config/platform.tcl
	@echo "[PNR ] Running OpenROAD flow (CLK_PERIOD_NS=$(CLK_PERIOD_NS), CORE_UTILIZATION=$(CORE_UTILIZATION))..."
	@rm -rf $(RESULTS_DIR)  # never let a run that stops early leave the previous run's reports looking current
	@mkdir -p $(RESULTS_DIR)
	@$(OPENROAD) -exit scripts/pnr_flow.tcl > $(RESULTS_DIR)/pnr.log 2>&1 || { tail -n 25 $(RESULTS_DIR)/pnr.log; exit 1; }
	@echo "[PNR ] Results directory: $(RESULTS_DIR)"

.PHONY: pnr-gui
pnr-gui: $(NETLIST)
	@echo "[OPENROAD][GUI] Running PnR in GUI..."
	@$(OPENROAD) -gui scripts/pnr_flow.tcl

.PHONY: pnr-check
pnr-check:
	@scripts/pnr_check.sh $(or $(PNR_CHECK_MODE),full)

.PHONY: pnr-selftest
pnr-selftest:
	@scripts/pnr_check_selftest.sh

.PHONY: summary
summary:
	@scripts/summary.sh

.PHONY: summary-selftest
summary-selftest:
	@scripts/summary_selftest.sh

.PHONY: all
all: synth sta pnr

.PHONY: view
view:
	@echo "[OPENROAD][GUI] Viewing final routed design..."
	@$(OPENROAD) -gui scripts/view_design.tcl

# --------------- Cleaning ---------------

.PHONY: clean
clean:
	@echo "[CLEAN] Removing $(BUILD_DIR)/"
	@rm -rf $(BUILD_DIR)

.PHONY: distclean
distclean: clean
	@echo "[CLEAN] Removing $(RESULTS_DIR)/"
	@rm -rf $(RESULTS_DIR)
