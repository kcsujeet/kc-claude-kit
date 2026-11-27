#!/usr/bin/env bash
# Tests that each review sweep added for a box is named by that box and flags its fixture case:
# §R12 pass-through-hooks.sh, §P1 near-copies.sh, §N14 near-synonym-names.sh. The exact output of
# each sweep is held by run-sweeps.sh; this holds the box-to-sweep link and the case each catches.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
passes=0
failures=0

check() {
  local label=$1; shift
  if "$@" >/dev/null 2>&1; then echo "ok   $label"; passes=$((passes + 1)); else echo "FAIL $label"; failures=$((failures + 1)); fi
}

# Runs a sweep on its fixture, with the fixture's repo as a git work tree when it has one.
run_sweep() {
  local topic=$1 sweep=$2 fixture="$tests_dir/sweeps/$1/$2" repo_copy
  if [ -d "$fixture/repo" ]; then
    repo_copy="$work_dir/$sweep"
    cp -R "$fixture/repo" "$repo_copy"
    git -C "$repo_copy" init -q
    (cd "$repo_copy" && find . -type f -not -path './.git/*' | sed 's|^\./||') | while IFS= read -r path; do
      if [ -f "$fixture/untracked.txt" ] && grep -qxF "$path" "$fixture/untracked.txt"; then continue; fi
      git -C "$repo_copy" add -- "$path"
    done
    bash "$plugin_dir/skills/$topic/scripts/$sweep.sh" "$fixture/input.diff" "$repo_copy"
  else
    bash "$plugin_dir/skills/$topic/scripts/$sweep.sh" "$fixture/input.diff"
  fi
}

lacks() { ! grep -q -- "$1" <<< "$2"; }
box_names_sweep() { grep -E "^- \[ \] $1 .*$2" "$plugin_dir/skills/$3/SKILL.md"; }

check "§R12 box names pass-through-hooks.sh" box_names_sweep '§R12' 'pass-through-hooks\.sh' kc-react
check "§P1 box names near-copies.sh" box_names_sweep '§P1' 'near-copies\.sh' kc-simplicity
check "§N14 box names near-synonym-names.sh" box_names_sweep '§N14' 'near-synonym-names\.sh' kc-naming

output=$(run_sweep kc-react pass-through-hooks)
check "§R12 flags a hook whose results only reach a child's props, through a derived value too" grep -q 'OrderPanel.tsx:2: .*useOrderReceipt' <<< "$output"
check "§R12 flags a hook left in place when the diff turns its own use into a prop" grep -q 'RefundPanel.tsx:2: .*useRefund' <<< "$output"
check "§R12 passes a hook the component reads itself" lacks useOrderTotals "$output"

output=$(run_sweep kc-simplicity near-copies)
check "§P1 flags a new test helper that near-copies an existing one" grep -q 'enableExpressShipping.ts:1: near copy of tests/enableGiftWrap.ts' <<< "$output"
check "§P1 passes a new file with no near copy" lacks formatOrderNumber "$output"

output=$(run_sweep kc-naming near-synonym-names)
check "§N14 flags names in one scope that share a word" grep -q 'hasPaymentError' <<< "$output"
check "§N14 passes a name sharing no word with its neighbours" lacks canCancel "$output"

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
