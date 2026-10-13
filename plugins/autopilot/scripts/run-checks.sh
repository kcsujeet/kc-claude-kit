#!/usr/bin/env bash
# Runs every command in config.checks inside a worktree and reports each.
# Usage: run-checks.sh <config.json> <worktree>
# Output: "ok   <cmd>" or "FAIL <cmd>" plus the last 60 output lines indented
#   by 4 spaces, then "checks: <passed>/<total> passed".
# Exit: 0 all passed; 1 any failed; 2 jq missing.
set -euo pipefail
command -v jq >/dev/null 2>&1 || { echo "autopilot: jq is required" >&2; exit 2; }
config=$1 worktree=$2
total=0
passed=0
while IFS= read -r check; do
  total=$((total + 1))
  if output=$(cd "$worktree" && bash -c "$check" 2>&1); then
    passed=$((passed + 1))
    echo "ok   $check"
  else
    echo "FAIL $check"
    printf '%s\n' "$output" | tail -n 60 | sed 's/^/    /'
  fi
done < <(jq -r '.checks[]' "$config")
echo "checks: $passed/$total passed"
[ "$passed" = "$total" ]
