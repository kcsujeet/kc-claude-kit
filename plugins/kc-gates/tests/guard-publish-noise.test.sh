#!/usr/bin/env bash
# Tests scripts/guard-publish-noise.sh: a command that publishes a file holding a command-line
# tool's own notice is denied; the same file without it, and commands that publish nothing, pass.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
guard="$(dirname "$tests_dir")/scripts/guard-publish-noise.sh"
require_jq

# Runs the guard on a Bash <command> run from the work dir; prints deny or allow.
run_command() {
  local output
  output=$(jq -cn --arg command "$1" --arg cwd "$work_dir" '{hook_event_name: "PreToolUse", tool_name: "Bash", cwd: $cwd, tool_input: {command: $command}}' | bash "$guard")
  printf '%s' "$output" > "$work_dir/last-output"
  if printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then echo deny; else echo allow; fi
}

printf 'hint: if you need to wait for this pull request, use gh event listen\nORD-1\n\n## Description\nShows the order total.\n' > "$work_dir/pr-body.md"
printf 'ORD-1\n\n## Description\nShows the order total.\n' > "$work_dir/clean-body.md"
printf 'npm WARN deprecated left-pad@1.0.0\n## 2.1.0\n- Storefront search\n' > "$work_dir/notes.md"
printf 'Fix the storefront total\n\n\033[32mok\033[0m 12 tests\n' > "$work_dir/commit-msg.txt"
printf '(node:4242) ExperimentalWarning: fetch is experimental\nRefund fails for a split payment\n' > "$work_dir/issue.md"

expect_eq "publish-noise: a pull request body read back with the CLI's hint is denied" deny "$(run_command 'gh pr edit 7 --body-file pr-body.md')"
expect_contains "the denial says to read the field raw" "read the field raw" "$(cat "$work_dir/last-output")"
expect_eq "publish-noise: the same body without the notice is allowed" allow "$(run_command 'gh pr edit 7 --body-file clean-body.md')"
expect_eq "publish-noise: release notes carrying an npm warning are denied" deny "$(run_command 'gh release create v2.1.0 --notes-file notes.md')"
expect_eq "publish-noise: a commit message with colour codes is denied" deny "$(run_command 'git commit -F commit-msg.txt')"
expect_eq "publish-noise: an issue body from an API field file with a Node warning is denied" deny "$(run_command 'gh api -X POST repos/o/r/issues -F body=@issue.md')"
expect_eq "publish-noise: an absolute path is read too" deny "$(run_command "gh pr create --title T --body-file $work_dir/pr-body.md")"
expect_eq "publish-noise: a command that publishes no file passes" allow "$(run_command 'gh pr view 7 --json body')"
expect_eq "publish-noise: a missing file is not blocked" allow "$(run_command 'gh pr edit 7 --body-file gone.md')"
expect_eq "an empty payload prints nothing" "" "$(printf '{}' | bash "$guard")"

finish
