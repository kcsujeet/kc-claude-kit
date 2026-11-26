#!/usr/bin/env bash
# shellcheck disable=SC2016  # the replies hold Markdown backticks, not shell expansions
# Tests scripts/guard-unchecked-claim.sh: text about to be published (a commit message, a pull request
# or issue body or comment, a tracker write) that states a fact about code, data or a tool
# (a quantified statement, a count, what a named thing does or is) is denied unless a tool
# call of the turn, other than an edit, was given or returned text naming what the fact is about, or
# the text says plainly it is unverified; plain text, quoted text, hedges, questions and the
# turn's own changes go out. Text fixtures are in fixtures/guard-unchecked-claim/.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
guard="$(dirname "$tests_dir")/scripts/guard-unchecked-claim.sh"
fixtures="$tests_dir/fixtures/guard-unchecked-claim"
require_jq

transcript=$work_dir/transcript.jsonl

emit_typed_message() { jq -cn --arg text "$1" '{type: "user", message: {role: "user", content: [{type: "text", text: $text}]}}'; }
# emit_call <id> <tool> <input key> <input value> <result text>: a tool call and what it returned.
emit_call() {
  jq -cn --arg id "$1" --arg name "$2" --arg key "$3" --arg value "$4" \
    '{type: "assistant", message: {role: "assistant", content: [{type: "tool_use", id: $id, name: $name, input: {($key): $value}}]}}'
  jq -cn --arg id "$1" --arg text "$5" \
    '{type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: $id, content: $text}]}}'
}

# Runs the guard on a tool call; prints held or out, and keeps its output in $work_dir/last-output.
# run_tool <tool> <input JSON>
run_tool() {
  local output
  output=$(jq -cn --arg tool "$1" --argjson input "$2" --arg path "$transcript" \
    '{session_id: "s", transcript_path: $path, hook_event_name: "PreToolUse", tool_name: $tool, tool_use_id: "self", tool_input: $input}' | bash "$guard")
  printf '%s' "$output" > "$work_dir/last-output"
  if printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then echo held; else echo out; fi
}
# run_stop <text>: the text as the body of a pull request comment, the usual way text is published.
run_stop() {
  run_tool Bash "$(jq -cn --arg text "$1" '{command: ("gh pr comment 7 --body \"$(cat <<'"'"'EOF'"'"'\n" + $text + "\nEOF\n)\"")}')"
}

# Texts as fixture files: blocked-* are held with nothing read, passes-* go out.
emit_typed_message "what is going on with the orders?" > "$transcript"
for fixture in "$fixtures"/blocked-*.txt; do
  expect_eq "held with nothing read: $(basename "$fixture" .txt)" held "$(run_stop "$(cat "$fixture")")"
done
for fixture in "$fixtures"/passes-*.txt; do
  expect_eq "out with nothing read: $(basename "$fixture" .txt)" out "$(run_stop "$(cat "$fixture")")"
done
run_stop "$(cat "$fixtures/blocked-quantified-column.txt")" > /dev/null
expect_contains "the block quotes the claim" "Every order has a currency set" "$(cat "$work_dir/last-output")"
expect_contains "the block names the two ways out" "or say plainly in the text that it is unverified" "$(cat "$work_dir/last-output")"
expect_contains "the block is the guard's own" "Blocked by the kc-gates plugin" "$(cat "$work_dir/last-output")"

# Every action that publishes text, with the same claim; the actions that don't, with it too.
claim="Every order has a currency set, so the totals add up."
expect_eq "git commit -m is held" held "$(run_tool Bash "$(jq -cn --arg c "git commit -m \"$claim\"" '{command: $c}')")"
expect_eq "git -C dir commit is held" held "$(run_tool Bash "$(jq -cn --arg c "git -C /repo commit -m \"$claim\"" '{command: $c}')")"
expect_eq "git add then commit is held" held "$(run_tool Bash "$(jq -cn --arg c "git add -A && git commit -m \"$claim\"" '{command: $c}')")"
expect_eq "gh pr create is held" held "$(run_tool Bash "$(jq -cn --arg c "gh pr create --title t --body \"$claim\"" '{command: $c}')")"
expect_eq "gh pr edit is held" held "$(run_tool Bash "$(jq -cn --arg c "gh pr edit 7 --body \"$claim\"" '{command: $c}')")"
expect_eq "gh issue comment is held" held "$(run_tool Bash "$(jq -cn --arg c "gh issue comment 3 --body \"$claim\"" '{command: $c}')")"
expect_eq "gh api with a body is held" held "$(run_tool Bash "$(jq -cn --arg c "gh api repos/o/r/issues/3/comments -f body=\"$claim\"" '{command: $c}')")"
expect_eq "a Linear comment save is held" held "$(run_tool mcp__claude_ai_Linear__save_comment "$(jq -cn --arg b "$claim" '{issueId: "ABC-1", body: $b}')")"
expect_eq "a Jira comment add is held" held "$(run_tool mcp__atlassian__addCommentToJiraIssue "$(jq -cn --arg b "$claim" '{issueIdOrKey: "ABC-1", commentBody: $b}')")"
expect_eq "a Linear issue save is held" held "$(run_tool mcp__claude_ai_Linear__save_issue "$(jq -cn --arg b "$claim" '{title: "t", description: $b}')")"
expect_eq "echo of the claim is not publishing" out "$(run_tool Bash "$(jq -cn --arg c "echo \"$claim\"" '{command: $c}')")"
expect_eq "a commit with no claim goes out" out "$(run_tool Bash '{"command": "git commit -m \"Add the currency column to orders\""}')"
expect_eq "a read-only issue call goes out" out "$(run_tool mcp__claude_ai_Linear__get_issue "$(jq -cn --arg b "$claim" '{id: $b}')")"
expect_eq "a Slack message is not covered here" out "$(run_tool mcp__claude_ai_Slack__slack_send_message_draft "$(jq -cn --arg b "$claim" '{text: $b}')")"
expect_eq "a Write is not publishing" out "$(run_tool Write "$(jq -cn --arg b "$claim" '{file_path: "/repo/notes.md", content: $b}')")"
expect_eq "a commit message saying it is unverified goes out" out "$(run_tool Bash "$(jq -cn --arg c "git commit -m \"$claim Unverified: schema not read.\"" '{command: $c}')")"
{ emit_typed_message "ship it"; emit_call self Bash command "git commit -m \"$claim\"" "done"; } > "$transcript"
expect_eq "the call being judged is not its own evidence" held "$(run_tool Bash "$(jq -cn --arg c "git commit -m \"$claim\"" '{command: $c}')")"
{ emit_typed_message "ship it"; emit_call a Bash command "git diff --stat" 'db/migrate/20260101_orders_currency.rb | 3 +++'; } > "$transcript"
expect_eq "a commit after a diff that names the subject goes out" out "$(run_tool Bash "$(jq -cn --arg c "git commit -m \"$claim\"" '{command: $c}')")"

# The example classes, each with the read that settles it.
every_order=$(cat "$fixtures/blocked-quantified-column.txt")
{ emit_typed_message "are totals safe to sum?"; emit_call a Grep pattern "currency" 'db/schema.rb:41:    t.string "currency", null: true'; } > "$transcript"
expect_eq "a search naming the subject settles the claim" out "$(run_stop "$every_order")"
{ emit_typed_message "are totals safe to sum?"; emit_call a Read file_path "/repo/db/schema.rb" 'create_table "orders" do |t|
  t.string "currency", null: true'; } > "$transcript"
expect_eq "a read whose result names the subject settles the claim" out "$(run_stop "$every_order")"
{ emit_typed_message "are totals safe to sum?"; emit_call a Read file_path "/repo/app/models/customer.rb" 'class Customer; end'; } > "$transcript"
expect_eq "a read of an unrelated file does not" held "$(run_stop "$every_order")"
{ emit_typed_message "are totals safe to sum?"; emit_call a Edit file_path "/repo/app/models/order.rb" "currency order updated"; } > "$transcript"
expect_eq "an edit naming the subject is not a read" held "$(run_stop "$every_order")"
{ emit_typed_message "are totals safe to sum?"; emit_call a Bash command "psql -c 'select count(*) from orders where currency is null'" "(1 row) 0"; } > "$transcript"
expect_eq "a query naming the subject settles the claim" out "$(run_stop "$every_order")"
{ emit_typed_message "earlier"; emit_call a Grep pattern "currency" "db/schema.rb"; emit_typed_message "are totals safe to sum?"; } > "$transcript"
expect_eq "a read in an earlier turn does not" held "$(run_stop "$every_order")"

cache_claim=$(cat "$fixtures/blocked-cache-deploy.txt")
{ emit_typed_message "why is the price stale?"; emit_call a Grep pattern "deploy" "bin/deploy:12: bin/rails cache:clear"; } > "$transcript"
expect_eq "the cache claim after a search for the deploy script goes out" out "$(run_stop "$cache_claim")"

library_claim=$(cat "$fixtures/blocked-library-default.txt")
{ emit_typed_message "why the duplicate charge?"; emit_call a WebFetch url "https://example.com/shopkit/docs/retries" "shopkit retries on 5xx by default"; } > "$transcript"
expect_eq "the library claim after fetching its docs goes out" out "$(run_stop "$library_claim")"

config_claim=$(cat "$fixtures/blocked-config-says.txt")
{ emit_typed_message "is it a timeout?"; emit_call a Read file_path "/repo/config/app.yml" "checkout_timeout: 30"; } > "$transcript"
expect_eq "the config claim after reading the config goes out" out "$(run_stop "$config_claim")"

count_claim=$(cat "$fixtures/blocked-count.txt")
{ emit_typed_message "can we rename it?"; emit_call a Grep pattern "Order#total" "app/a.rb: Order#total"; } > "$transcript"
expect_eq "the count claim after a search for the name goes out" out "$(run_stop "$count_claim")"

# A claim a test run backs, and a claim about a run nobody did.
{ emit_typed_message "did it pass?"; } > "$transcript"
expect_eq "all specs pass with no run is held" held "$(run_stop "All specs pass for the checkout.")"
{ emit_typed_message "did it pass?"; emit_call a Bash command "bundle exec rspec spec/checkout_spec.rb" "12 examples, 0 failures"; } > "$transcript"
expect_eq "all specs pass after running rspec goes out" out "$(run_stop "All specs pass for the checkout.")"

# A sentence with no usable word is settled by any lookup, and by none otherwise.
{ emit_typed_message "what now?"; } > "$transcript"
expect_eq "a claim with nothing to look up and no lookup is held" held "$(run_stop "It is never set.")"
{ emit_typed_message "what now?"; emit_call a Read file_path "/repo/README.md" "hello"; } > "$transcript"
expect_eq "the same claim after any read goes out" out "$(run_stop "It is never set.")"
expect_eq "a claim with a subject the read does not name is held" held "$(run_stop "The cache is never used.")"

# What it can't read.
{ emit_typed_message "are totals safe to sum?"; } > "$transcript"
expect_eq "a missing transcript prints nothing" "" "$(jq -cn --arg tool Bash '{tool_name: $tool, transcript_path: "/nonexistent", tool_input: {command: "git commit -m \"Every order has a currency set\""}}' | bash "$guard")"
expect_eq "an empty body goes out" out "$(run_stop "")"
expect_eq "a marker in another sentence covers the claim" out "$(run_stop "$(printf 'The cache is cleared on deploy.\nFrom memory, so check it.')")"

finish
