#!/usr/bin/env bash
# shellcheck disable=SC2016  # the replies hold Markdown backticks, not shell expansions
# Tests scripts/check-reply-sources.sh: a reply that says what instructions require, or hands the
# person an account CLI's command, is held back unless this turn read the instructions or ran that
# CLI (or read its config); anything else, a second try, or a turn that did check goes out.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
hook="$(dirname "$tests_dir")/scripts/check-reply-sources.sh"
transcript=$work_dir/transcript.jsonl

# Typed messages as transcripts hold them: an array of content blocks.
write_typed_message() { jq -cn --arg text "$1" '{type: "user", message: {role: "user", content: [{type: "text", text: $text}]}}'; }
write_tool_call() {
  jq -cn --arg name "$1" --arg key "$2" --arg value "$3" \
    '{type: "assistant", message: {role: "assistant", content: [{type: "tool_use", id: "t", name: $name, input: {($key): $value}}]}}'
}
write_tool_result() { jq -cn '{type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: "t", content: "ok"}]}}'; }
write_reminder() { jq -cn '{type: "user", message: {role: "user", content: "<system-reminder>a hook note</system-reminder>"}}'; }

# Runs the hook on <reply> against the transcript; prints "held" or "out", and keeps the output in
# $hook_output for expect_reason.
hook_output=$work_dir/hook-output
run_hook() {
  local reply=$1 active=${2:-false}
  jq -cn --arg reply "$reply" --arg path "$transcript" --argjson active "$active" \
    '{session_id: "s", transcript_path: $path, hook_event_name: "Stop", stop_hook_active: $active, last_assistant_message: $reply}' \
    | bash "$hook" > "$hook_output" || { echo "exit $?"; return; }
  # A reply let out gets no output at all; anything else is neither held nor out.
  if grep -q '"decision": *"block"' "$hook_output"; then echo held
  elif [ -s "$hook_output" ]; then echo "unexpected output"
  else echo out; fi
}
expect_reason() {
  if grep -Eq "$2" "$hook_output"; then record "$1" ok; else record "$1" fail "$(cat "$hook_output")"; fi
}

kit_claim='The kit doesn'"'"'t require a check behind each lesson, so lessons are only text.'
heroku_reply=$(printf 'Run this:\n\n```bash\nheroku config:set PRICE=15 --app shop\n```\n')

# Claims about instructions.
{ write_typed_message "will these hold?"; } > "$transcript"
expect_eq "a claim about the kit with nothing read is held" held "$(run_hook "$kit_claim")"
expect_reason "it says nothing was read" "nothing in this turn read them"

{ write_typed_message "will these hold?"; write_tool_call Read file_path "/home/me/kit/plugins/kc-conventions/rules/kc-working-agreement.md"; write_tool_result; } > "$transcript"
expect_eq "a claim about the kit after reading a rule file goes out" out "$(run_hook "$kit_claim")"

{ write_typed_message "will these hold?"; write_tool_call Bash command "git grep -n lesson origin/main -- CLAUDE.md"; write_tool_result; } > "$transcript"
expect_eq "a claim after a shell read of CLAUDE.md goes out" out "$(run_hook "$kit_claim")"

{ write_typed_message "earlier question"; write_tool_call Read file_path "/home/me/kit/plugins/kc-gates/skills/kc-code-review/SKILL.md"; write_tool_result; write_typed_message "will these hold?"; } > "$transcript"
expect_eq "a read in an earlier turn doesn't count" held "$(run_hook "$kit_claim")"

{ write_typed_message "will these hold?"; write_reminder; write_tool_call Grep path "/home/me/repo/.claude/review-conventions.md"; write_tool_result; } > "$transcript"
expect_eq "a hook note doesn't start a new turn, so the read before it counts" out "$(run_hook "$kit_claim")"

{ write_typed_message "what next?"; } > "$transcript"
expect_eq "a reply that says nothing about instructions goes out" out "$(run_hook "Next, the country pages still offer the trial.")"
expect_eq "naming the kit without a claim about it goes out" out "$(run_hook "The kit PR is merged.")"
expect_eq "a held reply's second try goes out" out "$(run_hook "$kit_claim" true)"

# Commands for account CLIs.
{ write_typed_message "set the config"; } > "$transcript"
expect_eq "a heroku command never checked is held" held "$(run_hook "$heroku_reply")"
expect_reason "it names the CLI" "a heroku command"

{ write_typed_message "set the config"; write_tool_call Bash command "heroku auth:whoami"; write_tool_result; } > "$transcript"
expect_eq "a heroku command after running heroku goes out" out "$(run_hook "$heroku_reply")"

{ write_typed_message "set the config"; write_tool_call Read file_path "/home/me/.config/heroku/config.json"; write_tool_result; } > "$transcript"
expect_eq "a heroku command after reading its config goes out" out "$(run_hook "$heroku_reply")"

{ write_typed_message "set the config"; write_tool_call Bash command "cat heroku-notes.txt | grep herokus"; write_tool_result; } > "$transcript"
expect_eq "a command that only names the CLI inside a word doesn't count" held "$(run_hook "$heroku_reply")"

deploy_reply=$(printf 'Deploy:\n\n```bash\nnpx vercel deploy --prod\n```\n')
{ write_typed_message "deploy it"; } > "$transcript"
expect_eq "a command run through bunx is still the CLI's" held "$(run_hook "$deploy_reply")"
{ write_typed_message "deploy it"; write_tool_call Bash command "npx vercel whoami"; write_tool_result; } > "$transcript"
expect_eq "after the CLI's own status check it goes out" out "$(run_hook "$deploy_reply")"

{ write_typed_message "build it"; } > "$transcript"
expect_eq "a command for a CLI that acts on no account goes out" out "$(run_hook "$(printf '```bash\nbun run build\n```\n')")"
expect_eq "a CLI named in prose, not handed over, goes out" out "$(run_hook 'Then sign in with `heroku login` when you have time.')"
expect_eq "a prose line that starts with a CLI's name goes out" out "$(run_hook "$(printf 'Done.\nheroku now holds both new values.\n')")"
expect_eq "a held command's second try goes out" out "$(run_hook "$heroku_reply" true)"

both_reply=$(printf '%s\n\n```bash\ngh pr merge 7\n```\n' "$kit_claim")
expect_eq "both kinds in one reply are held together" held "$(run_hook "$both_reply")"
expect_reason "it gives both reasons" "nothing in this turn read them.*a gh command"

# Commands anywhere in a fenced block, behind any fence, at the start of any command in a line.
{ write_typed_message "ship it"; } > "$transcript"
expect_eq "a CLI block after a block in another language is still read" held "$(run_hook "$(printf 'Config:\n\n```json\n{"a": 1}\n```\n\nThen:\n\n```bash\ngh pr merge 7\n```\n')")"
expect_eq "prose after a block in another language is not read as commands" out "$(run_hook "$(printf '```json\n{"a": 1}\n```\n\ngh is the code host CLI.\n')")"
expect_eq "a CLI after cd and && is found" held "$(run_hook "$(printf '```bash\ncd shop && gh pr merge 7\n```\n')")"
expect_eq "a CLI behind a variable assignment is found" held "$(run_hook "$(printf '```bash\nAPP=shop heroku config:set PRICE=15\n```\n')")"
expect_eq "a CLI behind a runner's flags is found" held "$(run_hook "$(printf '```bash\nnpx --yes vercel deploy --prod\n```\n')")"
expect_eq "a CLI in a tilde fence is found" held "$(run_hook "$(printf '~~~\ngh pr merge 7\n~~~\n')")"
{ write_typed_message "ship it"; write_tool_call Bash command "grep -rn gh src"; write_tool_result; } > "$transcript"
expect_eq "a shell command that only names the CLI as an argument doesn't count as running it" held "$(run_hook "$(printf '```bash\ngh pr merge 7\n```\n')")"
{ write_typed_message "ship it"; write_tool_call Bash command "cd shop && gh auth status"; write_tool_result; } > "$transcript"
expect_eq "the CLI run after cd and && counts" out "$(run_hook "$(printf '```bash\ngh pr merge 7\n```\n')")"

# A claim wrapped across two lines is one claim.
{ write_typed_message "will these hold?"; } > "$transcript"
expect_eq "a claim split across lines is held" held "$(run_hook "$(printf 'The kit\ndoesn'"'"'t require a check for each lesson.')")"

# Machine messages in the transcript don't start a new turn; a typed one does, in either shape.
for note in '{isMeta: true, message: {content: [{type: "text", text: "a note"}]}}' \
  '{message: {content: "Caveat: the messages below were generated by the user while running local commands."}}' \
  '{message: {content: [{type: "text", text: "<task-notification>done</task-notification>"}]}}' \
  '{isCompactSummary: true, message: {content: "the summary"}}'; do
  { write_typed_message "will these hold?"; write_tool_call Read file_path "/home/me/kit/plugins/kc-gates/agents/naming-gate.md"; write_tool_result; jq -cn "{type: \"user\"} + $note"; } > "$transcript"
  expect_eq "a read before a machine message still counts: $(printf '%s' "$note" | cut -c1-40)" out "$(run_hook "$kit_claim")"
done
{ write_typed_message "earlier"; write_tool_call Read file_path "/home/me/kit/plugins/kc-gates/agents/naming-gate.md"; write_tool_result; jq -cn '{type: "user", message: {role: "user", content: "will these hold?"}}'; } > "$transcript"
expect_eq "a typed message with string content starts a new turn" held "$(run_hook "$kit_claim")"

# A skill's preamble is not the person typing, so it doesn't start a new turn.
{ write_typed_message "will these hold?"; write_tool_call Read file_path "/home/me/kit/plugins/kc-conventions/rules/kc-testing.md"; write_tool_result; jq -cn '{type: "user", message: {role: "user", content: [{type: "text", text: "Base directory for this skill: /home/me/skill"}]}}'; } > "$transcript"
expect_eq "a skill preamble after a read doesn't hide the read" out "$(run_hook "$kit_claim")"
{ write_typed_message "will these hold?"; write_tool_call Read file_path "/home/me/kit/plugins/kc-conventions/rules/kc-testing.md"; write_tool_result; jq -cn '{type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: "t", content: "ok"}, {type: "text", text: "ok"}]}}'; } > "$transcript"
expect_eq "a tool result with text beside it doesn't start a new turn" out "$(run_hook "$kit_claim")"

# It never blocks on what it can't read.
expect_eq "a missing transcript lets the reply out" out "$(jq -cn --arg reply "$heroku_reply" '{transcript_path: "/nonexistent", stop_hook_active: false, last_assistant_message: $reply}' | bash "$hook" | grep -q block && echo held || echo out)"

finish
