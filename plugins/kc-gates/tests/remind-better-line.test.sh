#!/usr/bin/env bash
# shellcheck disable=SC2016  # the REPL code holds JavaScript backticks, not shell expansions
# Tests scripts/remind-better-line.sh (and the marker reset in remind-reply-rules.sh): on the first
# work call of a turn (an edit, a write, an agent, or a command that is not plainly read-only) Claude
# gets one additionalContext line to raise the bar; reads never do; a second work call in the same
# turn gets nothing; the next prompt clears the marker. It runs in PostToolUse, before the reply,
# and never in a Stop hook (the person would only see it after the reply). Holds step 5 of
# kc-raise-the-bar.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
hook="$(dirname "$tests_dir")/scripts/remind-better-line.sh"
prompt_hook="$(dirname "$tests_dir")/scripts/remind-reply-rules.sh"
require_jq

data_dir=$work_dir/data
mkdir -p "$data_dir"

# Runs the hook for session <id> on one tool call (name, then the input key and value); prints its output.
run_call() {
  jq -cn --arg id "$1" --arg name "$2" --arg key "$3" --arg value "$4" \
    '{session_id: $id, hook_event_name: "PostToolUse", tool_name: $name, tool_input: {($key): $value}}' \
    | CLAUDE_PLUGIN_DATA="$data_dir" bash "$hook"
}
# Prints reminded or silent for a call in a fresh session.
fresh_call() {
  local id out
  id=$(mktemp -u s.XXXXXX)
  out=$(run_call "$id" "$@")
  if printf '%s' "$out" | grep -q 'raise-the-bar'; then echo reminded; else echo silent; fi
}
expect_work() { expect_eq "$1 is work, reminded" reminded "$(fresh_call "$2" "$3" "$4")"; }

# Reads and plain read-only commands never remind.
expect_eq "a Read is silent" silent "$(fresh_call Read file_path src/orders.rb)"
expect_eq "a Grep is silent" silent "$(fresh_call Grep pattern total)"
expect_eq "a read-only command is silent" silent "$(fresh_call Bash command "grep -rn total src | head -5 && git log -3 --oneline")"
expect_eq "a REPL that only runs a read-only command is silent" silent "$(fresh_call REPL code 'const t = await $`git status --short`.text(); t')"
expect_eq "a read-only command with a /dev/null redirect is silent" silent "$(fresh_call Bash command "ls src 2>/dev/null | wc -l")"

# Each kind of work reminds.
expect_work "an Edit" Edit file_path src/orders.rb
expect_work "a Write" Write file_path src/orders.rb
expect_work "a NotebookEdit" NotebookEdit file_path orders.ipynb
expect_work "an Agent" Agent prompt "check the orders"
expect_work "a test run" Bash command "bundle exec rspec"
expect_work "a commit" Bash command "git commit -m done"
expect_work "a redirect to a file" Bash command "echo x > orders.txt"
expect_work "find -delete" Bash command "find . -delete"
expect_work "a nested command" Bash command 'ls $(rm x)'
expect_work "git diff --output" Bash command "git diff --output=out.txt"
expect_work "a redirect after an escaped single quote" Bash command "echo \\' > f; echo 'x'"
expect_work "a redirect after a quoted string" Bash command "echo 'a' > out.txt"
expect_work "a nested command inside double quotes" Bash command 'ls "$(rm x)"'
expect_work "a redirect after a quote inside a double-quoted string" Bash command "echo \"\$x'\" > f; echo 'y'"
expect_work "a redirect after an escaped double quote" Bash command 'echo \" > f; echo "x"'
expect_work "a redirect after a double-quoted string" Bash command 'echo "a" > out.txt'
expect_work "awk running a command" Bash command "awk 'BEGIN{system(\"rm x\")}'"
expect_work "a REPL \$(\"...\", ms) shell string" REPL code 'await $("rm -rf x", 5000)'
expect_eq "a double-quoted variable is data, not work" silent "$(fresh_call Bash command 'echo "$HOME"')"
expect_work "a background job" Bash command "ls & rm x"
expect_work "sed -i" Bash command "sed -i 's/a/b/' src/orders.rb"
expect_work "a REPL edit()" REPL code "await edit('a.rb', 'a', 'b')"
expect_work "a REPL bare-global Bash()" REPL code "await Bash({command: 'rm x'})"
expect_work "a REPL \$(\"...\") shell string" REPL code 'await $("rm -rf x")'
expect_eq "a quoted | or ; or > is data, not work" silent "$(for command in "rg 'foo|bar' src" "jq '.a | .b' f.json" "rg '=>' src" 'grep "a;b" f'; do fresh_call Bash command "$command"; done | sort -u)"

# The output is additionalContext for PostToolUse, short, and keeps it out of the reply.
out=$(run_call out1 Edit file_path src/orders.rb)
expect_eq "the output is PostToolUse additionalContext" PostToolUse "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')"
context=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')
expect_contains "it points to the raise-the-bar skill" "kc-conventions:kc-raise-the-bar" "$context"
expect_contains "it keeps the check out of the reply" "out of the reply" "$context"
expect_eq "it is under 40 words ($(printf '%s' "$context" | wc -w | tr -d ' '))" ok "$([ "$(printf '%s' "$context" | wc -w)" -lt 40 ] && echo ok || echo long)"
expect_eq "it blocks nothing" "" "$(printf '%s' "$out" | jq -r '.decision // empty')"

# Once per turn, until the next prompt clears the marker.
expect_eq "a second work call in the same turn is silent" "" "$(run_call out1 Bash command "rm x")"
printf '%s' '{"session_id":"out1","prompt":"next task"}' | CLAUDE_PLUGIN_DATA="$data_dir" bash "$prompt_hook" > /dev/null
expect_contains "after the next prompt the first work call reminds again" "raise-the-bar" "$(run_call out1 Edit file_path src/orders.rb)"
expect_eq "another session is not held by the first one's marker" reminded "$(fresh_call Edit file_path src/orders.rb)"
run_call out2 Read file_path src/orders.rb > /dev/null
expect_contains "a read does not use up the turn's reminder" "raise-the-bar" "$(run_call out2 Edit file_path src/orders.rb)"

# What it cannot read it does not remind.
expect_eq "no plugin data folder: nothing printed" "" "$(jq -cn '{session_id: "s", tool_name: "Edit", tool_input: {file_path: "a"}}' | env -u CLAUDE_PLUGIN_DATA bash "$hook")"
expect_eq "no session id: nothing printed" "" "$(jq -cn '{tool_name: "Edit", tool_input: {file_path: "a"}}' | CLAUDE_PLUGIN_DATA="$data_dir" bash "$hook")"
expect_eq "a data folder that cannot be written: nothing printed, not a reminder on every call" "" "$(jq -cn '{session_id: "s", tool_name: "Edit", tool_input: {file_path: "a"}}' | CLAUDE_PLUGIN_DATA=/dev/null/none bash "$hook")"
expect_eq "empty input: nothing printed" "" "$(printf '' | CLAUDE_PLUGIN_DATA="$data_dir" bash "$hook")"

finish
