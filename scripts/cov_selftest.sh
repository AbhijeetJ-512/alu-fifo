#!/usr/bin/env bash
# cov_selftest.sh - cov_check.py must fail on exactly the faults it claims to catch and pass otherwise.
# The fixtures are reduced copies (v_user and v_line records only) of a real Verilator coverage.dat.
set -u
cd "$(dirname "$0")/.."
FX=verif/fixtures/cov
CHK="python3 -I scripts/cov_check.py"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# expect <name> <exit code> <text that must appear in the output (or -)> -- <cov_check args...>
expect() {
  local name=$1 want_rc=$2 want_text=$3
  shift 4
  local out rc
  out=$($CHK "$@" --bins-out "$tmp/bins" --summary-out "$tmp/sum" --toggle-out "$tmp/tog" 2>&1)
  rc=$?
  if [ "$rc" -eq "$want_rc" ] && { [ "$want_text" = "-" ] || printf '%s' "$out" | grep -q -- "$want_text"; }; then
    echo "ok $name -> exit $rc${want_text:+ ($want_text)}"
  else
    echo "FAIL $name: want exit $want_rc with '$want_text', got exit $rc:"; printf '%s\n' "$out" | tail -n 5
    fail=1
  fi
}

: > "$tmp/no_exclusions.txt"
grep -v 'page.v_user' "$FX/all_hit.dat" > "$tmp/no_bins.dat"

expect all_hit              0 "alu_fifo_top.sv" -- $FX/all_hit.dat      --rtl-dir rtl --exclusions "$tmp/no_exclusions.txt"   # and it must say which rtl files the line gate cannot see
expect zero_hit_bin         1 "c_v_sub"         -- $FX/one_bin_miss.dat --rtl-dir rtl --exclusions "$tmp/no_exclusions.txt"
expect uncovered_line       1 "rtl/alu.sv:41"   -- $FX/one_line_miss.dat --rtl-dir rtl --exclusions "$tmp/no_exclusions.txt"
expect excluded_line_passes 0 -                 -- $FX/one_line_miss.dat --rtl-dir rtl --exclusions $FX/excl_alu41.txt
expect stale_exclusion      1 "STALE EXCLUSION" -- $FX/all_hit.dat      --rtl-dir rtl --exclusions $FX/excl_alu41.txt
expect no_bins_is_error     2 "no cover bins"   -- "$tmp/no_bins.dat"   --rtl-dir rtl --exclusions "$tmp/no_exclusions.txt"
expect missing_file         2 "cannot read"    -- "$tmp/does_not_exist.dat" --rtl-dir rtl --exclusions "$tmp/no_exclusions.txt"
exit "$fail"
