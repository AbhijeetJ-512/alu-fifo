#!/usr/bin/env bash
# pnr_check_selftest.sh - pnr_check.sh must pass a complete synthetic run and stop each bad one with its own message.
# The directories are synthetic: they test the checker, not the design. Each variant breaks exactly one thing.
set -u
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

make_good() { # <dir>
  local d=$1
  rm -rf "$d"; mkdir -p "$d/res"
  printf 'Clock net "clk" has 454 sinks.\nworst slack max 0.1\nworst slack min 0.2\ntns max 0.000\n=== stage complete: repair\nPnR flow complete. Results in pnr_results/\n' > "$d/res/pnr.log"
  for f in alu_fifo_sky130hd_global_place-tcl.db alu_fifo_sky130hd_cts-tcl.db alu_fifo_sky130hd_repair-tcl.db \
           alu_fifo_sky130hd_route-tcl.def alu_fifo_sky130hd_route-tcl.db alu_fifo_sky130hd_fill-tcl.db \
           alu_fifo_sky130hd_final-tcl.def alu_fifo_sky130hd-tcl.spef clock_skew.rpt power_final.rpt area_final.rpt \
           ; do echo x > "$d/res/$f"; done
  : > "$d/res/check_types_final.rpt"   # a clean run: no violations, so report_check_types writes an empty file
  : > "$d/res/check_types_postcts.rpt"; : > "$d/res/check_types_postrepair.rpt"; : > "$d/res/alu_fifo_sky130hd_route_drc-tcl.rpt"
  printf 'slack (MET)\nworst slack max 0.1\nworst slack min 0.2\ntns max 0.000\n' > "$d/res/timing_final.rpt"
  echo 'drc_violations=0' > "$d/res/drc_count.txt"
  echo 'antenna_violations=0' > "$d/res/antenna.rpt"
  echo 'clock_period_ns=10.000000' > "$d/res/run_conditions.txt"
  echo '     sky130_fd_sc_hd__dfxtp_1      454' > "$d/stat.txt"
  echo '# clock period (from the loaded design): 10.000000 ns' > "$d/timing.txt"
  echo 10.0 > "$d/stamp"
}
check() { # <name> <mode> <exit want 0|1> <text that must appear (or ->>
  local name=$1 mode=$2 want=$3 text=$4 out rc
  out=$(PNR_RESULTS_DIR="$tmp/res" PNR_STAT_FILE="$tmp/stat.txt" PNR_STA_TIMING="$tmp/timing.txt" PNR_PERIOD_STAMP="$tmp/stamp" \
        scripts/pnr_check.sh "$mode" 2>&1)
  rc=$?
  local got=0; [ "$rc" -ne 0 ] && got=1
  if [ "$got" = "$want" ] && { [ "$text" = - ] || printf '%s' "$out" | grep -q -- "$text"; }; then
    echo "ok   $name -> exit $rc${text:+ ($text)}"
  else
    echo "FAIL $name: want exit-$want with '$text', got exit $rc:"; printf '%s\n' "$out" | grep -E '^FAIL' | head -n 3; fail=1
  fi
}

make_good "$tmp";                                                                       check "complete run, full"                full    0 -
make_good "$tmp"; check "complete run, partial"                                         partial 0 -
make_good "$tmp"; sed -i '/PnR flow complete/d' "$tmp/res/pnr.log";                     check "run that stopped early, full"      full    1 "did not finish"
make_good "$tmp"; sed -i '/PnR flow complete/d' "$tmp/res/pnr.log";                     check "stopped-early run is fine as partial" partial 0 -
make_good "$tmp"; sed -i '/stage complete: repair/d; /PnR flow complete/d' "$tmp/res/pnr.log"; check "run that never reached repair" partial 1 "never reached"
make_good "$tmp"; echo '[ERROR PDN-9999] boom' >> "$tmp/res/pnr.log";                  check "[ERROR line in the log"             full    1 "\[ERROR"
make_good "$tmp"; echo 'clock_period_ns=7.500000' > "$tmp/res/run_conditions.txt";      check "OpenROAD period differs from STA's"  full    1 "different clock periods"
make_good "$tmp"; echo 7.5 > "$tmp/stamp";                                              check "netlist built for another period"   full    1 "netlist was built for"
make_good "$tmp"; rm "$tmp/res/run_conditions.txt";                                     check "no run_conditions.txt (stale or foreign results)" full 1 "run_conditions.txt"
make_good "$tmp"; echo '     sky130_fd_sc_hd__dfxtp_1      453' > "$tmp/stat.txt";      check "CTS sinks != flip-flops"            full    1 "clock sinks"
make_good "$tmp"; printf 'max slew\n_1_/Y 1 2 -1 (VIOLATED)\n' > "$tmp/res/check_types_final.rpt"; check "slew violations are reported by summary, not a check failure" full 0 -
make_good "$tmp"; rm "$tmp/res/check_types_final.rpt";                                  check "missing check_types_final.rpt"      full    1 "check_types_final.rpt missing"
make_good "$tmp"; rm "$tmp/res/timing_final.rpt";                                       check "missing timing_final.rpt"           full    1 "timing_final.rpt missing"
make_good "$tmp"; echo 'violation' > "$tmp/res/alu_fifo_sky130hd_route_drc-tcl.rpt";    check "DRC report disagrees with the count" full   1 "disagrees"
make_good "$tmp"; echo 'drc_violations=lots' > "$tmp/res/drc_count.txt";                check "malformed DRC count"                full    1 "drc_count.txt is not"
make_good "$tmp"; rm -rf "$tmp/res"; mkdir "$tmp/res";                                  check "empty results directory"            full    1 "missing or empty"
exit "$fail"
