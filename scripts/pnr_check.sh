#!/usr/bin/env bash
# pnr_check.sh partial|full - read the OpenROAD run back and fail on anything that would make "it ran" a lie.
#   partial  (floorplan through timing repair, e.g. PNR_STOP_AFTER=repair): no [ERROR lines, the flow reached the
#            end of the repair stage, the three databases exist, clock-tree sinks == flip-flops in stat.txt,
#            slack lines present
#   full     (the whole flow): all of the above plus the flow's completion line, every routed/extracted report,
#            and agreement between the route DRC report and the DRC count
# Both: the clock period the OpenROAD run used (run_conditions.txt) must equal the one the post-synthesis STA report
# was made with, so reports from different runs cannot be mixed. Paths can be overridden for scripts/pnr_check_selftest.sh.
set -u
cd "$(dirname "$0")/.."
mode=${1:-partial}
R=${PNR_RESULTS_DIR:-pnr_results}
STAT=${PNR_STAT_FILE:-build/reports/stat.txt}
STA_TIMING=${PNR_STA_TIMING:-build/reports/timing.txt}
STAMP=${PNR_PERIOD_STAMP:-build/period.stamp}
LOG=$R/pnr.log
fail=0
bad() { echo "FAIL $*"; fail=1; }
good() { echo "ok   $*"; }
same() { awk -v a="$1" -v b="$2" 'BEGIN { d = a - b; exit !(d < 1e-6 && d > -1e-6) }'; }

[ -s "$LOG" ] || { bad "$LOG missing or empty (run: make pnr)"; exit 1; }
if grep -q '\[ERROR' "$LOG"; then bad "$LOG has [ERROR lines:"; grep '\[ERROR' "$LOG" | head -n 5; else good "no [ERROR lines in $LOG"; fi

if grep -q '^=== stage complete: repair' "$LOG"; then good "the flow reached the end of the repair stage"; else bad "the log never reached 'stage complete: repair' (the run stopped early or failed)"; fi

# the clock period of this run, against the post-synthesis STA report and the period stamp
pnr_period=$(sed -n 's/^clock_period_ns=//p' "$R/run_conditions.txt" 2>/dev/null)
sta_period=$(sed -n 's/^# clock period (from the loaded design): \([0-9.]*\) ns.*/\1/p' "$STA_TIMING" 2>/dev/null)
stamp_period=$(cat "$STAMP" 2>/dev/null)
if [ -z "$pnr_period" ]; then
  bad "$R/run_conditions.txt has no clock_period_ns (not written by this flow, or a different run)"
elif [ -n "$sta_period" ] && ! same "$pnr_period" "$sta_period"; then
  bad "OpenROAD ran at ${pnr_period} ns but the post-synthesis STA report is for ${sta_period} ns: reports from different clock periods (different runs)"
elif [ -n "$stamp_period" ] && ! same "$pnr_period" "$stamp_period"; then
  bad "OpenROAD ran at ${pnr_period} ns but the netlist was built for ${stamp_period} ns (build/period.stamp)"
else
  good "clock period ${pnr_period} ns agrees with the post-synthesis STA report${stamp_period:+ and the netlist build}"
fi

for db in alu_fifo_sky130hd_global_place-tcl.db alu_fifo_sky130hd_cts-tcl.db alu_fifo_sky130hd_repair-tcl.db; do
  if [ -s "$R/$db" ]; then good "$db written"; else bad "$R/$db missing"; fi
done

flops=$(awk '/sky130_fd_sc_hd__.*df/ {s += $2} END {print s+0}' "$STAT")
sinks=$(grep -oE 'has [0-9]+ sinks' "$LOG" | head -n 1 | grep -oE '[0-9]+')
if [ -n "$sinks" ] && [ "$sinks" = "$flops" ]; then
  good "clock tree has $sinks sinks = $flops flip-flops in stat.txt"
else
  bad "clock sinks '${sinks:-none}' != flip-flops '$flops' (stat.txt)"
fi

for pat in 'worst slack max' 'worst slack min' 'tns max'; do
  if grep -q "$pat" "$LOG"; then good "log has '$pat'"; else bad "log has no '$pat' line"; fi
done
for f in check_types_postcts.rpt check_types_postrepair.rpt; do
  if [ -f "$R/$f" ]; then good "$f written"; else bad "$R/$f missing"; fi
done
[ "$mode" = full ] || exit "$fail"

# ---- full: routed, extracted, reported ----
if grep -q '^PnR flow complete' "$LOG"; then good "the flow printed its completion line"; else bad "no 'PnR flow complete' line: the run did not finish (stopped early, or failed after the repair stage)"; fi
for f in alu_fifo_sky130hd_route-tcl.def alu_fifo_sky130hd_route-tcl.db alu_fifo_sky130hd_fill-tcl.db \
         alu_fifo_sky130hd_final-tcl.def alu_fifo_sky130hd-tcl.spef \
         timing_final.rpt clock_skew.rpt power_final.rpt area_final.rpt antenna.rpt drc_count.txt; do
  if [ -s "$R/$f" ]; then good "$f written"; else bad "$R/$f missing or empty"; fi
done
# report_check_types -violators writes an empty file when there are none; violations are reported by make summary, not gated here
if [ -f "$R/check_types_final.rpt" ]; then
  good "check_types_final.rpt written ($(grep -c VIOLATED "$R/check_types_final.rpt") violating pins/nets; see make summary)"
else
  bad "$R/check_types_final.rpt missing"
fi
if grep -qE '^drc_violations=[0-9]+$' "$R/drc_count.txt" 2>/dev/null; then
  good "$(cat "$R/drc_count.txt") (route DRC; a non-zero count is reported, not hidden)"
else
  bad "drc_count.txt is not 'drc_violations=<n>'"
fi
# The route DRC report must agree with the count: empty for 0 violations, non-empty otherwise.
drc_rpt="$R/alu_fifo_sky130hd_route_drc-tcl.rpt"
n=$(sed -n 's/^drc_violations=//p' "$R/drc_count.txt" 2>/dev/null)
if [ ! -e "$drc_rpt" ]; then
  bad "$drc_rpt missing"
elif [ "${n:-x}" = 0 ] && [ ! -s "$drc_rpt" ]; then
  good "route DRC report is empty, consistent with drc_violations=0"
elif [ "${n:-0}" != 0 ] && [ -s "$drc_rpt" ]; then
  good "route DRC report lists violations, consistent with drc_violations=$n"
else
  bad "route DRC report ($(wc -c < "$drc_rpt") bytes) disagrees with drc_violations=${n:-?}"
fi
if grep -qE '^antenna_violations=[0-9]+$' "$R/antenna.rpt" 2>/dev/null; then
  good "$(grep -E '^antenna_violations=' "$R/antenna.rpt")"
else
  bad "antenna.rpt has no 'antenna_violations=<n>' line"
fi
for pat in 'slack' 'worst slack max' 'worst slack min' 'tns max'; do
  if grep -q "$pat" "$R/timing_final.rpt" 2>/dev/null; then good "timing_final.rpt has '$pat'"; else bad "timing_final.rpt has no '$pat'"; fi
done
if grep -q 'Design has unrouted nets' "$LOG"; then bad "design has unrouted nets"; else good "no unrouted nets"; fi
exit "$fail"
