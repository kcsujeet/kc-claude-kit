#!/usr/bin/env bash
# Tests scripts/remind-reload.sh: every command that changes the installed plugins gets the
# reload reminder (in the desktop app, a statement that it reloads itself); reads, help and other
# claude commands get nothing. Each case runs twice, once
# with jq and once through the sed fallback.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
hook="$(dirname "$tests_dir")/scripts/remind-reload.sh"
# The cases below are for a host that does not reload on its own; the desktop app sets this.
unset CLAUDE_CODE_ENTRYPOINT

build_payload() {
  local command
  command=$(printf '%s' "$1" | sed 's/"/\\"/g')
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"test"},"tool_response":{"stdout":"","stderr":""},"tool_use_id":"t"}' "$work_dir" "$command"
}

expect_hook() {
  local expectation=$1 label=$2 command=$3 mode output verdict
  for mode in jq sed; do
    if [ "$mode" = jq ] && ! command -v jq >/dev/null 2>&1; then
      continue
    fi
    if [ "$mode" = sed ]; then
      output=$(build_payload "$command" | KC_GUARD_NO_JQ=1 bash "$hook")
    else
      output=$(build_payload "$command" | bash "$hook")
    fi
    if [ -z "$output" ]; then
      verdict=quiet
    elif printf '%s' "$output" | grep -q '"hookEventName":"PostToolUse","additionalContext":"kc-gates: this changed the installed plugins'; then
      verdict=remind
    else
      verdict="unexpected output: $output"
    fi
    expect_eq "[$mode] $label" "$expectation" "$verdict"
  done
}

# --- changes to the installed plugins ------------------------------------------------------------
expect_hook remind "claude plugin update" "claude plugin update shop-rules@shop-kit"
expect_contains "the reminder asks for the reload as the turn's one question" \
  "Ask the person for /reload-plugins now, as the turn's one question" \
  "$(build_payload "claude plugin update shop-rules@shop-kit" | bash "$hook")"
expect_hook remind "claude plugin install" "claude plugin install shop-rules@shop-kit"
expect_hook remind "claude plugin enable" "claude plugin enable shop-rules@shop-kit"
expect_hook remind "claude plugin marketplace update" "claude plugin marketplace update shop-kit"
expect_hook remind "an update inside a loop" "for p in a b; do claude plugin update \$p@shop-kit; done"
expect_hook remind "an update after another command" "cd /tmp && claude plugin update shop-rules@shop-kit"

# --- not changes -------------------------------------------------------------------------------
expect_hook quiet "listing plugins" "claude plugin list"
expect_hook quiet "validating a plugin" "claude plugin validate . --strict"
expect_hook quiet "testing a plugin" "claude plugin test plugins/shop-band"
expect_hook quiet "help for update" "claude plugin update --help"
expect_hook quiet "updating the CLI itself" "claude update"
expect_hook quiet "a word that only ends in claude" "myclaude plugin update x"
expect_hook quiet "an unrelated command" "git push origin main"

# --- the desktop app reloads live sessions itself -----------------------------------------------
desktop_output=$(build_payload "claude plugin update shop-rules@shop-kit" | CLAUDE_CODE_ENTRYPOINT=claude-desktop bash "$hook")
expect_contains "the desktop app is told to state that it reloads on its own" \
  "reloads this session itself when this turn ends" "$desktop_output"
expect_contains "the desktop statement says there is nothing to type" "there is nothing to type" "$desktop_output"
expect_contains "the desktop statement goes first in the reply" "Make it the first line of your reply" "$desktop_output"
expect_contains "the desktop statement says never leave the person guessing" "never be left guessing" "$desktop_output"
expect_eq "the desktop app is not asked for /reload-plugins" no \
  "$(printf '%s' "$desktop_output" | grep -q 'Ask the person for /reload-plugins' && echo yes || echo no)"
expect_eq "nothing for a non-plugin command in the desktop app" "" \
  "$(build_payload "git push origin main" | CLAUDE_CODE_ENTRYPOINT=claude-desktop bash "$hook")"
expect_contains "another host's reminder also says never leave the person guessing" "never be left guessing" \
  "$(build_payload "claude plugin update shop-rules@shop-kit" | CLAUDE_CODE_ENTRYPOINT=cli bash "$hook")"
expect_contains "another host still gets the reminder" "Ask the person for /reload-plugins now" \
  "$(build_payload "claude plugin update shop-rules@shop-kit" | CLAUDE_CODE_ENTRYPOINT=cli bash "$hook")"

finish
