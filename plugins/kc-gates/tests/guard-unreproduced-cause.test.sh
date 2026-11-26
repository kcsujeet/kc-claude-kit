#!/usr/bin/env bash
# shellcheck disable=SC2016  # the REPL code holds JavaScript backticks, not shell expansions
# Tests scripts/guard-unreproduced-cause.sh (PreToolUse on Edit, Write, MultiEdit, NotebookEdit): the
# first file change made for a reported problem is denied until something ran the product (or its
# tests, or a browser) or Claude wrote a Not reproduced: line with a reason; a test or spec file may
# always be written; other prompts go through. Never a Stop hook: that would run after the reply was
# read. Holds §AS1 (kc-assess).
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
guard="$(dirname "$tests_dir")/scripts/guard-unreproduced-cause.sh"
require_jq

transcript=$work_dir/transcript.jsonl
repo=$work_dir/repo
mkdir -p "$repo/.claude"

emit_typed_message() { jq -cn --arg text "$1" '{type: "user", message: {role: "user", content: [{type: "text", text: $text}]}}'; }
emit_text() { jq -cn --arg text "$1" '{type: "assistant", message: {role: "assistant", content: [{type: "text", text: $text}]}}'; }
emit_tool_call() {
  jq -cn --arg name "$1" --arg key "$2" --arg value "$3" \
    '{type: "assistant", message: {role: "assistant", content: [{type: "tool_use", id: "t", name: $name, input: {($key): $value}}]}}'
}
emit_tool_result() { jq -cn '{type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: "t", content: "ok"}]}}'; }

# Runs the guard for an edit of <path> (default src/export.rb); prints denied or allowed, and keeps its output in $work_dir/last-output.
run_edit() {
  local path=${1:-src/export.rb} output
  output=$(jq -cn --arg path "$transcript" --arg cwd "$repo" --arg file "$path" \
    '{session_id: "s", transcript_path: $path, cwd: $cwd, hook_event_name: "PreToolUse", tool_name: "Edit", tool_input: {file_path: $file}}' | bash "$guard")
  printf '%s' "$output" > "$work_dir/last-output"
  if printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then echo denied; else echo allowed; fi
}

report="the export is broken, please fix it"

# Reading and searching code never counts.
{ emit_typed_message "$report"; emit_tool_call Read file_path "src/export.rb"; emit_tool_result; emit_tool_call Bash command "grep -rn curl src && git log -3 -- src/export.rb | cat"; emit_tool_result; emit_tool_call Grep pattern "rspec"; emit_tool_result; } > "$transcript"
expect_eq "§AS1: an edit for a reported problem after code reading alone is denied" denied "$(run_edit)"
expect_contains "the denial asks for the reporter's own path" "their entry point, renderer or runtime and version, environment and real-shaped data" "$(cat "$work_dir/last-output")"
expect_contains "the denial names the way out" "Not reproduced: <why>" "$(cat "$work_dir/last-output")"
expect_contains "the denial says reading code does not count" "reading code does not count" "$(cat "$work_dir/last-output")"
expect_eq "the denial is a PreToolUse deny" PreToolUse "$(jq -r '.hookSpecificOutput.hookEventName' "$work_dir/last-output")"
{ emit_typed_message "$report"; emit_tool_call Read file_path "src/export.rb"; emit_tool_result; } > "$transcript"
expect_eq "an edit with no tool call but a read is denied" denied "$(run_edit)"
{ emit_typed_message "$report"; } > "$transcript"
expect_eq "an edit straight after the report is denied" denied "$(run_edit)"

# A run of the product or its tests counts.
for command in "bundle exec rspec spec/export_spec.rb" "npx vitest run src/export.test.ts" "curl -s localhost:3000/orders/1/export" \
  "cd app && RAILS_ENV=test bin/rails runner 'Export.new.call'" "pnpm test --filter export" "go test ./..." "python3 -m pytest" "bin/rspec spec/export_spec.rb" "bin/rails runner scripts/export.rb" "./node_modules/.bin/jest src/export.test.ts" "npm test" "pnpm run test:unit" "cargo test" "yarn test" "NODE_ENV=test npm test" "node scripts/export.js" "curl -s 'localhost:3000/orders?id=7&fmt=pdf'"; do
  { emit_typed_message "$report"; emit_tool_call Read file_path "src/export.rb"; emit_tool_result; emit_tool_call Bash command "$command"; emit_tool_result; } > "$transcript"
  expect_eq "an edit after '$command' is allowed" allowed "$(run_edit)"
done
{ emit_typed_message "$report"; emit_tool_call REPL code 'const r = await $`curl -s localhost:3000/orders/1/export`; r'; emit_tool_result; } > "$transcript"
expect_eq "a curl inside a REPL shell template is a run" allowed "$(run_edit)"
{ emit_typed_message "$report"; emit_tool_call REPL code 'const text = await file("src/export.rb").text(); text'; emit_tool_result; } > "$transcript"
expect_eq "a REPL that only reads a file is not a run" denied "$(run_edit)"
{ emit_typed_message "$report"; emit_tool_call mcp__playwright__browser_navigate url "http://localhost:3000/orders/1"; emit_tool_result; } > "$transcript"
expect_eq "a browser MCP tool call is a run" allowed "$(run_edit)"
{ emit_typed_message "$report"; emit_tool_call Bash command "cat spec/export_spec.rb | sed -n 1,20p"; emit_tool_result; } > "$transcript"
expect_eq "cat and sed over a spec are not a run" denied "$(run_edit)"

# Commands that only look like runs.
for command in "npm install" "cargo build" "yarn add jest" "go build ./..." "git log -S rspec"; do
  { emit_typed_message "$report"; emit_tool_call Bash command "$command"; emit_tool_result; } > "$transcript"
  expect_eq "an edit after '$command' is denied" denied "$(run_edit)"
done

# A run before the report does not count.
{ emit_typed_message "earlier work"; emit_tool_call Bash command "bundle exec rspec"; emit_tool_result; emit_typed_message "$report"; emit_tool_call Read file_path "src/export.rb"; emit_tool_result; } > "$transcript"
expect_eq "a run from before the fix-asking message does not count" denied "$(run_edit)"

# The honest way out: a Not reproduced line with a reason, written since the report.
{ emit_typed_message "$report"; emit_text $'Not reproduced: the report needs the live payment sandbox, which is not reachable here.'; emit_tool_call Edit file_path "src/export.rb"; emit_tool_result; } > "$transcript"
expect_eq "Not reproduced with a reason of three or more words allows the edit" allowed "$(run_edit)"
{ emit_typed_message "$report"; emit_text '**Not reproduced:** a typo needs no run.'; } > "$transcript"
expect_eq "a bold Not reproduced label allows the edit" allowed "$(run_edit)"
{ emit_typed_message "$report"; emit_text $'Not reproduced: no access'; } > "$transcript"
expect_eq "Not reproduced with a two-word reason is still denied" denied "$(run_edit)"
{ emit_typed_message "$report"; emit_text $'The cause is a missing null check. I reproduced nothing yet.'; } > "$transcript"
expect_eq "the word reproduced in prose is not the line" denied "$(run_edit)"
{ emit_text $'Not reproduced: an earlier task, nothing to run.'; emit_typed_message "$report"; } > "$transcript"
expect_eq "a Not reproduced line from before the report does not count" denied "$(run_edit)"

# Writing a test or spec is how a problem is reproduced.
{ emit_typed_message "$report"; emit_tool_call Read file_path "src/export.rb"; emit_tool_result; } > "$transcript"
for path in spec/export_spec.rb src/export.test.ts test/export_test.rb src/__tests__/export.ts tests/export.py; do
  expect_eq "writing $path is allowed" allowed "$(run_edit "$path")"
done
expect_eq "a source file whose name only contains test is denied" denied "$(run_edit src/contest.rb)"

# A repo's own run commands.
{ emit_typed_message "$report"; emit_tool_call Bash command "bin/shop-check orders"; emit_tool_result; } > "$transcript"
expect_eq "a repo command the built-ins do not know is not a run" denied "$(run_edit)"
printf '# the shop smoke check\n\n^shop-check( |$)\n' > "$repo/.claude/reproduce-commands"
expect_eq ".claude/reproduce-commands adds a run command" allowed "$(run_edit)"
{ emit_typed_message "$report"; emit_tool_call Bash command "cat bin/shop-check"; emit_tool_result; } > "$transcript"
expect_eq "a command that only reads that file is still not a run" denied "$(run_edit)"
rm -f "$repo/.claude/reproduce-commands"

# Prompts that did not report a problem go through.
{ emit_typed_message "what does the export do?"; emit_tool_call Read file_path "src/export.rb"; emit_tool_result; } > "$transcript"
expect_eq "no fix-asking prompt: an edit is allowed" allowed "$(run_edit)"
{ emit_typed_message "add an export button"; } > "$transcript"
expect_eq "a feature request: an edit is allowed" allowed "$(run_edit)"
{ emit_typed_message "$report"; emit_tool_call Bash command "bundle exec rspec"; emit_tool_result; emit_typed_message "ok, go on"; emit_tool_call Read file_path "src/export.rb"; emit_tool_result; } > "$transcript"
expect_eq "its run after the fix-asking prompt counts for a later message" allowed "$(run_edit)"

# What it cannot read it does not deny.
rm -f "$transcript"
expect_eq "no transcript: allowed" allowed "$(run_edit)"
expect_eq "empty input: nothing printed" "" "$(printf '' | bash "$guard")"

# It is a PreToolUse guard, never a Stop hook.
expect_eq "a Stop payload with a cause and a fix is never blocked" "" "$(jq -cn --arg reply "The cause is a null. The fix is a guard." '{hook_event_name: "Stop", last_assistant_message: $reply}' | bash "$guard")"

finish
