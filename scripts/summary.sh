#!/usr/bin/env bash
# summary.sh - print the key figures from the checked reports. Every figure is read from a report file; if the
# report is missing the line says NOT YET MEASURED and which make target produces it. Nothing is computed or remembered here.
# Paths come from the environment so scripts/summary_selftest.sh can point it at synthetic reports.
set -u
cd "$(dirname "$0")/.."
REPORT_DIR=${REPORT_DIR:-build/reports}
RESULTS_DIR=${RESULTS_DIR:-pnr_results}

# row <label> <file> <make target> <awk/grep -E pattern> [sed expression to trim the line]
row() {
  local label=$1 file=$2 target=$3 pat=$4 trim=${5:-}
  local line
  if [ ! -s "$file" ]; then
    printf '  %-34s NOT YET MEASURED (run: make %s)\n' "$label" "$target"
    return
  fi
  line=$(grep -m1 -E -- "$pat" "$file" || true)
  if [ -z "$line" ]; then
    printf '  %-34s NOT FOUND in %s (pattern: %s)\n' "$label" "$file" "$pat"
    return
  fi
  [ -n "$trim" ] && line=$(printf '%s' "$line" | sed -E "$trim")
  printf '  %-34s %s\n' "$label" "$line"
}

# viol_row <label> <file> <make target>: violating pins/nets per category from a report_check_types -violators report
viol_row() {
  local label=$1 file=$2 target=$3
  # report_check_types -violators writes an EMPTY file when there are no violations, so only a missing file is unmeasured
  if [ ! -e "$file" ]; then
    printf '  %-34s NOT YET MEASURED (run: make %s)\n' "$label" "$target"
    return
  fi
  printf '  %-34s ' "$label"
  awk '/^max slew/ {sec="max slew"} /^max capacitance/ {sec="max capacitance"} /^max fanout/ {sec="max fanout"}
       /VIOLATED/ {n[sec]++}
       END {printf "max slew %d, max capacitance %d, max fanout %d (violating pins/nets)\n", n["max slew"], n["max capacitance"], n["max fanout"]}' "$file"
}

echo "=== SUMMARY (every line is read from a report file) ==="
echo "[synthesis]  $REPORT_DIR/stat.txt"
row "cells"                      $REPORT_DIR/stat.txt synth 'Number of cells'          's/^ +//'
row "area (um^2, no placement)"  $REPORT_DIR/stat.txt synth 'Chip area'                's/^ +//'
echo "[static timing, post-synthesis, ideal clock, no wires]  $REPORT_DIR/timing.txt"
row "clock period (ns)"          $REPORT_DIR/timing.txt sta '^# clock period'          's/^# //'
row "worst setup slack (ns)"     $REPORT_DIR/timing.txt sta '^worst slack max'
row "worst hold slack (ns)"      $REPORT_DIR/timing.txt sta '^worst slack min'
row "total negative slack (ns)"  $REPORT_DIR/timing.txt sta '^tns max'
echo "[place and route, routed + extracted (SPEF), propagated clock]  $RESULTS_DIR/"
row "clock period used (ns)"     $RESULTS_DIR/run_conditions.txt pnr '^clock_period_ns='
row "repair_timing setup margin"  $RESULTS_DIR/run_conditions.txt pnr '^repair_setup_margin='
row "worst setup slack (ns)"     $RESULTS_DIR/timing_final.rpt pnr '^worst slack max'
row "worst hold slack (ns)"      $RESULTS_DIR/timing_final.rpt pnr '^worst slack min'
row "total negative slack (ns)"  $RESULTS_DIR/timing_final.rpt pnr '^tns max'
viol_row "slew/cap/fanout, routed"    $RESULTS_DIR/check_types_final.rpt pnr
viol_row "slew/cap/fanout, after repair" $RESULTS_DIR/check_types_postrepair.rpt pnr
row "clock skew"                 $RESULTS_DIR/clock_skew.rpt pnr 'skew|Skew'
row "design area"                $RESULTS_DIR/area_final.rpt pnr 'Design area'
row "total power (W, default activity)" $RESULTS_DIR/power_final.rpt pnr '^Total'
row "route DRC violations"       $RESULTS_DIR/drc_count.txt pnr '^drc_violations='
row "antenna violations"         $RESULTS_DIR/antenna.rpt pnr '^antenna_violations='
echo "==="
