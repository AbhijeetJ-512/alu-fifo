#!/usr/bin/env bash
# rules.sh <dir> - RTL style gate. Prints "RULE <name>: <file>:<line>" per violation, exits 1 if any.
#   R-INITIAL   no initial blocks
#   R-ALWAYS    only always_comb and always_ff @(posedge clk ...)
#   R-DISPLAY   no $display/$write/$error/$fatal/$warning/$info (the one-line DEPTH guard, marked g_bad_depth, is exempt)
#   R-SVA       no assert/assume/cover property, no assert ( ... ) - those live in verif/
#   R-TRISTATE  no high-impedance drive
# Latches are caught by Verilator -Wall (make lint) and the Yosys checks (make synth), not here.
set -u
dir=${1:?usage: rules.sh <dir>}

files=$(find "$dir" -name '*.sv' | sort)
[ -n "$files" ] || { echo "rules.sh: no .sv files under $dir" >&2; exit 2; }

out=""
# hits <rule> <file> <pattern> [exempt-pattern]: append "RULE <rule>: <file>:<line>" for each matching line
hits() {
  local rule=$1 f=$2 pat=$3 exempt=${4:-}
  local lines
  lines=$(grep -HnP -e "$pat" "$f" || true)
  [ -n "$exempt" ] && lines=$(printf '%s\n' "$lines" | grep -v -e "$exempt" || true)
  [ -n "$lines" ] || return 0
  out+=$(printf '%s\n' "$lines" | cut -d: -f1,2 | sed "s/^/RULE $rule: /")$'\n'
}

for f in $files; do
  hits R-INITIAL  "$f" '^\s*initial\b'
  hits R-ALWAYS   "$f" '\balways(?!_comb\b)(?!_ff\s*@\s*\(\s*posedge\s+clk\b)\w*'
  hits R-DISPLAY  "$f" '\$(display|write|error|fatal|warning|info)\b' 'g_bad_depth'
  hits R-SVA      "$f" "\b(assert|assume|cover)\s+property\b|\bassert\s*\("
  hits R-TRISTATE "$f" "1'b[zZ]|'[zZ]\b"
done

if [ -n "$out" ]; then
  printf '%s' "$out"
  exit 1
fi
exit 0
