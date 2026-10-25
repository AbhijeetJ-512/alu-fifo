#!/usr/bin/env bash
# rules_selftest.sh - each bad fixture must be stopped by exactly the rule it is bound to,
# and the real rtl/ must pass. A rule that never fires would leave its fixture un-noticed.
set -u
cd "$(dirname "$0")/.."

fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

check() { # <fixture> <expected rule>
  rm -rf "${tmp:?}"/*
  cp "verif/fixtures/rules/$1.sv" "$tmp/"
  out=$(scripts/rules.sh "$tmp" 2>&1)
  rc=$?
  got=$(printf '%s\n' "$out" | sed -n 's/^RULE \([A-Z-]*\):.*/\1/p' | sort -u | tr '\n' ' ' | sed 's/ $//')
  if [ "$rc" -ne 0 ] && [ "$got" = "$2" ]; then
    echo "ok $1 -> $2"
  else
    echo "FAIL $1: expected only $2 with a non-zero exit, got rc=$rc rules='$got'"
    fail=1
  fi
}

check bad_initial  R-INITIAL
check bad_always   R-ALWAYS
check bad_display  R-DISPLAY
check bad_sva      R-SVA
check bad_tristate R-TRISTATE

if scripts/rules.sh rtl >/dev/null 2>&1; then
  echo "ok rtl/ passes every rule"
else
  echo "FAIL rtl/ violates a rule:"
  scripts/rules.sh rtl
  fail=1
fi
exit "$fail"
