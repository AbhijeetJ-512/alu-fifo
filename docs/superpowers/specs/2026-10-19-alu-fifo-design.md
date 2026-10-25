# ALU-FIFO — Design Spec

**Status:** draft for review, 2026-10-19. Nothing in this spec has been built or measured yet.
**Project directory:** `/home/abhi/Documents/VLSI/Projects/ALU-FIFO/`

## 1. Goal

A small clocked ALU with an input FIFO and an output FIFO, written in SystemVerilog (`.sv`),
taken through this flow:

1. RTL simulation in Verilator, with concurrent assertions and coverage.
2. Yosys synthesis to the Sky130 HD standard-cell library.
3. OpenSTA, then OpenROAD place-and-route on Sky130 HD, driven by a Makefile that follows the
   `Full-Adder` project's procedure (`synth`, `sta`, `pnr`, `sim`, `summary`, `view`, `all`, `clean`).

The deliverable is a repository where `make check` runs every verification gate and `make all`
runs the implementation flow, and where every figure in the README comes from a checked-in report.

## 2. Decisions

| ID | Decision | Source |
|----|----------|--------|
| D-001 | New project at `Projects/ALU-FIFO`. The sky130hd platform files and flow scripts are copied from `Full-Adder`, which stays untouched. | user, 2026-10-19 |
| D-002 | One clock, synchronous FIFOs, synchronous active-low reset (`rst_n`). No clock-domain crossing. | user, 2026-10-19 |
| D-003 | The ALU is purely combinational glue between the two FIFOs (approach A). A registered ALU stage (approach B) is a possible later change that would not alter `alu` or `sync_fifo`. | user, 2026-10-19 |
| D-004 | Input FIFO entry = `{op[2:0], a[W-1:0], b[W-1:0]}`. Output FIFO entry = `{flags[3:0], y[W-1:0]}`. Defaults: `W=16`, `DEPTH=8`. | user, 2026-10-19 |
| D-005 | Eight ops (ADD, SUB, AND, OR, XOR, SLL, SRL, SLTU) and four flags (N, Z, C, V). Definitions in §4.3. | user, 2026-10-19 |
| D-006 | Verilator 5.020 is the simulator. It has no `covergroup` and no `##` sequence delays, so functional coverage is named `cover property` bins plus Verilator line and toggle coverage. | measured by probe, 2026-10-19 |
| D-007 | One C++ file is allowed: `verif/sim_main.cpp` (~20 lines), whose only job is to run the timing loop and write `coverage.dat`. Verilator's generated main never writes it. All design, testbench and checker code is `.sv`. | user, 2026-10-19 |
| D-008 | Assertions live in checker modules attached with `bind`. The synthesis scripts never read them. | user, 2026-10-19 |
| D-009 | `make check` = lint + simulation + coverage-hole gate + mutation run. | this spec |
| D-010 | The implementation flow follows the Full-Adder Makefile and scripts, extended with what a clocked design needs: SDC, clock-tree synthesis, timing repair, post-route RC extraction. | user, 2026-10-19 |
| D-011 | Clock period is one Makefile variable, `CLK_PERIOD_NS`, default `10.0`. This is a placeholder target, not a result. Input and output delays are 20% of the period; driving cell `buf_2`, output load 10 fF (§6.3). | this spec |
| D-012 | No figure (timing, area, power, coverage, DRC count) is stated unless a tool produced it and the report is checked in. Otherwise it is labelled NOT YET MEASURED with the command that would produce it. | standing rule |

## 3. Scope

**In scope:** RTL, Verilator testbench, bound assertions, cover bins, mutation testing of the
checks, Yosys synthesis, OpenSTA, OpenROAD flow through detailed routing and RC extraction, README.

**Out of scope:**
- Formal proofs (`sby` is not installed).
- `covergroup` functional coverage (Verilator 5.020 rejects it).
- Gate-level simulation of the synthesised netlist.
- Asynchronous FIFOs and clock-domain crossing.
- SRAM macros. FIFO storage is flip-flops.
- Signoff DRC/LVS and GDS. klayout, magic and netgen are not on `PATH`; the layout check stops at
  OpenROAD's route DRC report, as in `Full-Adder`.

## 4. Architecture

### 4.1 Block diagram

```
in_valid/in_ready   ┌────────────┐   ┌──────────┐   ┌─────────────┐   out_valid/out_ready
{in_op,in_a,in_b} ─►│ input FIFO │──►│ ALU      │──►│ output FIFO │─► {out_flags,out_y}
                    │ DEPTH×(3+2W)│  │ (comb)   │   │ DEPTH×(4+W) │
                    └────────────┘   └──────────┘   └─────────────┘
                          ▲ pop = push = xfer = !in_empty && !out_full ▲
```

### 4.2 Files and interfaces

| File | Role |
|------|------|
| `rtl/alu_pkg.sv` | Opcode `localparam`s, `OP_W`. Used by fully-qualified name (`alu_pkg::OP_ADD`); the package file is always read first. |
| `rtl/alu.sv` | Combinational. `op, a, b` → `y`, `c`, `v`. `alu` returns only `y`, `c`, `v`; `z` and `n` are derived from `y` in the top, so the same flag logic covers all ops. |
| `rtl/sync_fifo.sv` | Parameters `WIDTH`, `DEPTH` (power of two, ≥ 2). Ports: `clk, rst_n, push, din, pop, dout, full, empty`. |
| `rtl/alu_fifo_top.sv` | Parameters `W=16`, `DEPTH=8`. Instantiates both FIFOs and the ALU; contains the transfer rule. |

`alu_fifo_top` ports:

| Port | Dir | Meaning |
|------|-----|---------|
| `clk`, `rst_n` | in | Clock; synchronous active-low reset |
| `in_valid`, `in_ready` | in, out | Source handshake. Transfer when both are 1. |
| `in_op[2:0]`, `in_a[W-1:0]`, `in_b[W-1:0]` | in | Command. Must be held, with `in_valid` high, while `in_ready` is low. |
| `out_valid`, `out_ready` | out, in | Sink handshake. Transfer when both are 1. |
| `out_y[W-1:0]` | out | Result |
| `out_flags[3:0]` | out | `{N, Z, C, V}` = bits `[3], [2], [1], [0]` |

RTL style rules (enforced by lint and by a `make rules` grep, as in `mlc_cache_controller`):
only `always_comb` and `always_ff @(posedge clk)`; no `initial` blocks, latches, or tri-states;
no SVA or `$display` in `rtl/` (those live in `verif/`).

### 4.3 Behaviour

**Opcodes.** `0` ADD, `1` SUB, `2` AND, `3` OR, `4` XOR, `5` SLL, `6` SRL, `7` SLTU. All eight
values of the 3-bit field are defined, so `alu.sv` has no `default` branch to leave uncovered.

| Op | `y` | `C` | `V` |
|----|-----|-----|-----|
| ADD | `a + b` (low W bits) | carry-out of `a + b` | signed overflow of `a + b` |
| SUB | `a − b` (low W bits) | carry-out of `a + ~b + 1` (C=1 means no borrow) | signed overflow of `a − b` |
| AND / OR / XOR | bitwise | 0 | 0 |
| SLL / SRL | `a` shifted by `b[$clog2(W)-1:0]`; SRL is logical | 0 | 0 |
| SLTU | `{W-1{1'b0}, a < b}` (unsigned) | 0 | 0 |

For every op: `Z = (y == 0)` and `N = y[W-1]`.

**FIFO.**
- Pointers are `$clog2(DEPTH)+1` bits wide; the extra bit distinguishes full from empty.
- `empty` = pointers equal. `full` = low bits equal and the wrap bits differ.
- Read is first-word-fall-through: `dout = mem[rd_ptr]`; the entry is valid when `!empty`.
- A push while full, or a pop while empty, is ignored (no state change).
- Reset clears the pointers only. The memory array is not reset.

**Transfer rule.** `xfer = !in_empty && !out_full`. When `xfer` is 1 in a cycle, the same cycle pops
the input FIFO and pushes `{flags, y}` of the ALU applied to the popped command into the output
FIFO. `in_ready = !in_full`. `out_valid = !out_empty`.

**Latency.** A command accepted at the edge ending cycle *t* is at the input FIFO head in cycle
*t+1*. If the output FIFO is not full, the transfer happens in *t+1* and `out_valid` is high in
*t+2*. This 2-cycle minimum is asserted (§5.2).

## 5. Verification

### 5.1 Testbench (`verif/tb_alu_fifo.sv`)

Built with `verilator --cc --exe --build --timing --assert --coverage` and `verif/sim_main.cpp`.

- **Reference model.** A function in the testbench computes `{n,z,c,v,y}` independently of `alu.sv`:
  wider arithmetic for carry (`{1'b0,a} + {1'b0,b}`), `$signed` comparisons for overflow, written in a
  different structure from the RTL so the two do not agree by construction.
- **Scoreboard.** A queue of expected output words. Every output transfer is compared; at the end
  the queue must be empty and the command count must equal the result count.
- **Stimulus phases:**
  1. Reset behaviour: both FIFOs empty, `out_valid` low.
  2. Directed: every op against corner operands (0, 1, all-ones, max signed, min signed, equal
     operands, shift amounts 0, 1, `W-1`, and values with bits above the shift field set).
  3. Fill and drain: output sink stalled until both FIFOs are full; `in_ready` must be low; then drain.
  4. Wrap: at least `3×DEPTH` transfers through each FIFO so both pointers wrap.
  5. Random: seeded (`+seed=N`, printed every run), sweeping source and sink ready probabilities
     over {0.1, 0.5, 0.9} each.
  6. Reset in the middle of traffic: pending commands are dropped, the scoreboard is flushed,
     both FIFOs are empty afterwards.
- **No X-poisoning in a two-state simulator.** Verilator has no X. To keep idle data from being
  accidentally correct: memory arrays start random (`--x-initial unique` with
  `+verilator+rand+reset+2`), and the testbench drives random garbage on `in_op/in_a/in_b` whenever
  `in_valid` is 0, and samples outputs only on a valid-and-ready cycle.
- **Verdict.** The run prints `TB PASS seed=N cmds=N` or `TB FAIL ...` and exits non-zero on any
  failure. A pass requires both the line and exit status 0.

### 5.2 Assertions (`verif/sync_fifo_checker.sv`, `verif/alu_fifo_checker.sv`, `verif/checker_binds.sv`)

All are concurrent `assert property (@(posedge clk) disable iff (!rst_n) ...)` using only `|->`,
`|=>`, `$past`, `$stable`, `$rose` (the subset Verilator 5.020 accepts), except where noted.
Each has a stable label; the mutation runner keys on these labels.

FIFO checker (bound into every `sync_fifo`). It is black-box: it never reads the RTL's pointers. It
keeps its own occupancy count `cnt` from the FIFO's ports, `cnt' = cnt + (push && cnt<DEPTH) −
(pop && cnt>0)`, cleared by reset, so a bug in the RTL's pointer logic cannot also change the
checker's reference.

| Label | Property |
|-------|----------|
| `a_not_full_and_empty` | `!(full && empty)` |
| `a_full_def` | `full` ⇔ `cnt == DEPTH` |
| `a_empty_def` | `empty` ⇔ `cnt == 0` |
| `a_head_stable` | `!empty && !pop` ⇒ next `dout` equals current `dout` |
| `a_reset_empty` | (no `disable iff`) `!rst_n` ⇒ next cycle `empty && !full` |

Top checker (bound into `alu_fifo_top`):

| Label | Property |
|-------|----------|
| `a_in_hold` | environment rule: `in_valid && !in_ready` ⇒ next `in_valid` and `$stable({in_op,in_a,in_b})`. Catches a bad testbench. |
| `a_out_hold` | `out_valid && !out_ready` ⇒ next `out_valid` and `$stable({out_y,out_flags})` |
| `a_flag_z`, `a_flag_n` | `out_valid` ⇒ `out_flags[Z] == (out_y == 0)`, `out_flags[N] == out_y[W-1]` |
| `a_lockstep` | input pop and output push occur in the same cycle, and only when `!in_empty && !out_full` |
| `a_latency` | `out_push` ⇒ next `out_valid`; a command accepted while both FIFOs are empty ⇒ `out_valid` two cycles later (via `$past(…, 2)`) |
| `a_conservation` | accepted-in minus taken-out (counters in the checker, cleared by reset) equals the sum of two occupancy models, one per FIFO, built from the top's internal push and pop wires the same way as the FIFO checker's `cnt` |

Separation of duties: assertions check structure (FIFO, protocol, flag consistency, conservation);
the scoreboard checks the ALU's arithmetic. The spec does not claim an assertion checks a value that
only the scoreboard checks.

### 5.3 Coverage

- **Verilator `--coverage`** gives line and toggle coverage of `rtl/`. Gate: 100% line coverage of
  `rtl/*.sv`, or each uncovered line named in an exclusion list with its reason. Toggle coverage is
  reported with its unhit bits listed; it is not a gate.
- **Named `cover property` bins** (each written out as its own named statement; Verilator sums a
  `generate for` loop into a single name, which would hide an unhit bin):
  - each of the 8 ops executed;
  - result flag Z set (ADD, SUB, and a logic op), N set, C set on ADD, C=1 and C=0 on SUB, V set
    on ADD and on SUB;
  - shift amount 0 and `W-1`; SLTU true and false;
  - input FIFO full; output FIFO full; each FIFO empty; each FIFO push and pop in the same cycle;
    pointer wrap on each FIFO; source stalled (`in_valid && !in_ready`); sink stalled
    (`out_valid && !out_ready`); at least 8 consecutive transfers.
- **Gate (`make cov`).** `scripts/cov_check.py` reads `coverage.dat`, prints every bin with its hit
  count into `build/reports/coverage_bins.txt`, and exits non-zero if any named bin has zero hits.
  It also writes the `verilator_coverage --annotate` output to `build/reports/cov_annotated/`.

### 5.4 Checking the checks (`make mutants`)

A runner applies each deliberate bug to a copy of the RTL, builds, runs the full testbench, and
records which check fired first. Each mutant is bound in `verif/mutants/` to the one check that
(or checks) intended to catch it. The planned set (finalised in the implementation plan):

| Mutant | Bug | Intended check(s) |
|--------|-----|-------------------|
| M01 | FIFO `full` off by one | `a_full_def` |
| M02 | pop allowed while empty | `a_empty_def` |
| M03 | push allowed while full (overwrite) | `a_full_def` |
| M04 | pointer without a wrap bit (full never asserts) | `a_full_def` |
| M05 | reset leaves `rd_ptr` untouched | `a_reset_empty` |
| M06 | SUB carry inverted | scoreboard |
| M07 | V computed for AND/OR/XOR | scoreboard |
| M08 | SRL made arithmetic | scoreboard |
| M09 | SLTU compares signed | scoreboard |
| M10 | N flag taken from bit `W-2` | `a_flag_n` |
| M11 | transfer ignores `out_full` | `a_lockstep` |
| M12 | transfer fires while input FIFO empty | `a_lockstep` |
| M13 | output data changes while stalled | `a_out_hold` |
| M14 | result dropped when the output FIFO holds `DEPTH-1` entries (input still popped) | `a_conservation`, `a_lockstep` |

Pass criteria: every mutant is killed, and its intended check is among those that fired. A second run
neutralises the intended check (compile-time define that removes only that property) and records
whether the mutant is still caught by some other check or survives. The report
`build/reports/mutants.txt` lists both, so a check that no mutant ever exercised is visible.
When the run reports any survivor, each is read individually and classified as a real gap or an
equivalent mutant, with the reason written next to it.

### 5.5 Lint (`make lint`)

`verilator --lint-only -Wall` on `rtl/` must report zero warnings. A second lint of `rtl/` plus
`verif/` may use named, justified `-Wno-` flags, listed in the Makefile.

## 6. Implementation flow

### 6.1 Make targets

| Target | What it does | Output |
|--------|--------------|--------|
| `make lint` | Verilator lint (§5.5) | stdout |
| `make rules` | grep gate for the RTL style rules (§4.2) | stdout |
| `make sim` | Build and run the testbench with `--trace` | `build/sim/waveform.vcd` |
| `make wave` | Open the VCD in GTKWave | |
| `make cov` | Coverage run, bin gate, annotated report | `build/reports/coverage*` |
| `make mutants` | §5.4 | `build/reports/mutants.txt` |
| `make check` | lint + rules + sim + cov + mutants | non-zero exit on any failure |
| `make synth` | Yosys → `build/synth.v` | `build/reports/stat.txt` |
| `make sta` | OpenSTA on the synthesised netlist with the SDC | `build/reports/timing.txt`, `power_report.txt` |
| `make pnr` | OpenROAD flow | `pnr_results/` |
| `make all` | `synth sta pnr` (same as Full-Adder) | |
| `make summary` | Print key lines from the reports, including worst setup and hold slack | |
| `make view`, `make pnr-gui` | OpenROAD GUI on the routed design or the flow | |
| `make clean`, `make distclean` | Remove generated files | |

### 6.2 Synthesis (`scripts/synth.ys`, native Yosys script, no Tcl)

Reads `rtl/alu_pkg.sv` first, then the other `rtl/*.sv`. Then `hierarchy -check -top alu_fifo_top`,
`synth -flatten`, flip-flop legalisation and `dfflibmap -liberty`, `abc -D <period in ps> -liberty`,
`hilomap`, `opt_clean -purge`, `check -assert` (fails on latches, undriven or multiply-driven nets),
`stat -liberty` into `build/reports/stat.txt`, `write_verilog -noattr build/synth.v`.

`Full-Adder/scripts/synth.ys` ran `techmap` before `dfflibmap` and has no flip-flop handling; it was
written for combinational logic. The ALU-FIFO script keeps the same stage order (read, map, report,
write) but replaces the middle. Yosys 0.33's `synth` leaves enable flip-flops (`$_DFFE_PP_`, 280 of
them for the 35-bit × 8 input FIFO in a probe); the exact legalisation pass is confirmed during
implementation and is a named risk (R-1).

The Makefile generates the run script from `scripts/synth.ys` with the period substituted from
`CLK_PERIOD_NS`, so the period has one source.

### 6.3 Constraints (`constraints/alu_fifo.sdc`)

One clock `clk` with period `$::env(CLK_PERIOD_NS)`; `set_input_delay` and `set_output_delay` of 20%
of the period on all non-clock ports (including `rst_n`); `set_driving_cell -lib_cell
sky130_fd_sc_hd__buf_2 -pin X` on the inputs and `set_load 0.01` on the outputs (the liberty file's
units are ns and pF, so this is 10 fF). The driving cell and load are assumptions about the
surrounding system, like the 20% delays, not results. `make sta` reads the clock
period back from the loaded design (`report_clock_properties`) and fails if it differs from
`CLK_PERIOD_NS`, so the SDC is verified rather than assumed.

### 6.4 STA (`scripts/sta.tcl`)

OpenSTA with the Sky130 HD typical-corner liberty, the synthesised netlist and the SDC. Writes
`build/reports/timing.txt` (setup and hold) and `power_report.txt`.

### 6.5 Place and route (`scripts/pnr_flow.tcl`)

The Full-Adder script, with the stages a clocked design needs. Order:

1. Read LEF, liberty, netlist; `link_design`; `read_sdc`.
2. `initialize_floorplan` by core utilisation (`CORE_UTILIZATION`, default 40) and aspect ratio 1,
   replacing Full-Adder's fixed 13×13 µm die.
3. Tracks, tapcells, PDN (`pdngen`), global placement, pin placement, routability-driven global
   placement, `repair_design`, detailed placement.
4. Clock tree: `repair_clock_inverters`, `clock_tree_synthesis` with the platform's `cts_buffer` and
   cluster settings, `set_propagated_clock`, `repair_clock_nets`, detailed placement.
5. `repair_timing` (setup and hold).
6. Global route, `repair_antennas`, detailed route (DRC report), filler placement.
7. RC extraction (`extract_parasitics` with the platform's RCX rules), `write_spef`, `read_spef`.
8. Final reports into `pnr_results/`: worst setup and hold slack, TNS, `report_checks`,
   `report_clock_skew`, max slew/capacitance/fanout violators, `report_power`, `report_design_area`,
   DRC violation count (`detailed_route_num_drvs`), antenna check.

The reference sequence is taken from the OpenROAD distribution's own `test/flow.tcl`
(`/home/abhi/Documents/VLSI/OpenROAD/test/`), which is a clocked Sky130 HD flow.

**Timing honesty.** `make pnr` succeeds when the flow completes and its reports exist. Whether setup
and hold are met is read from the reports by `make summary`, not assumed. If setup fails at the
default period, the result is reported as it is; any change of `CLK_PERIOD_NS` is a recorded
decision with the before and after reports kept.

### 6.6 Platform files

Copied from `Full-Adder/sky130hd/` into `ALU-FIFO/sky130hd/`: `sky130hd.tlef`,
`sky130_fd_sc_hd_merged.lef` (and the `sky130hd_std_cell.lef` link), `sky130_fd_sc_hd__tt_025C_1v80.lib`
(and the `sky130hd_tt.lib` link), `sky130hd.pdn.tcl`, `sky130hd.tracks`, `sky130hd.rc`,
`sky130hd.rcx_rules`, `sky130hd.vars`. Not copied: the fast and slow corner libraries (the flow is
single-corner), and `work_around_yosys/`. Measured sizes of the files copied: about 15 MB, against 96 MB
for the full folder (the fast-corner library alone is 68 MB). The copied `sky130hd.vars` has its
unused `liberty_files` multi-corner list removed so it does not point at files that are absent.

## 7. Repository layout

```
ALU-FIFO/
├── Makefile
├── README.md                       written last; every figure cites a report
├── rtl/                            alu_pkg.sv  alu.sv  sync_fifo.sv  alu_fifo_top.sv
├── verif/                          tb_alu_fifo.sv  *_checker.sv  checker_binds.sv  sim_main.cpp
│   └── mutants/                    one rule per mutant + intended-check table
├── constraints/alu_fifo.sdc
├── config/                         platform.tcl  floorplan.tcl (design name, utilisation)
├── scripts/                        synth.ys  sta.tcl  pnr_flow.tcl  flow_helpers.tcl  helpers.tcl
│                                   view_design.tcl  cov_check.py  mutants.py
├── sky130hd/                       platform subset (§6.6)
├── build/                          generated: sim, synth.v, reports/
├── pnr_results/                    generated: DEF/ODB/SPEF/reports
└── docs/superpowers/specs/         this file
```

Languages: `.sv` for all RTL, testbench and checkers; `Makefile`, Tcl and Yosys scripts for the flow;
Python for two small report scripts; one ~20-line `.cpp` (D-007).

## 8. Acceptance criteria

Each is checked by running the command from a clean checkout and reading the report it writes.

1. `make lint` reports zero warnings on `rtl/`.
2. `make sim` exits 0 and prints `TB PASS` with its seed and command count; the same seed reproduces
   the same run.
3. `make cov` exits 0: every named bin has at least one hit and `rtl/` line coverage is 100% apart from
   named exclusions. Hit counts, line coverage and toggle coverage are the numbers in
   `build/reports/`; none is quoted from memory.
4. `make mutants` kills every mutant with its intended check firing, and `mutants.txt` shows the
   neutralised-check run for each.
5. `make synth` exits 0 with `check -assert` clean, and `build/synth.v` contains only Sky130 HD cells.
6. `make sta` confirms the SDC's clock period equals `CLK_PERIOD_NS` and writes timing and power reports.
7. `make pnr` completes and writes the §6.5 reports, including the DRC violation count and antenna
   result. A non-zero count or a failing slack is reported, not hidden.
8. `make all` and `make check` both run from a clean checkout. The README's figures each cite a
   checked-in report; anything not run is labelled NOT YET MEASURED with its command.

## 9. Risks

| ID | Risk | Mitigation |
|----|------|------------|
| R-1 | Yosys 0.33 `dfflibmap` may not map enable flip-flops directly. | Legalise to plain D flip-flops plus mux before `dfflibmap`; confirm by `check -assert` and the cell list in `stat.txt`. |
| R-2 | The Full-Adder PnR script was written for a combinational design; CTS and `repair_timing` are new to it, on a recent OpenROAD build. | Use the OpenROAD distribution's `flow.tcl` as the reference; debug stage by stage. |
| R-3 | Setup may not close at 10 ns, or hold may need repair. | §6.5 timing honesty rule. |
| R-4 | A two-state simulator cannot poison idle data. | Random initialisation, garbage driven when invalid, outputs sampled only on valid-and-ready (§5.1). |
| R-5 | Verilator stops at the first failed assertion by default, which hides other checks that would also fire. | The mutation runner raises Verilator's error limit (`+verilator+error+limit+N`) so more than one check can be reported; confirmed during implementation, otherwise only the first is recorded and the report says so. |
| R-6 | No klayout/magic/netgen, so no signoff DRC or LVS. | Stated in §3; the README says the layout check is OpenROAD's route DRC only. |

## 10. Notes

- This spec is not committed. `Projects/` is not a git repository, and `ALU-FIFO` has no `.git` yet.
  If you want one, say so (the existing projects use Title-Case-Hyphen repository names, and you
  have chosen private visibility before).
- After you approve this spec, the next step is an implementation plan (task-by-task, test first),
  which you also review before any RTL is written.
