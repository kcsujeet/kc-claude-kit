#!/usr/bin/env bash
# Tests hooks/check-installed.sh in its three states: rules missing, rules stale
# (no stamp, or a stamp for another version), and rules current.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
hook="$(dirname "$tests_dir")/hooks/check-installed.sh"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

mkdir -p "$work_dir/plugin/.claude-plugin" "$work_dir/home" "$work_dir/project/.git"
printf '{\n  "name": "conventions",\n  "version": "9.8.7"\n}\n' > "$work_dir/plugin/.claude-plugin/plugin.json"

failures=0
run_hook() {
  (cd "$work_dir/project" && HOME="$work_dir/home" CLAUDE_PLUGIN_ROOT="$work_dir/plugin" bash "$hook")
}
expect_output() {
  local label=$1 expected=$2 actual
  actual=$(run_hook)
  if [ "$actual" = "$expected" ]; then
    echo "ok   $label"
  else
    echo "FAIL $label"
    echo "     expected: $expected"
    echo "     actual:   $actual"
    failures=$((failures + 1))
  fi
}

expect_output "missing: no rules installed" \
  "The portable coding conventions are not installed in this project. Run /conventions:init to copy them into .claude/rules/, or say so if this project should not have them."

mkdir -p "$work_dir/project/.claude/rules"
touch "$work_dir/project/.claude/rules/working-agreement.md"
expect_output "stale: rules without a version stamp" \
  "The portable coding conventions in .claude/rules carry no version stamp, so they may predate conventions plugin 9.8.7. Run /conventions:init to refresh them."

echo "1.0.2" > "$work_dir/project/.claude/rules/.kc-conventions-version"
expect_output "stale: stamp for an older version" \
  "The portable coding conventions in .claude/rules are from conventions plugin 1.0.2, but 9.8.7 is installed. Run /conventions:init to refresh them."

echo "9.8.7" > "$work_dir/project/.claude/rules/.kc-conventions-version"
expect_output "current: stamp matches the plugin" ""

echo "$((4 - failures)) passed, $failures failed"
[ "$failures" -eq 0 ]
