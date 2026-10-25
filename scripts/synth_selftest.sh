#!/usr/bin/env bash
# synth_selftest.sh [--deep] - the synthesis checks must stop exactly the bad inputs they are bound to.
#
# Plain mode: every fixture is run through the script that owns its check; the check that opened
# (CHECK <name>) and never passed (PASS <name>) when Yosys stopped must be the bound one, and the good
# netlist must pass.
# --deep: for each check, delete it from a copy of its script, then replace its command with one that
# always passes (banners kept); the fixture suite must then FAIL on exactly the fixtures bound to
# that check. Counting checks proves nothing; a check that cannot make its fixture go wrong is dead.
set -u
cd "$(dirname "$0")/.."
YOSYS=${YOSYS:-yosys}
FULL_LIB=sky130hd/sky130hd_tt.lib
SYNTH_LIB=build/sky130hd_synth.lib
FX=verif/fixtures/synth
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# <kind>:<top>:<fixture>:<expected>   kind rtl -> scripts/synth.ys, net -> scripts/netlist_check.ys
CASES="
rtl:latch_top:latch.sv:no-latch
rtl:tribuf_top:tribuf.sv:no-tribuf
rtl:undriven_top:undriven.sv:check-rtl
rtl:multidrive_top:multidrive.sv:check-rtl
net:top:net_good.v:pass
net:top:net_generic.v:all-mapped
net:top:net_lpflow.v:no-lpflow
net:top:net_multidrive.v:check-assert
"

# run_case <rtl|net> <script> <top> <fixture>  -> echoes "pass", or the check blamed for the error
run_case() {
  local kind=$1 script=$2 top=$3 fixture=$4 ys="$tmp/run.ys" log="$tmp/y.log"
  mkdir -p "$tmp/out/reports"
  sed -e "s|@SOURCES@|$FX/$fixture|g" -e "s|@NETLIST@|$FX/$fixture|g" -e "s|@TOP@|$top|g" \
      -e "s|@LIB@|$SYNTH_LIB|g" -e "s|@FULL_LIB@|$FULL_LIB|g" -e "s|@PERIOD_PS@|10000|g" \
      -e "s|@OUTDIR@|$tmp/out|g" "$script" > "$ys"
  if $YOSYS -q -l "$log" -s "$ys" >/dev/null 2>&1; then
    echo pass
  else
    # blame the check that opened (CHECK <n>) and never passed (PASS <n>); none open = failed outside a check
    awk '/^CHECK /{open=$2} /^PASS /{if ($2==open) open=""} END{print (open=="" ? "error-outside-any-check" : open)}' "$log"
  fi
}

# suite <synth.ys> <netlist_check.ys> [print]  -> sets FAILED to the space-separated list of fixtures whose result differs
suite() {
  FAILED=""
  local kind top fixture expect script got
  for c in $CASES; do
    IFS=: read -r kind top fixture expect <<< "$c"
    if [ "$kind" = rtl ]; then script=$1; else script=$2; fi
    got=$(run_case "$kind" "$script" "$top" "$fixture")
    if [ "$got" = "$expect" ]; then
      [ "${3:-}" = print ] && echo "ok $fixture -> $expect"
    else
      [ "${3:-}" = print ] && echo "FAIL $fixture: expected '$expect', got '$got'"
      FAILED="$FAILED $fixture"
    fi
  done
}

suite scripts/synth.ys scripts/netlist_check.ys print
[ -z "$FAILED" ] || exit 1
[ "${1:-}" = --deep ] || exit 0

# ---- deep mode ----
rc=0
for spec in synth.ys:check-rtl synth.ys:no-latch synth.ys:no-tribuf \
            netlist_check.ys:check-assert netlist_check.ys:all-mapped netlist_check.ys:no-lpflow; do
  file=${spec%%:*}; name=${spec##*:}
  bound=$(echo "$CASES" | awk -F: -v n="$name" '$4==n {printf " %s", $3}')
  for variant in delete neutralise; do
    cp scripts/synth.ys "$tmp/synth.ys"; cp scripts/netlist_check.ys "$tmp/netlist_check.ys"
    awk -v n="$name" -v v="$variant" '
      $0 == "log CHECK " n { if (v == "delete") { getline; getline; next }
                             print; getline; print "log neutralised"; next }
      { print }' "scripts/$file" > "$tmp/$file"
    suite "$tmp/synth.ys" "$tmp/netlist_check.ys"
    if [ "$(echo $FAILED)" = "$(echo $bound)" ] && [ -n "$bound" ]; then
      echo "ok   $variant $name -> only$bound went wrong"
    else
      echo "FAIL $variant $name: expected exactly [$(echo $bound)] to go wrong, got [$(echo $FAILED)]"; rc=1
    fi
  done
done
exit $rc
