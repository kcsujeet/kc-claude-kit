#!/usr/bin/env bash
# shellcheck disable=SC2016  # the REPL code holds JavaScript backticks, not shell expansions
# Tests scripts/guard-better-line.sh: a turn that presented work (an edit, a write, an agent, or a
# command that is not plainly read-only) is blocked unless its reply has a Better: line with a number
# or a named alternative tried; a turn of reads passes. Holds step 5 of kc-raise-the-bar.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
guard="$(dirname "$tests_dir")/scripts/guard-better-line.sh"
require_jq

transcript=$work_dir/transcript.jsonl
repo=$work_dir/repo
mkdir -p "$repo"

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

done_text="The order total is fixed."
reply_with_numeric_better_line=$'The order total is fixed.\nBetter: order export check 44s -> 6s by a 10-case test of the totals.'
reply_with_tried_better_line=$'The order total is fixed.\nBetter: none, tried a cached total, 3 runs, no faster.'

# Turns of reads, or with no tool calls, pass.
{ emit_typed_message "how do orders work?"; emit_tool_call Read file_path "src/orders.rb"; emit_tool_result; emit_tool_call Bash command "grep -rn total src | head -5 && git log -3 --oneline"; emit_tool_result; emit_tool_call Grep pattern "total"; emit_tool_result; } > "$transcript"
expect_eq "a turn of reads with no Better line goes out" out "$(run_stop "$done_text")"
{ emit_typed_message "how do orders work?"; emit_tool_call REPL code 'const t = await $`git status --short`.text(); t'; emit_tool_result; } > "$transcript"
expect_eq "a REPL that only runs a read-only command goes out" out "$(run_stop "$done_text")"
{ emit_typed_message "hello"; } > "$transcript"
expect_eq "a turn with no tool call goes out" out "$(run_stop "$done_text")"

# A turn that did work needs the line.
{ emit_typed_message "fix the total"; emit_tool_call Edit file_path "src/orders.rb"; emit_tool_result; } > "$transcript"
expect_eq "work with no Better line is held" held "$(run_stop "$done_text")"
expect_contains "the block tells Claude to measure what it did" "measure what you just did" "$(cat "$work_dir/last-output")"
expect_contains "the block points to the raise-the-bar skill" "kc-conventions:kc-raise-the-bar" "$(cat "$work_dir/last-output")"
expect_eq "an empty reply goes out" out "$(run_stop "")"
{ emit_typed_message "fix the total"; emit_tool_call REPL code 'const t = await $`bundle exec rspec`.text(); t'; emit_tool_result; } > "$transcript"
expect_eq "a REPL that runs a non-read command is work, held" held "$(run_stop "$done_text")"
{ emit_typed_message "fix the total"; emit_tool_call Edit file_path "src/orders.rb"; emit_tool_result; } > "$transcript"
expect_contains "the block names both line forms" "Better: none, tried" "$(cat "$work_dir/last-output")"
expect_eq "a bare Better: none is held" held "$(run_stop $'Done.\nBetter: none')"
expect_eq "Better: looks fine is held" held "$(run_stop $'Done.\nBetter: looks fine')"
expect_eq "a numeric improvement goes out" out "$(run_stop "$reply_with_numeric_better_line")"
expect_eq "none with a number and what was tried goes out" out "$(run_stop "$reply_with_tried_better_line")"
expect_eq "none with a named alternative tried goes out" out "$(run_stop $'Done.\nBetter: none, tried a batch query instead of a loop.')"
expect_eq "a bold Better label with a number goes out" out "$(run_stop $'Done.\n**Better:** 12 steps -> 4 by one script.')"
expect_eq "the word better in prose is not the line" held "$(run_stop "A better way took 5 runs to find.")"
expect_eq "work held on the first try goes out on the second (stop_hook_active)" out "$(run_stop "$done_text" true)"

expect_eq "an arrow with no number is held" held "$(run_stop $'Done.\nBetter: slow loop -> one query.')"

# Each kind of work counts.
for call in "Write file_path src/orders.rb" "NotebookEdit file_path orders.ipynb" "Agent prompt check-the-orders" "Bash command bundle-exec-rspec" "Bash command git-commit-m-done" "Bash command echo-x->orders.txt" "REPL code await-edit('a.rb','a','b')" "REPL code await-Bash({command:'rm-x'})" "REPL code await-tools.mcp__shop__save_order({})" "Bash command find-.--delete" "Bash command git-branch--D-x" "Bash command ls-\$(rm-x)"; do
  # shellcheck disable=SC2086 # the call is three words
  set -- $call
  { emit_typed_message "fix the total"; emit_tool_call "$1" "$2" "${3//-/ }"; emit_tool_result; } > "$transcript"
  expect_eq "$1 '${3//-/ }' with no Better line is held" held "$(run_stop "$done_text")"
done
{ emit_typed_message "fix the total"; emit_tool_call Bash command "ls src 2>/dev/null | wc -l"; emit_tool_result; } > "$transcript"
expect_eq "a read-only command with a /dev/null redirect goes out" out "$(run_stop "$done_text")"

{ emit_typed_message "fix the total"; emit_tool_call Bash command "sed -i 's/a/b/' src/orders.rb"; emit_tool_result; } > "$transcript"
expect_eq "sed -i is work, held" held "$(run_stop "$done_text")"

# Only this turn counts.
{ emit_typed_message "fix the total"; emit_tool_call Edit file_path "src/orders.rb"; emit_tool_result; emit_typed_message "what did you change?"; emit_tool_call Read file_path "src/orders.rb"; emit_tool_result; } > "$transcript"
expect_eq "an edit from an earlier turn does not count" out "$(run_stop "$done_text")"

# What it cannot read it does not block.
rm -f "$transcript"
expect_eq "no transcript: out" out "$(run_stop "$done_text")"

finish
