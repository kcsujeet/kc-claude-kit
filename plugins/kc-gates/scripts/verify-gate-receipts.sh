#!/usr/bin/env bash
# The receipts half of the verification gate, as a script: for each trigger group the round's diff
# hits, checks that the gate that owns it left its headline receipt in its saved verdict block.
# It counts text; whether a receipt is honest, a library claim is cited or a finding was defended
# with a run is the verification agent's call. Per-hit verdicts, citations and SCOPE: are
# verify-gate-blocks.sh's.
#
# Usage: verify-gate-receipts.sh <round-dir>
#   <round-dir>  A round folder of a pass: verdicts/ (one file per gate block, named <gate>.txt),
#                review.diff and changed-files.txt.
#
# A group applies when the diff's added lines (or changed files) show its trigger. Each group names
# the gate file that must hold the receipt:
#   locale files changed              i18n.txt         a per-key row (`dupe:`)
#   && or || added                    naming.txt       grepped &&/||: N hits
#   ternary, as-cast, any, non-null !, conditional spread, numeric literal added
#                                     clarity.txt      grepped <construct>: N hits, one line each
#   switch or else if added           structure.txt    grepped switch/else-if/IIFE: N hits
#   hook, query or mutation added     react.txt        grepped mutateAsync: N hits
#   test file changed                 testing.txt      grepped class assertions / loose assertions
#   security gate ran (not N/A)       security.txt     grepped request surface: N hits
# A gate with no verdict file is not read (verify-gate-blocks.sh reports a missing block).
#
# Prints one line per missing receipt and exits 1; otherwise prints one line per group walked and
# exits 0. Exits 2 on a usage error.
set -euo pipefail

script_name=$(basename "$0")
[ "$#" -eq 1 ] || { echo "usage: $script_name <round-dir>" >&2; exit 2; }
round_dir=$1
for required in review.diff changed-files.txt; do
  [ -f "$round_dir/$required" ] || { echo "$script_name: no $round_dir/$required" >&2; exit 2; }
done
[ -d "$round_dir/verdicts" ] || { echo "$script_name: no $round_dir/verdicts" >&2; exit 2; }

added=$(grep -E '^\+' "$round_dir/review.diff" | grep -vE '^\+\+\+' || true)
added_code=$(printf '%s\n' "$added" | grep -vE '^\+[[:space:]]*(//|#|\*|/\*)' || true)
changed=$(cat "$round_dir/changed-files.txt")
problems=0
walked=0

# needs <group> <gate> <receipt pattern>...: the gate's file must match every pattern.
needs() {
  local group=$1 gate=$2 pattern
  shift 2
  local file="$round_dir/verdicts/$gate.txt"
  [ -f "$file" ] || return 0
  walked=$((walked + 1))
  for pattern in "$@"; do
    if ! grep -Eq -- "$pattern" "$file"; then
      echo "$gate.txt: $group: no receipt matching \"$pattern\" (state it, \"0 hits\" when true)"
      problems=$((problems + 1))
    fi
  done
}
has() { printf '%s\n' "$added_code" | grep -Eq -- "$1"; }

if printf '%s\n' "$changed" | grep -Eq '(^|/)(locales?|i18n|messages|translations)/.*\.json$'; then
  needs "locale files changed" i18n 'dupe:'
fi
if has '(&&|\|\|)'; then
  needs "boolean logic added" naming 'grepped &&/\|\|: [0-9]+ hits?'
fi
if printf '%s\n' "$changed" | grep -Eq '\.(tsx?|jsx?)$'; then
  has ' \? .* : ' && needs "ternary added" clarity 'grepped ternaries: [0-9]+ hits?'
  has '[[:space:])]as [A-Za-z{(]' && needs "cast added" clarity 'grepped as-casts: [0-9]+ hits?'
  has '(: any\b|<any>|as any\b)' && needs "any added" clarity 'grepped any: [0-9]+ hits?'
  has '[A-Za-z0-9_)\]]!(\.|\)|;|,|\[)' && needs "non-null assertion added" clarity 'grepped non-null assertions: [0-9]+ hits?'
  has '\.\.\.\(.*\?' && needs "conditional spread added" clarity 'grepped conditional spreads: [0-9]+ hits?'
  has '(^|[^A-Za-z0-9_."'"'"'#-])[0-9]{2,}([^A-Za-z0-9_]|$)' && needs "numeric literal added" clarity 'grepped numeric literals: [0-9]+ hits?'
  has '(\bswitch \(|\belse if\b)' && needs "chain added" structure 'grepped switch/else-if/IIFE: [0-9]+ hits?'
  has '(useQuery|useMutation|export (const|function) use[A-Z])' && needs "hook, query or mutation added" react 'grepped mutateAsync: [0-9]+ hits?'
fi
if printf '%s\n' "$changed" | grep -Eq '(\.(test|spec)\.[a-z]+$|_spec\.rb$|_test\.[a-z]+$|(^|/)(tests?|spec|__tests__)/)'; then
  needs "test file changed" testing 'grepped class assertions: [0-9]+ hits?' 'grepped loose assertions: [0-9]+ hits?'
fi
if [ -f "$round_dir/verdicts/security.txt" ] && ! grep -Eq '^STATUS: PASS \(N/A\)' "$round_dir/verdicts/security.txt"; then
  needs "security gate ran" security 'grepped request surface: [0-9]+ hits?'
fi

if [ "$problems" -gt 0 ]; then
  exit 1
fi
echo "receipts: $walked trigger group(s) the diff hits, each with its headline receipt"
