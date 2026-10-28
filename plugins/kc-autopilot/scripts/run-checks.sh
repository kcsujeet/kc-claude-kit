#!/usr/bin/env bash
# Runs every command in config.checks inside a worktree and reports each.
# Usage: run-checks.sh <config.json> <worktree>
# Output: "ok   <cmd>" or "FAIL <cmd>" plus the last 60 output lines indented
#   by 4 spaces, then "checks: <passed>/<total> passed".
# Exit: 0 all passed; 1 any failed or checks unreadable/empty; 2 jq missing.
set -euo pipefail
command -v jq >/dev/null 2>&1 || { echo "autopilot: jq is required" >&2; exit 2; }
config=$1 worktree=$2
list=$(jq -er '.checks | if type == "array" and length > 0 then .[] else error("checks must be a non-empty array") end' "$config" 2>&1) || {
  echo "run-checks: cannot read checks from $config: $list" >&2
  exit 1
}
total=0
passed=0
# The list is read on fd 3 and each check gets /dev/null as stdin, so a check
# that reads stdin cannot swallow the remaining checks.
while IFS= read -r check <&3; do
  total=$((total + 1))
  if output=$(cd "$worktree" && bash -c "$check" 2>&1 </dev/null); then
    passed=$((passed + 1))
    echo "ok   $check"
  else
    echo "FAIL $check"
    printf '%s\n' "$output" | tail -n 60 | sed 's/^/    /'
  fi
done 3<<<"$list"
echo "checks: $passed/$total passed"
[ "$passed" = "$total" ]
