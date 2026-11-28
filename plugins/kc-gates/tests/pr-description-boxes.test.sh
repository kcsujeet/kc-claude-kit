#!/usr/bin/env bash
# Checks that the PR-description boxes exist in kc-ready-for-human-review (§H10, §H9) and kc-code-review
# (§G9, §G10), and that the evidence box names `--attach`.
set -euo pipefail

plugin_dir=$(cd "$(dirname "$0")/.." && pwd)
failures=0
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

for f in kc-ready-for-human-review/SKILL.md kc-ready-for-human-review/references/detail.md kc-code-review/SKILL.md kc-code-review/references/detail.md; do
  file="$plugin_dir/skills/$f"
  case "$f" in kc-ready*) short=§H10; evid=§H9 ;; *) short=§G9; evid=§G10 ;; esac
  grep -qE "^- \[ \] $short The PR description .*(short|reads).*no process notes" "$file" || fail "$f: $short short-description box missing"
  grep -E "^- \[ \] $evid " "$file" | grep -q -- '--attach' || fail "$f: $evid must name --attach"
done

[ "$failures" -eq 0 ] && echo "ok   pr-description boxes"
exit "$failures"
