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

typed() { jq -cn --arg text "$1" '{type: "user", message: {role: "user", content: $text}}'; }
tool_call() {
  jq -cn --arg name "$1" --arg key "$2" --arg value "$3" \
    '{type: "assistant", message: {role: "assistant", content: [{type: "tool_use", id: "t", name: $name, input: {($key): $value}}]}}'
}
tool_result() { jq -cn '{type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: "t", content: "ok"}]}}'; }
reminder() { jq -cn '{type: "user", message: {role: "user", content: "<system-reminder>a hook note</system-reminder>"}}'; }

# Runs the hook on <reply> against the transcript; prints "held" or "out", and keeps the output in
# $hook_output for expect_reason.
hook_output=$work_dir/hook-output
run_hook() {
  local reply=$1 active=${2:-false}
  jq -cn --arg reply "$reply" --arg path "$transcript" --argjson active "$active" \
    '{session_id: "s", transcript_path: $path, hook_event_name: "Stop", stop_hook_active: $active, last_assistant_message: $reply}' \
    | bash "$hook" > "$hook_output"
  if grep -q '"decision": *"block"' "$hook_output"; then echo held; else echo out; fi
}
expect_reason() {
  if grep -Eq "$2" "$hook_output"; then record "$1" ok; else record "$1" fail "$(cat "$hook_output")"; fi
}

kit_claim='The kit doesn'"'"'t require a check behind each lesson, so lessons are only text.'
heroku_reply=$(printf 'Run this:\n\n```bash\nheroku config:set PRICE=15 --app shop\n```\n')

# Claims about instructions.
{ typed "will these hold?"; } > "$transcript"
expect_eq "a claim about the kit with nothing read is held" held "$(run_hook "$kit_claim")"
expect_reason "it says nothing was read" "nothing in this turn read them"

{ typed "will these hold?"; tool_call Read file_path "/home/me/kit/plugins/kc-conventions/rules/kc-working-agreement.md"; tool_result; } > "$transcript"
expect_eq "a claim about the kit after reading a rule file goes out" out "$(run_hook "$kit_claim")"

{ typed "will these hold?"; tool_call Bash command "git grep -n lesson origin/main -- CLAUDE.md"; tool_result; } > "$transcript"
expect_eq "a claim after a shell read of CLAUDE.md goes out" out "$(run_hook "$kit_claim")"

{ typed "earlier question"; tool_call Read file_path "/home/me/kit/plugins/kc-gates/skills/kc-code-review/SKILL.md"; tool_result; typed "will these hold?"; } > "$transcript"
expect_eq "a read in an earlier turn doesn't count" held "$(run_hook "$kit_claim")"

{ typed "will these hold?"; reminder; tool_call Grep path "/home/me/repo/.claude/review-conventions.md"; tool_result; } > "$transcript"
expect_eq "a hook note doesn't start a new turn, so the read before it counts" out "$(run_hook "$kit_claim")"

{ typed "what next?"; } > "$transcript"
expect_eq "a reply that says nothing about instructions goes out" out "$(run_hook "Next, the country pages still offer the trial.")"
expect_eq "naming the kit without a claim about it goes out" out "$(run_hook "The kit PR is merged.")"
expect_eq "a held reply's second try goes out" out "$(run_hook "$kit_claim" true)"

# Commands for account CLIs.
{ typed "set the config"; } > "$transcript"
expect_eq "a heroku command never checked is held" held "$(run_hook "$heroku_reply")"
expect_reason "it names the CLI" "a heroku command"

{ typed "set the config"; tool_call Bash command "heroku auth:whoami"; tool_result; } > "$transcript"
expect_eq "a heroku command after running heroku goes out" out "$(run_hook "$heroku_reply")"

{ typed "set the config"; tool_call Read file_path "/home/me/.config/heroku/config.json"; tool_result; } > "$transcript"
expect_eq "a heroku command after reading its config goes out" out "$(run_hook "$heroku_reply")"

{ typed "set the config"; tool_call Bash command "cat heroku-notes.txt | grep herokus"; tool_result; } > "$transcript"
expect_eq "a command that only names the CLI inside a word doesn't count" held "$(run_hook "$heroku_reply")"

deploy_reply=$(printf 'Deploy:\n\n```bash\nnpx vercel deploy --prod\n```\n')
{ typed "deploy it"; } > "$transcript"
expect_eq "a command run through bunx is still the CLI's" held "$(run_hook "$deploy_reply")"
{ typed "deploy it"; tool_call Bash command "npx vercel whoami"; tool_result; } > "$transcript"
expect_eq "after the CLI's own status check it goes out" out "$(run_hook "$deploy_reply")"

{ typed "build it"; } > "$transcript"
expect_eq "a command for a CLI that acts on no account goes out" out "$(run_hook "$(printf '```bash\nbun run build\n```\n')")"
expect_eq "a CLI named in prose, not handed over, goes out" out "$(run_hook 'Then sign in with `heroku login` when you have time.')"
expect_eq "a prose line that starts with a CLI's name goes out" out "$(run_hook "$(printf 'Done.\nheroku now holds both new values.\n')")"
expect_eq "a held command's second try goes out" out "$(run_hook "$heroku_reply" true)"

both_reply=$(printf '%s\n\n```bash\ngh pr merge 7\n```\n' "$kit_claim")
expect_eq "both kinds in one reply are held together" held "$(run_hook "$both_reply")"
expect_reason "it gives both reasons" "nothing in this turn read them.*a gh command"

# It never blocks on what it can't read.
expect_eq "a missing transcript lets the reply out" out "$(jq -cn --arg reply "$heroku_reply" '{transcript_path: "/nonexistent", stop_hook_active: false, last_assistant_message: $reply}' | bash "$hook" | grep -q block && echo held || echo out)"

finish
