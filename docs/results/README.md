# Report snapshots

Each directory is a copy (made by `scripts/snapshot.sh <label>`) of the reports of one run, with `run.txt` recording the
conditions and tool versions. They are kept outside `build/` and `pnr_results/` so `make clean` does not delete them.

| Directory | What it is |
|-----------|-----------|
| `final/` | The accepted run of the current flow (`CLK_PERIOD_NS=10.0`, `CORE_UTILIZATION=40`, `repair_setup_margin` 0.3 ns, `slew_margin`/`cap_margin` 20). The README quotes this one. |
| `period_10.0ns_margin0.3_slew0/` | The accepted run before the final review: setup margin 0.3 ns but no slew/capacitance margin. Its routed `check_types_final.rpt` lists the slew and capacitance violations the review found. Kept as the "before". |
| `period_10.0ns_default/` | The same flow before the setup margin was added (margin 0): routed setup was **not** met. Kept as the "before". |
| `period_10.5ns/`, `period_11.0ns/` | Margin 0 at a slightly longer clock: routed setup was still not met, and worse than at 10.0 ns. |
| `period_12.0ns_margin0/` | Margin 0 at 12.0 ns: routed setup **is** met. Reproduced after the final review found the earlier claim ("a longer clock does not help") wrong. See its `NOTE.txt`. |
| `margin_sweep_10.0ns/` | Routed `timing_final.rpt` and DRC count for repair margins 0.15, 0.3 and 0.5 ns at the 10.0 ns period. |

Why the margin and not a longer clock: see `docs/rulings.md` (Task 12, including the correction) and the comment above `repair_setup_margin` in `scripts/pnr_flow.tcl`.
