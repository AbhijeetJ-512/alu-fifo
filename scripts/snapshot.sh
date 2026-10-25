#!/usr/bin/env bash
# snapshot.sh <label> - copy the reports of the current run to docs/results/<label>/ so they survive
# make clean / distclean and can be cited (README) or compared (a period change keeps the before and after).
# It copies; it never edits a report. run.txt records the conditions the run was made under.
set -eu
cd "$(dirname "$0")/.."
label=${1:?usage: snapshot.sh <label>}
dest=docs/results/$label
mkdir -p "$dest"
for f in build/reports/exit_status.txt build/reports/check.log build/reports/all.log build/reports/selftests.log build/reports/pnr-check.log build/reports/coverage_summary.txt build/reports/coverage_bins.txt build/reports/mutants.txt build/reports/stat.txt build/reports/timing.txt build/reports/power_report.txt build/reports/sdc_readback.sdc \
         pnr_results/run_conditions.txt pnr_results/timing_final.rpt pnr_results/check_types_final.rpt pnr_results/clock_skew.rpt pnr_results/power_final.rpt \
         pnr_results/area_final.rpt pnr_results/antenna.rpt pnr_results/drc_count.txt \
         pnr_results/floating_nets.rpt pnr_results/check_types_postcts.rpt pnr_results/check_types_postrepair.rpt pnr_results/pnr.log; do
  [ -e "$f" ] && cp "$f" "$dest/" || echo "snapshot: $f not present, skipped"
done
make --no-print-directory summary > "$dest/summary.txt"
{
  echo "label            : $label"
  echo "CLK_PERIOD_NS    : $(cat build/period.stamp 2>/dev/null || echo unknown)"
  echo "CORE_UTILIZATION : ${CORE_UTILIZATION:-40 (Makefile default)}"
  echo "verilator        : $(verilator --version 2>&1 | head -n 1)"
  echo "yosys            : $(yosys -V 2>&1 | head -n 1)"
  echo "openroad         : $(openroad -version 2>&1 | head -n 1)"
  echo "rtl sha256       : $(cat rtl/*.sv | sha256sum | cut -c1-16) (cat rtl/*.sv)"
} > "$dest/run.txt"
echo "snapshot: $dest ($(ls "$dest" | wc -l) files, $(du -sh "$dest" | cut -f1))"
