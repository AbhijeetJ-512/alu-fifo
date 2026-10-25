#!/usr/bin/env bash
# summary_selftest.sh - summary.sh must print the figure in a report, and NOT YET MEASURED (for that line only)
# when the report is missing. The reports here are synthetic: they test the parsing, not the design.
set -u
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/rep" "$tmp/res"
fail=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

cat > "$tmp/rep/stat.txt" <<'X'
   Number of cells:               1111
   Chip area for module '\alu_fifo_top': 2222.5
X
printf '# clock period (from the loaded design): 7.5 ns\nworst slack max -1.111\nworst slack min 2.222\ntns max -3.333\n' > "$tmp/rep/timing.txt"
printf 'worst slack max 0.444\nworst slack min 0.555\ntns max 0.000\n' > "$tmp/res/timing_final.rpt"
printf 'Clock clk\n   skew 0.123\n' > "$tmp/res/clock_skew.rpt"
printf 'Design area 4444 u^2 12%% utilization\n' > "$tmp/res/area_final.rpt"
printf 'Total                  1.0e-03   2.0e-03   3.0e-09   9.99e-03 100.0%%\n' > "$tmp/res/power_final.rpt"
cat > "$tmp/res/check_types_final.rpt" <<'X'
max slew

Pin                                     Limit     Slew    Slack
---------------------------------------------------------------
_1_/Y                                    1.489    1.622   -0.134 (VIOLATED)
_2_/A1                                   1.500    1.622   -0.122 (VIOLATED)
_3_/B1                                   1.500    1.622   -0.122 (VIOLATED)
_4_/A                                    1.500    1.400    0.100 (MET)

max capacitance

Pin                                     Limit      Cap    Slack
---------------------------------------------------------------
_5_/Y                                    0.010    0.020   -0.010 (VIOLATED)
X
printf 'clock_period_ns=7.500000\nrepair_setup_margin=0.3\n' > "$tmp/res/run_conditions.txt"
printf 'max slew\n\nPin Limit Slew Slack\n_9_/Y 1.5 1.6 -0.1 (VIOLATED)\n' > "$tmp/res/check_types_postrepair.rpt"
echo 'drc_violations=7' > "$tmp/res/drc_count.txt"
echo 'antenna_violations=2' > "$tmp/res/antenna.rpt"

run() { REPORT_DIR="$tmp/rep" RESULTS_DIR="$tmp/res" scripts/summary.sh; }
out=$(run)
for want in 'Number of cells:  *1111' 'Chip area.* 2222.5' 'period.*7.5 ns' 'worst slack max -1.111' 'worst slack max 0.444' \
            'tns max -3.333' 'max slew 3, max capacitance 1, max fanout 0' 'max slew 1, max capacitance 0, max fanout 0' 'clock_period_ns=7.500000' 'repair_setup_margin=0.3' 'skew 0.123' 'Design area 4444' 'Total .*9.99e-03' 'drc_violations=7' 'antenna_violations=2'; do
  if printf '%s' "$out" | grep -qE -- "$want"; then ok "prints '$want'"; else bad "missing '$want'"; fi
done
if printf '%s' "$out" | grep -q 'NOT YET MEASURED'; then bad "NOT YET MEASURED printed although every report exists"; else ok "no NOT YET MEASURED when every report exists"; fi

: > "$tmp/res/check_types_final.rpt"   # a clean run: report_check_types -violators writes an EMPTY file
out=$(run)
if printf '%s\n' "$out" | grep 'slew/cap/fanout, routed' | grep -q 'max slew 0, max capacitance 0, max fanout 0'; then
  ok "an empty violations report means zero violations, not NOT YET MEASURED"
else
  bad "an empty check_types_final.rpt must print zero violations: $(printf '%s\n' "$out" | grep 'slew/cap/fanout, routed')"
fi
rm "$tmp/res/check_types_final.rpt"
out=$(run)
if printf '%s\n' "$out" | grep 'slew/cap/fanout, routed' | grep -q 'NOT YET MEASURED'; then
  ok "a missing violations report is NOT YET MEASURED"
else
  bad "a missing check_types_final.rpt must print NOT YET MEASURED"
fi
printf 'max slew\n_1_/Y 1 2 -1 (VIOLATED)\n' > "$tmp/res/check_types_final.rpt"
rm "$tmp/res/power_final.rpt"
out=$(run)
n=$(printf '%s\n' "$out" | grep -c 'NOT YET MEASURED')
if [ "$n" -eq 1 ] && printf '%s' "$out" | grep -E 'total power' | grep -q 'NOT YET MEASURED (run: make pnr)'; then
  ok "a missing power report gives NOT YET MEASURED on the power line only"
else
  bad "expected exactly one NOT YET MEASURED (power), got $n"
fi
rm -rf "$tmp/rep"
out=$(run)
n=$(printf '%s\n' "$out" | grep -c 'NOT YET MEASURED')
if [ "$n" -ge 7 ]; then ok "with no build reports every build-report line says NOT YET MEASURED ($n lines)"; else bad "only $n NOT YET MEASURED lines with build/reports gone"; fi
exit "$fail"
