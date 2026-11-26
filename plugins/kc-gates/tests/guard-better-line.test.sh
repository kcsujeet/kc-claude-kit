#!/usr/bin/env bash
# shellcheck disable=SC2016  # the REPL code holds JavaScript backticks, not shell expansions
# Tests scripts/guard-better-line.sh: a turn that did work (an edit, a write, an agent, or a command
# that is not plainly read-only) is blocked unless the session's better-lines file holds a record for
# the turn: a thing improved with a before and an after, or "none" with what was checked. The reply
# is never read. Holds step 5 of kc-raise-the-bar.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
guard_script="$(dirname "$tests_dir")/scripts/guard-better-line.sh"
require_jq

transcript=$work_dir/transcript.jsonl
repo=$work_dir/repo
data_dir=$work_dir/data
better_lines_file=$data_dir/better-lines/s
mkdir -p "$repo" "$data_dir/better-lines"

readonly TURN_START=2026-01-01T10:00:00.000Z
emit_typed_message() { jq -cn --arg text "$1" --arg at "${2:-$TURN_START}" '{type: "user", timestamp: $at, message: {role: "user", content: [{type: "text", text: $text}]}}'; }
emit_tool_call() {
  jq -cn --arg name "$1" --arg key "$2" --arg value "$3" \
    '{type: "assistant", message: {role: "assistant", content: [{type: "tool_use", id: "t", name: $name, input: {($key): $value}}]}}'
}
emit_tool_result() { jq -cn '{type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: "t", content: "ok"}]}}'; }

# Runs the guard on <reply>; prints held or out, and keeps its output in $work_dir/last-output.
run_stop() {
  local is_stop_hook_active=${2:-false} guard_output
  guard_output=$(jq -cn --arg reply "$1" --arg path "$transcript" --arg cwd "$repo" --argjson active "$is_stop_hook_active" \
    '{session_id: "s", transcript_path: $path, cwd: $cwd, hook_event_name: "Stop", stop_hook_active: $active, last_assistant_message: $reply}' \
    | CLAUDE_PLUGIN_DATA="$data_dir" bash "$guard_script")
  printf '%s' "$guard_output" > "$work_dir/last-output"
  if printf '%s' "$guard_output" | grep -q '"decision":"block"'; then echo held; else echo out; fi
}

# Writes a transcript of one turn: a fix request and one tool call.
write_work_turn() { { emit_typed_message "fix the total"; emit_tool_call "$1" "$2" "$3"; emit_tool_result; } > "$transcript"; }
expect_work_held() { write_work_turn "$2" "$3" "$4"; expect_eq "$1 is work, held" held "$(run_stop "$done_text")"; }
# Writes the session's better-lines file: one line, tab-separated fields.
write_record() { printf '%s\n' "$1" > "$better_lines_file"; }
expect_record() { write_record "$2"; write_work_turn Edit file_path "src/orders.rb"; expect_eq "$1" "$3" "$(run_stop "$done_text")"; }

done_text="The order total is fixed."
no_record() { rm -f "$better_lines_file"; }

# Turns of reads, or with no tool calls, pass.
no_record
{ emit_typed_message "how do orders work?"; emit_tool_call Read file_path "src/orders.rb"; emit_tool_result; emit_tool_call Bash command "grep -rn total src | head -5 && git log -3 --oneline"; emit_tool_result; emit_tool_call Grep pattern "total"; emit_tool_result; } > "$transcript"
expect_eq "a turn of reads with no record goes out" out "$(run_stop "$done_text")"
{ emit_typed_message "how do orders work?"; emit_tool_call REPL code 'const t = await $`git status --short`.text(); t'; emit_tool_result; } > "$transcript"
expect_eq "a REPL that only runs a read-only command goes out" out "$(run_stop "$done_text")"
{ emit_typed_message "hello"; } > "$transcript"
expect_eq "a turn with no tool call goes out" out "$(run_stop "$done_text")"

# A turn that did work needs a record in the file.
write_work_turn Edit file_path "src/orders.rb"
expect_eq "work with no record is held" held "$(run_stop "$done_text")"
expect_contains "the block names the file to write" "$better_lines_file" "$(cat "$work_dir/last-output")"
expect_contains "the block gives the improved shape" "<thing improved> TAB <before> TAB <after>" "$(cat "$work_dir/last-output")"
expect_contains "the block gives the none shape" "TAB none TAB <what you checked or measured>" "$(cat "$work_dir/last-output")"
expect_contains "the block points to the raise-the-bar skill" "kc-conventions:kc-raise-the-bar" "$(cat "$work_dir/last-output")"
expect_contains "the block keeps it out of the reply" "out of the reply" "$(cat "$work_dir/last-output")"
block_words=$(jq -r '.reason' "$work_dir/last-output" | wc -w | tr -d ' ')
expect_eq "the block message is under 60 words (${block_words})" ok "$([ "$block_words" -lt 60 ] && echo ok || echo long)"
expect_eq "an empty reply with no record is held too" held "$(run_stop "")"
expect_eq "a reply with a Better: line but no record is still held" held "$(run_stop $'Done.\nBetter: order export 44s -> 6s')"
expect_eq "work held on the first try goes out on the second (stop_hook_active)" out "$(run_stop "$done_text" true)"

# The record, by case.
t0=2026-01-01T10:05:00Z
expect_record "an improvement with a before and an after passes" "$t0"$'\torder export\t44 s\t6 s' out
expect_record "an improvement passes without a word in the reply" "$t0"$'\tcheck run time\t9 min\t2 min' out
expect_eq "a reply with no Better line passes when the file has the line" out "$(run_stop "Done.")"
expect_record "none with what was checked passes" "$t0"$'\tnone\tmeasured 3 runs, no faster alternative' out
expect_record "none with nothing checked is held" "$t0"$'\tnone\t' held
expect_record "none with one word is held" "$t0"$'\tnone\tfine' held
expect_record "an action as the thing improved is held" "$t0"$'\tfixed the total\t44 s\t6 s' held
expect_record "posted as the thing improved is held" "$t0"$'\tposted the reply\tdraft\tposted' held
expect_record "merged as the thing improved is held" "$t0"$'\tMerged the PR\topen\tmerged' held
expect_record "an improvement with no before is held" "$t0"$'\torder export\t\t6 s' held
expect_record "an improvement with the same before and after is held" "$t0"$'\torder export\t6 s\t6 s' held
expect_record "a line with one field is held" "$t0"$'\torder export' held
expect_record "a line from before this turn is held" "2026-01-01T09:00:00Z"$'\torder export\t44 s\t6 s' held

# Each kind of work counts.
no_record
expect_work_held "a Write" Write file_path "src/orders.rb"
expect_work_held "a NotebookEdit" NotebookEdit file_path "orders.ipynb"
expect_work_held "an Agent" Agent prompt "check the orders"
expect_work_held "a test run" Bash command "bundle exec rspec"
expect_work_held "a commit" Bash command "git commit -m done"
expect_work_held "a redirect to a file" Bash command "echo x > orders.txt"
expect_work_held "find -delete" Bash command "find . -delete"
expect_work_held "a nested command" Bash command 'ls $(rm x)'
expect_work_held "git diff --output" Bash command "git diff --output=out.txt"
expect_work_held "sed -i" Bash command "sed -i 's/a/b/' src/orders.rb"
expect_work_held "awk running a command" Bash command "awk 'BEGIN{system(\"rm x\")}'"
expect_work_held "a REPL edit()" REPL code "await edit('a.rb', 'a', 'b')"
expect_work_held "a REPL bare-global Bash()" REPL code "await Bash({command: 'rm x'})"
expect_work_held "a REPL \$(\"...\") shell string" REPL code 'await $("rm -rf x")'
expect_work_held "a REPL \$(\"...\", ms) shell string" REPL code 'await $("rm -rf x", 5000)'
{ emit_typed_message "fix the total"; emit_tool_call Bash command "ls src 2>/dev/null | wc -l"; emit_tool_result; } > "$transcript"
expect_eq "a read-only command with a /dev/null redirect goes out" out "$(run_stop "$done_text")"

# Only this turn counts.
{ emit_typed_message "fix the total" 2026-01-01T09:00:00.000Z; emit_tool_call Edit file_path "src/orders.rb"; emit_tool_result; emit_typed_message "what did you change?"; emit_tool_call Read file_path "src/orders.rb"; emit_tool_result; } > "$transcript"
expect_eq "an edit from an earlier turn does not count" out "$(run_stop "$done_text")"

# What it cannot read it does not block.
write_work_turn Edit file_path "src/orders.rb"
expect_eq "no plugin data folder: nothing printed" "" "$(jq -cn --arg path "$transcript" '{session_id: "s", transcript_path: $path, stop_hook_active: false}' | env -u CLAUDE_PLUGIN_DATA bash "$guard_script")"
expect_eq "no session id: nothing printed" "" "$(jq -cn --arg path "$transcript" '{transcript_path: $path, stop_hook_active: false}' | CLAUDE_PLUGIN_DATA="$data_dir" bash "$guard_script")"
rm -f "$transcript"
expect_eq "no transcript: out" out "$(run_stop "$done_text")"

finish
