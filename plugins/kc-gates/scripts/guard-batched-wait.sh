#!/usr/bin/env bash
# PreToolUse guard for Bash and the REPL tool: a wait on several independent results returns only
# when the slowest ends, so the first result sits unused and a hung one hides; a wait with a long
# timeout hides a hang. It denies a command or REPL script that
#
#   a. starts two or more CI watches (gh pr checks ... --watch, gh run watch), chained or inside
#      Promise.all; or
#   b. starts a CI watch with a timeout over 10 minutes: the call's timeout parameter, or a
#      .timeout(n) in the script, above 600000 ms.
#
# Poll each result on its own with a short timeout and act on each as it lands. Other commands are
# untouched. It never blocks what it can't read: no jq or an unreadable payload exits 0.
#
# Output: the PreToolUse deny JSON, or nothing. Hook schema: https://code.claude.com/docs/en/hooks
set -u

scripts_dir=$(dirname "$0")
# shellcheck source=lib/hook-input.sh
. "$scripts_dir/lib/hook-input.sh"

readonly CI_WATCH='gh[[:space:]]+(pr[[:space:]]+checks[^;&|"'"'"'`]*--watch|run[[:space:]]+watch)'
readonly MAX_WATCH_TIMEOUT_MS=600000

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
script=$(printf '%s' "$payload" | jq -r '.tool_input.command // .tool_input.code // empty' 2>/dev/null) || exit 0
[ -n "$script" ] || exit 0
call_timeout=$(printf '%s' "$payload" | jq -r '.tool_input.timeout // empty | tostring' 2>/dev/null)

watch_count=$(printf '%s\n' "$script" | grep -Eo "$CI_WATCH" | wc -l | tr -d ' ')
[ "$watch_count" -ge 1 ] || exit 0

if [ "$watch_count" -ge 2 ]; then
  print_pretooluse_deny "Blocked by the kc-gates plugin: this call waits on $watch_count CI watches together, so it returns only when the slowest ends: the first result sits unused and a hung one hides. Poll each result on its own with a short timeout and act on each as it lands."
  exit 0
fi

# The longest timeout the call sets: the tool's own parameter, or a .timeout(n) in the script.
longest_timeout=0
for candidate in $call_timeout $(printf '%s' "$script" | grep -Eo '\.timeout\([0-9_]+\)' | tr -dc '0-9\n_' | tr -d '_'); do
  case "$candidate" in '' | *[!0-9]*) continue ;; esac
  [ "$candidate" -le "$longest_timeout" ] || longest_timeout=$candidate
done
if [ "$longest_timeout" -gt "$MAX_WATCH_TIMEOUT_MS" ]; then
  print_pretooluse_deny "Blocked by the kc-gates plugin: this CI watch has a timeout of $longest_timeout ms, over 10 minutes, which hides a hang. Poll the result on its own with a short timeout and act on it when it lands."
fi
exit 0
