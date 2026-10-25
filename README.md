# ALU-FIFO

A small clocked ALU between an input FIFO and an output FIFO, written in SystemVerilog. I took it through RTL simulation and
verification in Verilator, synthesis in Yosys, static timing in OpenSTA, and place and route in OpenROAD on the Sky130 HD standard
cells. The Makefile uses the target names of my [Full-Adder](../Full-Adder) project and adds what a clocked design needs.

The design spec is [`docs/superpowers/specs/2026-10-19-alu-fifo-design.md`](docs/superpowers/specs/2026-10-19-alu-fifo-design.md). The working
plan I built it from isn't kept in this folder.

I didn't type any of the measured results in this README (timing, area, power, coverage, DRC, mutation). `scripts/readme_results.py`
quotes the Results block word for word from a report snapshot in [`docs/results/`](docs/results), and `scripts/acceptance.sh` fails if
the block ever differs from that snapshot. Anything that wasn't measured says `NOT YET MEASURED`, with the command that would measure
it. The design parameters and assumptions in the text (16-bit, 8-entry, a 10 ns clock target, 20% I/O delays) are my choices rather than
results.

## The design

```
in_valid/in_ready   +------------+   +----------+   +-------------+   out_valid/out_ready
{in_op,in_a,in_b} ->| input FIFO |-->| ALU      |-->| output FIFO |-> {out_flags,out_y}
                    +------------+   | (comb)   |   +-------------+
                       pop = push = xfer = !in_empty && !out_full
```

- `rtl/alu.sv` is the combinational ALU: ADD, SUB, AND, OR, XOR, SLL, SRL and SLTU, with a 3-bit opcode.
- `rtl/sync_fifo.sv` is a single-clock, first-word-fall-through FIFO with wrap-bit pointers and a synchronous active-low reset.
- `rtl/alu_fifo_top.sv` holds the two FIFOs and the ALU, and moves one command per cycle whenever the input has a command and the output
  has room.
- The defaults are 16-bit data and 8-entry FIFOs, with flags `{N, Z, C, V}`; on SUB, C = 1 means no borrow. Section 4 of the spec has
  the details.
- There's a single clock with no clock-domain crossing, and the FIFO storage is flip-flops, not SRAM macros.

## Running it

```bash
make check      # every verification gate: lint, RTL style rules, simulation, seeds, depths, coverage, mutation run, and their self-tests
make all        # synth + sta + pnr  (Yosys, OpenSTA, OpenROAD)
make summary    # the key figures, read from the reports (NOT YET MEASURED where a report is missing)
make help       # every target
```

Parameters can be set on the command line, for example `make sim SEED=7 DEPTH=4` or `make all CLK_PERIOD_NS=10.0 CORE_UTILIZATION=40`.
`CLK_PERIOD_NS` is the only place the clock period is set: it feeds the SDC, Yosys `abc -D` and OpenROAD.

## How it's verified

- **Testbench** (`verif/tb_alu_fifo.sv`): a scoreboard against an independent reference model, which is itself checked against
  hand-derived known answers before any stimulus runs. It has directed corner cases for every op, fill and drain, pointer wrap, a seeded
  random phase with random back-pressure, and a reset in the middle of traffic. Verilator is two-state, so idle data is randomised and
  garbage is driven whenever `valid` is low.
- **Assertions** (`verif/*_checker.sv`, attached with `bind` and never read by Yosys): black-box checks of the FIFOs, which keep their own
  occupancy model, the handshake rules (ready and valid are exactly the FIFO flags, and a transfer happens whenever one is possible and
  only then), flag consistency, latency and occupancy bookkeeping. The scoreboard checks the data values; the assertions don't. Verilator
  5.020 has no `##` sequence delays, so they're written with `|->`, `|=>`, `$past` and `$stable`.
- **Coverage**: Verilator line and toggle coverage plus named `cover property` bins, since Verilator 5.020 has no `covergroup`. `make cov`
  fails on any bin with zero hits, and on any uncovered line it can see that isn't excluded with a reason. It can't see every file:
  Verilator only records line coverage for procedural blocks, so `alu_fifo_top.sv` (continuous assignments, which hold the transfer rule
  and the ready/valid logic) has no line records. The coverage report names such files, and that logic is exercised by the cover bins,
  the handshake assertions and the mutants instead.
- **Checking the checks**: `make mutants` injects deliberate bugs (`verif/mutants/`), in the RTL plus one in the testbench for the
  source-protocol rule. Each bug is bound to the check that's meant to catch it and re-run with that assertion removed. The run also
  fails if an assertion has no mutant bound to it or never fired in any run. The self-tests (`rules-selftest`, `cov-selftest`,
  `sta-selftest`, `synth-selftest`, `summary-selftest`, `pnr-selftest`) show that most of the gates can fail on a bad input; Verilator's
  own `-Wall` lint has no self-test.
- The only C++ is `verif/sim_main.cpp` (about twenty lines), because the main that Verilator 5.020 generates never writes `coverage.dat`.
  Everything else in the design and its verification is SystemVerilog.

## Implementation flow

`make synth` runs `scripts/synth.ys` in Yosys (RTL-level checks, then mapping to a copy of the Sky130 HD liberty without the low-power
`lpflow_` cells) and then `scripts/netlist_check.ys`, which reads the written netlist back in. `make sta` runs OpenSTA with
`constraints/alu_fifo.sdc` and checks the constraints OpenSTA actually loaded. `make pnr` runs `scripts/pnr_flow.tcl`: floorplan by
utilisation, power grid, placement, clock-tree synthesis, timing repair, routing, antenna repair, fillers, RC extraction, and final
reports into `pnr_results/`.

## Results

<!-- BEGIN RESULTS (generated by scripts/readme_results.py from docs/results/final/; do not edit by hand) -->

**Conditions of the run** - from `docs/results/final/run.txt`

```text
label            : final
CLK_PERIOD_NS    : 10.0
CORE_UTILIZATION : 40 (Makefile default)
verilator        : Verilator 5.020 2024-01-01 rev (Debian 5.020-1)
yosys            : Yosys 0.33 (git sha1 2584903a060)
openroad         : v2.0-25346-gc62be3f952 
rtl sha256       : 31b57e264b286735 (cat rtl/*.sv)
```

**Key figures (make summary)** - from `docs/results/final/summary.txt`

```text
=== SUMMARY (every line is read from a report file) ===
[synthesis]  build/reports/stat.txt
  cells                              Number of cells:               1625
  area (um^2, no placement)          Chip area for module '\alu_fifo_top': 19947.881600
[static timing, post-synthesis, ideal clock, no wires]  build/reports/timing.txt
  clock period (ns)                  clock period (from the loaded design): 10.000000 ns
  worst setup slack (ns)             worst slack max -2.536
  worst hold slack (ns)              worst slack min 0.427
  total negative slack (ns)          tns max -146.371
[place and route, routed + extracted (SPEF), propagated clock]  pnr_results/
  clock period used (ns)             clock_period_ns=10.000000
  repair_timing setup margin         repair_setup_margin=0.3
  worst setup slack (ns)             worst slack max 0.061
  worst hold slack (ns)              worst slack min 0.493
  total negative slack (ns)          tns max 0.000
  slew/cap/fanout, routed            max slew 0, max capacitance 0, max fanout 0 (violating pins/nets)
  slew/cap/fanout, after repair      max slew 0, max capacitance 0, max fanout 0 (violating pins/nets)
  clock skew                          -0.059 setup skew
  design area                        Design area 20825 u^2 42.4% utilization (standard cells and tapcells, before filler cells)
  total power (W, default activity)  Total                  4.14e-03   3.66e-03   8.71e-09   7.80e-03 100.0%
  route DRC violations               drc_violations=0
  antenna violations                 antenna_violations=0
===
```

**Coverage** - from `docs/results/final/coverage_summary.txt`

```text
source               : build/cov_d8/coverage.dat
named cover bins     : 34 total, 34 hit, 0 zero
rtl/ line blocks    : 10 total, 10 covered, 0 excluded, 0 uncovered
rtl/ files with no line records : alu_fifo_top.sv, alu_pkg.sv (procedural blocks only are recorded; these are covered by toggle coverage, the cover bins and the assertions, not by the line gate)
rtl/ branches       : 12 total, 12 hit (reported, not gated)
rtl/ toggle bits    : 626 total, 626 toggled, 0 unhit (reported, not gated)
```

**Mutation run** - from `docs/results/final/mutants.txt`

```text
mutants: 22, killed 22, intended check fired in 22
only guard for their bug (survive with the intended check removed): M15, M17
assertions defined in verif/*_checker.sv : 15
assertions with no mutant bound to them  : none
assertions that fired in no mutant run   : none
```

<!-- END RESULTS -->

## Reading the timing numbers

- The **post-synthesis** timing is from before layout: the clock is ideal, wires cost nothing, and high-fanout nets aren't buffered (the
  FIFO read pointers drive every bit of the read multiplexer). That makes it pessimistic, and at the 10 ns target it doesn't close.
- The number that matters is the **routed and extracted** one (the second timing block), taken after placement, clock-tree synthesis,
  `repair_timing` and detailed routing, with extracted wire parasitics and a propagated clock.
- To close it at the 10 ns target I had to give `repair_timing` a setup margin (`repair_setup_margin` in `scripts/pnr_flow.tcl`). With no
  margin the repair stops at zero slack on the placement-stage wire estimates, which are optimistic, and the routed design missed setup.
  A longer clock can also close it, but not smoothly: with no margin the routed slack was negative at 10.0, 10.5 and 11.0 ns and positive
  at 12.0 ns. The synthesised netlist is identical across those periods, so the period only changes how hard `repair_timing` works. The
  reports for every trial are in [`docs/results/`](docs/results/README.md). The margin I used is the smallest value I tried that closes,
  which isn't necessarily the best one.
- The setup and hold slack are for the typical corner only (`tt_025C_1v80`); I didn't run any other corner.
- The power figure uses OpenSTA's default switching activity, not a real workload.

## Limitations: what isn't checked

- Only `W = 16` is verified, because the known-answer vectors are 16-bit. The RTL is parameterised, but other widths are untested.
  `DEPTH` 2, 4, 8 and 16 are simulated.
- There's no formal proof, no `covergroup` and no gate-level simulation of the synthesised netlist.
- Toggle coverage leaves out the storage array of the input FIFO (the wider one, since Verilator limits the size of array it
  instruments), and the line gate can't see `alu_fifo_top.sv` (see *Coverage* above).
- The routed design isn't free of slew and capacitance violations. The counts are in the Results block, and `make summary` prints them.
  The flow has no repair step after routing.
- A command offered while `rst_n` is low can be accepted by the handshake and then dropped by the reset.
- The layout checks stop at OpenROAD's route DRC and antenna reports. Signoff DRC/LVS and GDS need klayout, magic and netgen, which
  aren't installed here, so the layout hasn't been through signoff.
- The clock period, the 20% input and output delays, the `buf_2` driving cell and the 10 fF output load are assumptions about a
  surrounding system, not results. The power figure uses OpenSTA's default switching activity, not a measured workload.
- The assertions are only as strong as the mutation report shows, and I don't claim that a bug class outside the mutant list is caught.

## Differences from the spec

Wherever the build departed from the spec or the plan, or had to fill a gap, the decision and what it would cost if it were wrong are in
[`docs/rulings.md`](docs/rulings.md), with the findings that forced them. The ones a user of the flow will notice: `sky130hd.pdn.tcl` is
the OpenROAD distribution's file instead of Full-Adder's, because Full-Adder's minimal power grid made detailed placement fail on the wide
`mux4_2` cells; the clock period stayed at its default and `repair_timing` got a setup margin instead; and the synthesis checks are split
into `synth.ys` and a netlist check that reads the written netlist back.

## Layout

```
rtl/            alu_pkg.sv alu.sv sync_fifo.sv alu_fifo_top.sv
verif/          testbench, checkers, binds, sim_main.cpp, mutants/, fixtures/ (inputs for the self-tests)
constraints/    alu_fifo.sdc
config/         platform.tcl floorplan.tcl
scripts/        flow scripts and the checks that guard them
sky130hd/       the platform files the flow reads (copied from Full-Adder, one file from the OpenROAD distribution)
docs/           spec, acceptance checklist, results/ (report snapshots)
build/ pnr_results/   generated
```

## License

MIT, see [`LICENSE`](LICENSE). The Sky130 platform files in `sky130hd/` aren't mine and keep their own licenses (BSD 3-Clause from
OpenROAD, Apache 2.0 for the SkyWater cell data); [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) has the details.
