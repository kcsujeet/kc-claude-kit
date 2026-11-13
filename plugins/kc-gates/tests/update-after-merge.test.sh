#!/usr/bin/env bash
# Tests scripts/update-after-merge.sh against a copy of the scripts whose update-marketplace.sh is
# a stub: it logs each run with its switches, and installs a new version (rewrites
# installed_plugins.json) or prints a failure notice when the test says so.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL jq is required to run these tests"
  exit 1
fi

scripts="$work_dir/scripts"
cp -R "$(dirname "$tests_dir")/scripts" "$scripts"
config="$work_dir/config"
mkdir -p "$config/plugins"
installed_plugins_file="$config/plugins/installed_plugins.json"
update_log="$work_dir/update.log"
cat > "$scripts/update-marketplace.sh" <<STUB
#!/usr/bin/env bash
echo "now=\${KC_UPDATE_NOW:-} event=\${KC_HOOK_EVENT:-}" >> "$update_log"
case "\${STUB_RESULT:-none}" in
  installs) echo '{"version":2,"plugins":{"kc-gates@shop-kit":[{"version":"2.0.0"}]}}' > "$installed_plugins_file" ;;
  fails) echo '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Updating failed: x"}}' ;;
  installs-some)
    echo '{"version":2,"plugins":{"kc-gates@shop-kit":[{"version":"2.0.0"}]}}' > "$installed_plugins_file"
    echo '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Updating failed: x"}}' ;;
esac
exit 0
STUB

# Runs the hook on <command> with the stub's <result> (none, installs, fails, installs-some) and any extra
# VAR=value; prints its output.
run_hook() {
  local command=$1 result=$2
  shift 2
  echo '{"version":2,"plugins":{"kc-gates@shop-kit":[{"version":"1.0.0"}]}}' > "$installed_plugins_file"
  : > "$update_log"
  jq -cn --arg c "$command" '{tool_input: {command: $c}, cwd: "/tmp"}' \
    | env CLAUDE_CONFIG_DIR="$config" CLAUDE_CODE_ENTRYPOINT=cli STUB_RESULT="$result" "$@" bash "$scripts/update-after-merge.sh"
}

expect_eq "a command that merges nothing: no look, no output" "" "$(run_hook "gh pr view 7" installs)"
expect_eq "and the update script never ran" "" "$(cat "$update_log")"
expect_eq "cancelling a queued merge: no look" "" "$(run_hook "gh pr merge 7 --disable-auto" installs; cat "$update_log")"

expect_eq "a merge with nothing to install: no output" "" "$(run_hook "gh pr merge 7 --squash" none)"
expect_eq "it looked now, with failures worded for PostToolUse" "now=1 event=PostToolUse" "$(cat "$update_log")"

desktop_output=$(run_hook "gh pr merge 7 --squash" installs CLAUDE_CODE_ENTRYPOINT=claude-desktop)
expect_contains "a merge that installs, in the desktop app: says the app reloads by itself" \
  "the desktop app reloads this session itself" "$desktop_output"
cli_output=$(run_hook "cd kit && gh pr merge 7 --squash" installs)
expect_contains "a merge that installs, elsewhere: asks for /reload-plugins" "Ask the person for /reload-plugins" "$cli_output"
expect_contains "a merge through the API counts too" "Ask the person for /reload-plugins" \
  "$(run_hook "gh api -X PUT repos/o/r/pulls/7/merge" installs)"

expect_eq "an update that fails: its notice is passed on" \
  '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Updating failed: x"}}' \
  "$(run_hook "gh pr merge 7" fails)"

partial_output=$(run_hook "gh pr merge 7" installs-some)
expect_contains "some plugins install and one fails: the failure is passed on" "Updating failed: x" "$partial_output"
expect_contains "and the reload is still stated" "Ask the person for /reload-plugins" "$partial_output"
expect_eq "as one JSON object" 1 "$(printf '%s\n' "$partial_output" | jq -s length)"

finish
