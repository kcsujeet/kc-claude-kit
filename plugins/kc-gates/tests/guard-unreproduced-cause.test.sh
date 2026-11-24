#!/usr/bin/env bash
# shellcheck disable=SC2016  # the replies hold Markdown backticks, not shell expansions
# Tests scripts/guard-unreproduced-cause.sh: a reply that proposes a cause and a fix for a reported
# problem is blocked unless it names a reproduction (a Reproduced: line backed by a run of the product
# or its tests, or a Not reproduced: line with a reason); other prompts and replies go out. Holds
# §AS1 (kc-assess).
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
emit_tool_call() {
  jq -cn --arg name "$1" --arg key "$2" --arg value "$3" \
    '{type: "assistant", message: {role: "assistant", content: [{type: "tool_use", id: "t", name: $name, input: {($key): $value}}]}}'
}
emit_tool_result() { jq -cn '{type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: "t", content: "ok"}]}}'; }

# Runs the guard on <reply>; prints held or out, and keeps its output in $work_dir/last-output.
run_stop() {
  local active=${2:-false} output
  output=$(jq -cn --arg reply "$1" --arg path "$transcript" --arg cwd "$repo" --argjson active "$active" \
    '{session_id: "s", transcript_path: $path, cwd: $cwd, hook_event_name: "Stop", stop_hook_active: $active, last_assistant_message: $reply}' | bash "$guard")
  printf '%s' "$output" > "$work_dir/last-output"
  if printf '%s' "$output" | grep -q '"decision":"block"'; then echo held; else echo out; fi
}

report="the export is broken, please fix it"
proposal=$'The cause is a missing null check in the exporter. The fix is to guard the total.'
reproduced=$'Reproduced: the export of order ABC-1 returned 500 in the browser.\n'"$proposal"
not_reproduced=$'Not reproduced: the report needs the live payment sandbox, which is not reachable here.\n'"$proposal"

# Reading and searching code never counts.
{ emit_typed_message "$report"; emit_tool_call Read file_path "src/export.rb"; emit_tool_result; emit_tool_call Bash command "grep -rn curl src && git log -3 -- src/export.rb | cat"; emit_tool_result; emit_tool_call Grep pattern "rspec"; emit_tool_result; } > "$transcript"
expect_eq "§AS1: a proposal from code reading alone with no Reproduced line is held" held "$(run_stop "$proposal")"
expect_contains "the block asks for the reporter's own path" "their entry point, renderer or runtime and version, environment and real-shaped data" "$(cat "$work_dir/last-output")"
expect_contains "the block names the two ways out" "Not reproduced: <why>" "$(cat "$work_dir/last-output")"
expect_eq "§AS1: a Reproduced line with only code reading behind it is held" held "$(run_stop "$reproduced")"
expect_contains "the block says reading code does not count" "reading code does not count" "$(cat "$work_dir/last-output")"

# A run of the product or its tests counts.
for command in "bundle exec rspec spec/export_spec.rb" "npx vitest run src/export.test.ts" "curl -s localhost:3000/orders/1/export" \
  "cd app && RAILS_ENV=test bin/rails runner 'Export.new.call'" "pnpm test --filter export" "go test ./..." "python3 -m pytest" "bin/rspec spec/export_spec.rb" "bin/rails runner scripts/export.rb" "./node_modules/.bin/jest src/export.test.ts" "npm test" "pnpm run test:unit" "cargo test" "yarn test" "NODE_ENV=test npm test" "node scripts/export.js" "curl -s 'localhost:3000/orders?id=7&fmt=pdf'"; do
  { emit_typed_message "$report"; emit_tool_call Read file_path "src/export.rb"; emit_tool_result; emit_tool_call Bash command "$command"; emit_tool_result; } > "$transcript"
  expect_eq "a Reproduced line after '$command' goes out" out "$(run_stop "$reproduced")"
done
{ emit_typed_message "$report"; emit_tool_call REPL code 'const r = await $`curl -s localhost:3000/orders/1/export`; r'; emit_tool_result; } > "$transcript"
expect_eq "a curl inside a REPL shell template is a run" out "$(run_stop "$reproduced")"
{ emit_typed_message "$report"; emit_tool_call REPL code 'const text = await file("src/export.rb").text(); text'; emit_tool_result; } > "$transcript"
expect_eq "a REPL that only reads a file is not a run" held "$(run_stop "$reproduced")"
{ emit_typed_message "$report"; emit_tool_call mcp__playwright__browser_navigate url "http://localhost:3000/orders/1"; emit_tool_result; } > "$transcript"
expect_eq "a browser MCP tool call is a run" out "$(run_stop "$reproduced")"
{ emit_typed_message "$report"; emit_tool_call Bash command "cat spec/export_spec.rb | sed -n 1,20p"; emit_tool_result; } > "$transcript"
expect_eq "cat and sed over a spec are not a run" held "$(run_stop "$reproduced")"

# Commands that only look like runs.
for command in "npm install" "cargo build" "yarn add jest" "go build ./..." "git log -S rspec"; do
  { emit_typed_message "$report"; emit_tool_call Bash command "$command"; emit_tool_result; } > "$transcript"
  expect_eq "a Reproduced line after '$command' is held" held "$(run_stop "$reproduced")"
done
{ emit_typed_message "$report"; emit_tool_call Read file_path "src/export.rb"; emit_tool_result; } > "$transcript"
expect_eq "a Reproduced line beside a two-word Not reproduced and no run is held" held "$(run_stop $'Reproduced: the 500 on order ABC-1.\nNot reproduced: no access\n'"$proposal")"

{ emit_typed_message "$report"; emit_tool_call Bash command "bundle exec rspec"; emit_tool_result; } > "$transcript"
expect_eq "a run in the transcript with a two-word Not reproduced is held" held "$(run_stop $'Not reproduced: no access\n'"$proposal")"
expect_contains "the block says the Not reproduced line gives no reason" "gives no reason" "$(cat "$work_dir/last-output")"

# A turn that edited: no label needed, a run is.
fix_built="Fixed: the cause was a missing null check and the fix guards the total."
{ emit_typed_message "$report"; emit_tool_call Edit file_path "src/export.rb"; emit_tool_result; emit_tool_call Bash command "bundle exec rspec spec/export_spec.rb"; emit_tool_result; } > "$transcript"
expect_eq "a fix made, with a run and no label, goes out" out "$(run_stop "$fix_built")"
{ emit_typed_message "$report"; emit_tool_call Read file_path "src/export.rb"; emit_tool_result; emit_tool_call Write file_path "src/export.rb"; emit_tool_result; } > "$transcript"
expect_eq "a fix made with no run is held" held "$(run_stop "$fix_built")"
expect_contains "the block says a fix was built without reproducing the problem" "a fix was built without reproducing the problem" "$(cat "$work_dir/last-output")"
expect_eq "a fix made with no run goes out on the second try" out "$(run_stop "$fix_built" true)"

# A run before the report does not count.
{ emit_typed_message "earlier work"; emit_tool_call Bash command "bundle exec rspec"; emit_tool_result; emit_typed_message "$report"; emit_tool_call Read file_path "src/export.rb"; emit_tool_result; } > "$transcript"
expect_eq "a run from before the fix-asking message does not count" held "$(run_stop "$reproduced")"

# The honest way out.
{ emit_typed_message "$report"; emit_tool_call Read file_path "src/export.rb"; emit_tool_result; } > "$transcript"
expect_eq "Not reproduced with a reason of three or more words goes out" out "$(run_stop "$not_reproduced")"
expect_eq "Not reproduced with a two-word reason is held" held "$(run_stop $'Not reproduced: no access\n'"$proposal")"
expect_contains "the block asks for the reason" "at least three words" "$(cat "$work_dir/last-output")"

# A repo's own run commands.
{ emit_typed_message "$report"; emit_tool_call Bash command "bin/shop-check orders"; emit_tool_result; } > "$transcript"
expect_eq "a repo command the built-ins do not know is not a run" held "$(run_stop "$reproduced")"
printf '# the shop smoke check\n\n^shop-check( |$)\n' > "$repo/.claude/reproduce-commands"
expect_eq ".claude/reproduce-commands adds a run command" out "$(run_stop "$reproduced")"
{ emit_typed_message "$report"; emit_tool_call Bash command "cat bin/shop-check"; emit_tool_result; } > "$transcript"
expect_eq "a command that only reads that file is still not a run" held "$(run_stop "$reproduced")"
rm -f "$repo/.claude/reproduce-commands"

# Which prompts and replies it leaves alone.
{ emit_typed_message "what does the export do?"; emit_tool_call Read file_path "src/export.rb"; emit_tool_result; } > "$transcript"
expect_eq "no fix-asking prompt: a cause and a fix go out" out "$(run_stop "$proposal")"
{ emit_typed_message "$report"; } > "$transcript"
expect_eq "a reply with no cause and fix goes out" out "$(run_stop "The exporter reads the total from the order.")"
{ emit_typed_message "$report"; emit_tool_call Bash command "bundle exec rspec"; emit_tool_result; emit_typed_message "ok, go on"; emit_tool_call Read file_path "src/export.rb"; emit_tool_result; } > "$transcript"
expect_eq "an earlier fix-asking prompt still counts: a proposal with no line is held" held "$(run_stop "$proposal")"
expect_eq "its run after the fix-asking prompt counts for a later message" out "$(run_stop "$reproduced")"

# Second try.
{ emit_typed_message "$report"; emit_tool_call Read file_path "src/export.rb"; emit_tool_result; } > "$transcript"
expect_eq "second try, still no line: held again" held "$(run_stop "$proposal" true)"
expect_eq "second try with a Reproduced line and no run goes out" out "$(run_stop "$reproduced" true)"
expect_eq "second try with a Not reproduced line goes out" out "$(run_stop "$not_reproduced" true)"

# What it cannot read it does not block.
rm -f "$transcript"
expect_eq "no transcript: out" out "$(run_stop "$proposal")"
expect_eq "an empty reply: nothing printed" "" "$(jq -cn --arg path "$transcript" '{transcript_path: $path, stop_hook_active: false}' | bash "$guard")"

finish
