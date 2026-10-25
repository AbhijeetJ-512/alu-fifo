#!/usr/bin/env bash
# sdc_selftest.sh - check_sdc.py must accept a correct OpenSTA readback and name each constant it is
# bound to when that constant is wrong. The fixtures are small hand-made readbacks in OpenSTA's write_sdc format.
set -u
cd "$(dirname "$0")/.."
FX=verif/fixtures/sdc
fail=0
# expect <fixture> <period> <exit code> <text that must appear in the output (or ->
expect() {
  local out rc
  out=$(python3 -I scripts/check_sdc.py "$FX/$1" "$2" --netlist $FX/tiny.v 2>&1)
  rc=$?
  if [ "$rc" -eq "$3" ] && { [ "$4" = - ] || printf '%s' "$out" | grep -q -- "$4"; }; then
    echo "ok $1 (period $2) -> exit $rc${4:+ ($4)}"
  else
    echo "FAIL $1: want exit $3 with '$4', got exit $rc:"; printf '%s\n' "$out" | tail -n 4; fail=1
  fi
}
expect good_readback.sdc         10.0 0 -
expect good_readback.sdc         8.0  1 "clock period"      # the Makefile asked for 8 ns; the SDC says 10
expect bad_period.sdc            10.0 1 "clock period"
expect bad_delay.sdc             10.0 1 "set_input_delay.*a\[0\]"
expect missing_input_delay.sdc   10.0 1 "set_input_delay.*a\[1\]"
expect missing_output_delay.sdc  10.0 1 "set_output_delay.*y"
expect bad_load.sdc              10.0 1 "set_load.*y"
expect bad_driver.sdc            10.0 1 "set_driving_cell"
expect clock_delay.sdc           10.0 1 "clk"
expect no_such_file.sdc          10.0 2 "cannot read"
exit "$fail"
