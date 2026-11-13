#!/usr/bin/env bash
# shellcheck disable=SC2016  # the replies hold Markdown backticks, not shell expansions
# Tests scripts/check-reply-sources.sh: a reply that says what instructions require, or hands the
# person an account CLI's command, is noted for the next turn unless this turn read the instructions or ran that
# CLI (or read its config); anything else, or a turn that did check goes out.
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
# A hook's additionalContext as transcripts hold it: an attachment entry.
write_hook_note() { jq -cn --arg text "$1" '{attachment: {type: "hook_additional_context", content: [$text], hookName: "PostToolUse:Bash"}}'; }

# Runs the hook on <reply> against the transcript; prints "noted" or "out", and keeps the output in
# $hook_output for expect_reason.
export CLAUDE_PLUGIN_DATA=$work_dir/data
misses_file=$CLAUDE_PLUGIN_DATA/reply-misses/s
hook_output=$work_dir/hook-output
run_hook() {
  local reply=$1
  rm -f "$misses_file"
  jq -cn --arg reply "$reply" --arg path "$transcript" \
    '{session_id: "s", transcript_path: $path, hook_event_name: "Stop", stop_hook_active: false, last_assistant_message: $reply}' \
    | bash "$hook" > "$hook_output" || { echo "exit $?"; return; }
  # The hook never prints (it never blocks); it only writes misses for the next turn.
  if [ -s "$hook_output" ]; then echo "unexpected output"
  elif [ -s "$misses_file" ]; then echo noted
  else echo out; fi
}
expect_reason() {
  if tr '\n' ' ' < "$misses_file" | grep -Eq "$2"; then record "$1" ok; else record "$1" fail "$(cat "$misses_file")"; fi
}

kit_claim='The kit doesn'"'"'t require a check behind each lesson, so lessons are only text.'
heroku_reply=$(printf 'Run this:\n\n```bash\nheroku config:set PRICE=15 --app shop\n```\n')

# Claims about instructions.
{ write_typed_message "will these hold?"; } > "$transcript"
expect_eq "a claim about the kit with nothing read is noted" noted "$(run_hook "$kit_claim")"
expect_reason "it says nothing was read" "without reading them first"

{ write_typed_message "will these hold?"; write_tool_call Read file_path "/home/me/kit/plugins/kc-conventions/rules/kc-working-agreement.md"; write_tool_result; } > "$transcript"
expect_eq "a claim about the kit after reading a rule file goes out" out "$(run_hook "$kit_claim")"

{ write_typed_message "will these hold?"; write_tool_call Bash command "git grep -n lesson origin/main -- CLAUDE.md"; write_tool_result; } > "$transcript"
expect_eq "a claim after a shell read of CLAUDE.md goes out" out "$(run_hook "$kit_claim")"

{ write_typed_message "earlier question"; write_tool_call Read file_path "/home/me/kit/plugins/kc-gates/skills/kc-code-review/SKILL.md"; write_tool_result; write_typed_message "will these hold?"; } > "$transcript"
expect_eq "a read in an earlier turn doesn't count" noted "$(run_hook "$kit_claim")"

{ write_typed_message "will these hold?"; write_reminder; write_tool_call Grep path "/home/me/repo/.claude/review-conventions.md"; write_tool_result; } > "$transcript"
expect_eq "a hook note doesn't start a new turn, so the read before it counts" out "$(run_hook "$kit_claim")"

{ write_typed_message "what next?"; } > "$transcript"
expect_eq "a reply that says nothing about instructions goes out" out "$(run_hook "Next, the country pages still offer the trial.")"
expect_eq "naming the kit without a claim about it goes out" out "$(run_hook "The kit PR is merged.")"

# Commands for account CLIs.
{ write_typed_message "set the config"; } > "$transcript"
expect_eq "a heroku command never checked is noted" noted "$(run_hook "$heroku_reply")"
expect_reason "it names the CLI" "a heroku command"

{ write_typed_message "set the config"; write_tool_call Bash command "heroku auth:whoami"; write_tool_result; } > "$transcript"
expect_eq "a heroku command after running heroku goes out" out "$(run_hook "$heroku_reply")"

{ write_typed_message "set the config"; write_tool_call Read file_path "/home/me/.config/heroku/config.json"; write_tool_result; } > "$transcript"
expect_eq "a heroku command after reading its config goes out" out "$(run_hook "$heroku_reply")"

{ write_typed_message "set the config"; write_tool_call Bash command "cat heroku-notes.txt | grep herokus"; write_tool_result; } > "$transcript"
expect_eq "a command that only names the CLI inside a word doesn't count" noted "$(run_hook "$heroku_reply")"

deploy_reply=$(printf 'Deploy:\n\n```bash\nnpx vercel deploy --prod\n```\n')
{ write_typed_message "deploy it"; } > "$transcript"
expect_eq "a command run through bunx is still the CLI's" noted "$(run_hook "$deploy_reply")"
{ write_typed_message "deploy it"; write_tool_call Bash command "npx vercel whoami"; write_tool_result; } > "$transcript"
expect_eq "after the CLI's own status check it goes out" out "$(run_hook "$deploy_reply")"

{ write_typed_message "build it"; } > "$transcript"
expect_eq "a command for a CLI that acts on no account goes out" out "$(run_hook "$(printf '```bash\nbun run build\n```\n')")"
expect_eq "a CLI named in prose, not handed over, goes out" out "$(run_hook 'Then sign in with `heroku login` when you have time.')"
expect_eq "a prose line that starts with a CLI's name goes out" out "$(run_hook "$(printf 'Done.\nheroku now holds both new values.\n')")"

both_reply=$(printf '%s\n\n```bash\ngh pr merge 7\n```\n' "$kit_claim")
expect_eq "both kinds in one reply are noted together" noted "$(run_hook "$both_reply")"
expect_reason "it gives both reasons" "without reading them first.*a gh command"

# Commands anywhere in a fenced block, behind any fence, at the start of any command in a line.
{ write_typed_message "ship it"; } > "$transcript"
expect_eq "a CLI block after a block in another language is still read" noted "$(run_hook "$(printf 'Config:\n\n```json\n{"a": 1}\n```\n\nThen:\n\n```bash\ngh pr merge 7\n```\n')")"
expect_eq "prose after a block in another language is not read as commands" out "$(run_hook "$(printf '```json\n{"a": 1}\n```\n\ngh is the code host CLI.\n')")"
expect_eq "a CLI after cd and && is found" noted "$(run_hook "$(printf '```bash\ncd shop && gh pr merge 7\n```\n')")"
expect_eq "a CLI behind a variable assignment is found" noted "$(run_hook "$(printf '```bash\nAPP=shop heroku config:set PRICE=15\n```\n')")"
expect_eq "a CLI behind a runner's flags is found" noted "$(run_hook "$(printf '```bash\nnpx --yes vercel deploy --prod\n```\n')")"
expect_eq "a CLI in a tilde fence is found" noted "$(run_hook "$(printf '~~~\ngh pr merge 7\n~~~\n')")"
{ write_typed_message "ship it"; write_tool_call Bash command "grep -rn gh src"; write_tool_result; } > "$transcript"
expect_eq "a shell command that only names the CLI as an argument doesn't count as running it" noted "$(run_hook "$(printf '```bash\ngh pr merge 7\n```\n')")"
{ write_typed_message "ship it"; write_tool_call Bash command "cd shop && gh auth status"; write_tool_result; } > "$transcript"
expect_eq "the CLI run after cd and && counts" out "$(run_hook "$(printf '```bash\ngh pr merge 7\n```\n')")"

# A claim wrapped across two lines is one claim.
{ write_typed_message "will these hold?"; } > "$transcript"
expect_eq "a claim split across lines is noted" noted "$(run_hook "$(printf 'The kit\ndoesn'"'"'t require a check for each lesson.')")"

# Machine messages in the transcript don't start a new turn; a typed one does, in either shape.
for note in '{isMeta: true, message: {content: [{type: "text", text: "a note"}]}}' \
  '{message: {content: "Caveat: the messages below were generated by the user while running local commands."}}' \
  '{message: {content: [{type: "text", text: "<task-notification>done</task-notification>"}]}}' \
  '{isCompactSummary: true, message: {content: "the summary"}}'; do
  { write_typed_message "will these hold?"; write_tool_call Read file_path "/home/me/kit/plugins/kc-gates/agents/naming-gate.md"; write_tool_result; jq -cn "{type: \"user\"} + $note"; } > "$transcript"
  expect_eq "a read before a machine message still counts: $(printf '%s' "$note" | cut -c1-40)" out "$(run_hook "$kit_claim")"
done
{ write_typed_message "earlier"; write_tool_call Read file_path "/home/me/kit/plugins/kc-gates/agents/naming-gate.md"; write_tool_result; jq -cn '{type: "user", message: {role: "user", content: "will these hold?"}}'; } > "$transcript"
expect_eq "a typed message with string content starts a new turn" noted "$(run_hook "$kit_claim")"

# A skill's preamble is not the person typing, so it doesn't start a new turn.
{ write_typed_message "will these hold?"; write_tool_call Read file_path "/home/me/kit/plugins/kc-conventions/rules/kc-testing.md"; write_tool_result; jq -cn '{type: "user", message: {role: "user", content: [{type: "text", text: "Base directory for this skill: /home/me/skill"}]}}'; } > "$transcript"
expect_eq "a skill preamble after a read doesn't hide the read" out "$(run_hook "$kit_claim")"
{ write_typed_message "will these hold?"; write_tool_call Read file_path "/home/me/kit/plugins/kc-conventions/rules/kc-testing.md"; write_tool_result; jq -cn '{type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: "t", content: "ok"}, {type: "text", text: "ok"}]}}'; } > "$transcript"
expect_eq "a tool result with text beside it doesn't start a new turn" out "$(run_hook "$kit_claim")"

# After plugins were installed, the reply opens with the reload status.
installed_note="kc-gates: this changed the installed plugins. Make it the first line of your reply."
{ write_typed_message "merge it"; write_tool_call Bash command "claude plugin update kc-gates@shop-kit"; write_tool_result; write_hook_note "$installed_note"; } > "$transcript"
expect_eq "plugins installed, reload status on the first line: out" out \
  "$(run_hook "$(printf 'Installed 3.7.0; the app reloads this session by itself.\n\nThe merge went through.')")"
expect_eq "plugins installed, reload status only further down: noted" noted \
  "$(run_hook "$(printf 'Merged the PR.\n\n- Installed: 3.7.0, the app reloads by itself.')")"
expect_reason "it names the first line" "first line didn't give the reload status"
expect_eq "blank lines before the first line don't count" out \
  "$(run_hook "$(printf '\n\nReloads by itself once this reply ends; 3.7.0 is installed.')")"
{ write_typed_message "merge it"; write_tool_call Bash command "gh pr merge 7"; write_tool_result; write_hook_note "kc-gates: this merged a pull request, so its look-back is due."; } > "$transcript"
expect_eq "a turn whose hooks installed nothing needs no reload line" out "$(run_hook "Merged the PR.")"
ask_note="kc-gates: this changed the installed plugins, and this session still runs the versions it loaded. Ask the person for /reload-plugins now, as the turn's one question in the host's question box."
{ write_typed_message "merge it"; write_tool_call Bash command "claude plugin update kc-gates@shop-kit"; write_tool_result; write_hook_note "$ask_note"; } > "$transcript"
expect_eq "a host that asks for /reload-plugins instead needs no reload first line" out "$(run_hook "Merged the PR.")"
{ write_typed_message "update"; write_hook_note "$installed_note"; write_typed_message "and now?"; } > "$transcript"
expect_eq "an install in an earlier turn doesn't count" out "$(run_hook "Merged the PR.")"

# A reply that can't settle something is reminded to check every source first.
write_typed_message "did it reload?" > "$transcript"
expect_eq "\"I can't confirm\" is noted" noted "$(run_hook "I can't confirm the session reloaded.")"
expect_reason "it asks for every source checked" "check every source that could settle it"
expect_eq "\"not sure whether\" is noted" noted "$(run_hook "I'm not sure whether it reloaded.")"
expect_eq "a reply that settles it is out" out "$(run_hook "It reloaded: the app log shows it at 12:13:34.")"

# It never blocks on what it can't read.
rm -f "$misses_file"
jq -cn --arg reply "$heroku_reply" '{session_id: "s", transcript_path: "/nonexistent", last_assistant_message: $reply}' | bash "$hook" > "$hook_output"
expect_eq "a missing transcript notes nothing" out "$([ -s "$misses_file" ] && echo noted || echo out)"
write_typed_message "x" > "$transcript"
expect_eq "with no plugin data folder it prints nothing, errors included" "" "$(jq -cn --arg reply "$kit_claim" --arg path "$transcript" '{session_id: "s", transcript_path: $path, last_assistant_message: $reply}' | CLAUDE_PLUGIN_DATA='' bash "$hook" 2>&1)"
rm -rf "$CLAUDE_PLUGIN_DATA"
expect_eq "with no session id it prints nothing, errors included" "" "$(jq -cn --arg reply "$kit_claim" --arg path "$transcript" '{transcript_path: $path, last_assistant_message: $reply}' | bash "$hook" 2>&1)"
expect_eq "with no session id no misses folder is made" absent "$([ -e "$CLAUDE_PLUGIN_DATA/reply-misses" ] && echo present || echo absent)"

finish
