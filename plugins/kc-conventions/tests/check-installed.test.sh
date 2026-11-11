#!/usr/bin/env bash
# Tests hooks/check-installed.sh: its three states (rules missing, rules stale with no stamp or a
# stamp for another version, rules current), the folder it checks (the payload's `cwd`, not the
# one it was started in), a stale copy in the home folder, and saying each state once per session.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
hook="$(dirname "$tests_dir")/hooks/check-installed.sh"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

mkdir -p "$work_dir/plugin/.claude-plugin" "$work_dir/home" "$work_dir/project/.git" "$work_dir/spare" "$work_dir/data"
printf '{\n  "name": "conventions",\n  "version": "9.8.7"\n}\n' > "$work_dir/plugin/.claude-plugin/plugin.json"

failures=0
cases=0
# Runs the hook from <start dir> with <payload> on stdin (empty: run by hand, no payload).
run_hook_from() {
  local start_dir=$1 payload=$2
  (cd "$start_dir" && printf '%s' "$payload" \
    | HOME="$work_dir/home" CLAUDE_PLUGIN_ROOT="$work_dir/plugin" CLAUDE_PLUGIN_DATA="$work_dir/data" bash "$hook")
}
expect_output() {
  local label=$1 expected=$2 actual=$3
  cases=$((cases + 1))
  if [ "$actual" = "$expected" ]; then
    echo "ok   $label"
  else
    echo "FAIL $label"
    echo "     expected: $expected"
    echo "     actual:   $actual"
    failures=$((failures + 1))
  fi
}
payload_for() { printf '{"session_id":"%s","cwd":"%s","prompt":"hello"}' "$1" "$2"; }

not_installed="The portable coding conventions are not installed in this project. Run /kc-conventions:kc-init to copy them into .claude/rules/, or say so if this project should not have them."
project_stale="The portable coding conventions in .claude/rules are from kc-conventions plugin 1.0.2, but 9.8.7 is installed: this session loaded the older rules, which may lack steps the newer plugins rely on. Run /kc-conventions:kc-init to refresh them."
home_stale="The portable coding conventions in $work_dir/home/.claude/rules are from kc-conventions plugin 1.0.2, but 9.8.7 is installed: this session loaded the older rules, which may lack steps the newer plugins rely on. Refresh them with: bash \"$work_dir/plugin/scripts/install-rules.sh\" --dest \"$work_dir/home/.claude/rules\""

# Run by hand in the project, no payload.
expect_output "missing: no rules installed" "$not_installed" "$(run_hook_from "$work_dir/project" "")"

mkdir -p "$work_dir/project/.claude/rules"
touch "$work_dir/project/.claude/rules/kc-working-agreement.md"
expect_output "stale: rules without a version stamp" \
  "The portable coding conventions in .claude/rules carry no version stamp, so they may predate kc-conventions plugin 9.8.7. Run /kc-conventions:kc-init to refresh them." \
  "$(run_hook_from "$work_dir/project" "")"

echo "1.0.2" > "$work_dir/project/.claude/rules/.kc-conventions-version"
expect_output "stale: stamp for an older version" "$project_stale" "$(run_hook_from "$work_dir/project" "")"

# The session started in a spare folder with no .git and moved to the project: the payload's
# cwd is the folder checked.
expect_output "payload cwd: checks the project the session is in, not the folder it was started in" \
  "$project_stale" "$(run_hook_from "$work_dir/spare" "$(payload_for s1 "$work_dir/project")")"
expect_output "once: the same state is not repeated in the same session" \
  "" "$(run_hook_from "$work_dir/spare" "$(payload_for s1 "$work_dir/project")")"
expect_output "once: another session is told" \
  "$project_stale" "$(run_hook_from "$work_dir/spare" "$(payload_for s2 "$work_dir/project")")"

echo "9.8.7" > "$work_dir/project/.claude/rules/.kc-conventions-version"
expect_output "current: stamp matches the plugin" "" "$(run_hook_from "$work_dir/project" "")"
expect_output "current: nothing said with a payload either" \
  "" "$(run_hook_from "$work_dir/spare" "$(payload_for s3 "$work_dir/project")")"

# A copy in the home folder serves every project; it is checked where there is no project copy,
# in a folder with no .git too, and the notice names the command that refreshes it in place.
mkdir -p "$work_dir/home/.claude/rules"
touch "$work_dir/home/.claude/rules/kc-working-agreement.md"
echo "1.0.2" > "$work_dir/home/.claude/rules/.kc-conventions-version"
expect_output "home copy: stale, in a folder that is no project" \
  "$home_stale" "$(run_hook_from "$work_dir/spare" "$(payload_for s4 "$work_dir/spare")")"
expect_output "home copy: a new state in the same session is told again" \
  "The portable coding conventions in $work_dir/home/.claude/rules carry no version stamp, so they may predate kc-conventions plugin 9.8.7. Refresh them with: bash \"$work_dir/plugin/scripts/install-rules.sh\" --dest \"$work_dir/home/.claude/rules\"" \
  "$(rm "$work_dir/home/.claude/rules/.kc-conventions-version"; run_hook_from "$work_dir/spare" "$(payload_for s4 "$work_dir/spare")")"
rm -rf "$work_dir/home/.claude"

# A caller that keeps stdin open and sends nothing must not hang the hook: stdin here is a pipe
# whose writer stays silent for fifteen seconds, so a hook that waits for it fails the time check
# below instead of hanging the suite.
mkfifo "$work_dir/held-open"
run_with_open_stdin() {
  local silent_writer
  sleep 15 > "$work_dir/held-open" &
  silent_writer=$!
  (cd "$work_dir/project" \
    && HOME="$work_dir/home" CLAUDE_PLUGIN_ROOT="$work_dir/plugin" CLAUDE_PLUGIN_DATA="$work_dir/data" bash "$hook" \
      < "$work_dir/held-open")
  kill "$silent_writer" 2>/dev/null
  wait "$silent_writer" 2>/dev/null || true
}
started=$SECONDS
echo "1.0.2" > "$work_dir/project/.claude/rules/.kc-conventions-version"
expect_output "open stdin, no payload: checks the current folder and speaks, as when run by hand" \
  "$project_stale" "$(run_with_open_stdin)"
echo "9.8.7" > "$work_dir/project/.claude/rules/.kc-conventions-version"
expect_output "open stdin, no payload: quiet when current" "" "$(run_with_open_stdin)"
expect_output "open stdin, no payload: both runs returned within 10 s" \
  "yes" "$([ $((SECONDS - started)) -lt 10 ] && echo yes || echo no)"

expect_output "no project, nothing installed: quiet" \
  "" "$(run_hook_from "$work_dir/spare" "$(payload_for s5 "$work_dir/spare")")"

echo "$((cases - failures)) passed, $failures failed"
[ "$failures" -eq 0 ]
