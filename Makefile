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
	@echo "  make check          - lint, rules, sim, seeds, depths, cov, mutants and their self-tests"
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

# Everything that can fail, in one command: the RTL gates, the simulations, the coverage gate and the
# mutation run, plus the self-tests that prove those gates can fail. Exits non-zero on the first failure.
.PHONY: check
check: lint rules rules-selftest
	@echo "[CHECK] all gates passed"

# --------------- Cleaning ---------------

.PHONY: clean
clean:
	@echo "[CLEAN] Removing $(BUILD_DIR)/"
	@rm -rf $(BUILD_DIR)

.PHONY: distclean
distclean: clean
	@echo "[CLEAN] Removing $(RESULTS_DIR)/"
	@rm -rf $(RESULTS_DIR)
