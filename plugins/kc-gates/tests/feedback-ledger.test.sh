#!/usr/bin/env bash
# Tests scripts/feedback-ledger.sh: `list` finds every kind of feedback in a session transcript
# and nothing else, and `check` refuses a ledger that leaves an item without a verdict or names a
# rule that isn't there.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
script="$(dirname "$tests_dir")/scripts/feedback-ledger.sh"
require_jq

# A transcript with one entry of every shape the lister reads or skips.
transcript=$work_dir/session.jsonl
cat > "$transcript" <<'JSONL'
{"type":"user","message":{"role":"user","content":"Fix the total on the order page"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"On it."}]}}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<system-reminder>\nnot typed</system-reminder>"},{"type":"text","text":"don't round\nbefore summing"}]}}
{"type":"user","message":{"role":"user","content":"<task-notification>\n<task-id>a1</task-id></task-notification>"}}
{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"This session is being continued"}}
{"type":"user","isMeta":true,"message":{"role":"user","content":[{"type":"text","text":"Base directory for this skill: /x"}]}}
{"type":"user","isMeta":true,"message":{"role":"user","content":"Another Claude session sent a message: add the tax line"}}
{"type":"attachment","attachment":{"type":"queued_command","commandMode":"prompt","prompt":"why a helper for one line?"}}
{"type":"attachment","attachment":{"type":"queued_command","commandMode":"prompt","prompt":[{"type":"text","text":"<system-reminder>x</system-reminder>"},{"type":"text","text":"name it for the store"}]}}
{"type":"attachment","attachment":{"type":"queued_command","commandMode":"task-notification","prompt":"<task-notification>done</task-notification>"}}
{"type":"attachment","attachment":{"type":"queued_command","commandMode":"bash","prompt":"git status"}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":"The user doesn't want to proceed with this tool use. The tool use was rejected."}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2","is_error":true,"content":"Exit code 1"}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t3","content":[{"type":"text","text":"The user answered: \"Keep cents\""}]}]}}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}
JSONL
qa_rows=$work_dir/qa-rows.txt
printf 'Row 1: total shows 0 for a free order\n\nRow 2: tax\tmissing\n' > "$qa_rows"

list=$work_dir/feedback.tsv
bash "$script" list "$transcript" --extra "$qa_rows" > "$list"
listed() { cut -f2,3 "$list"; }
expected=$'typed\tFix the total on the order page
typed\tdon\'t round before summing
session\tAnother Claude session sent a message: add the tax line
typed\twhy a helper for one line?
typed\tname it for the store
rejected\tThe user doesn\'t want to proceed with this tool use. The tool use was rejected.
answer\tThe user answered: "Keep cents"
interrupt\t[Request interrupted by user for tool use]
qa-rows.txt\tRow 1: total shows 0 for a free order
qa-rows.txt\tRow 2: tax missing'
expect_eq "list finds each kind of feedback, in order, and skips reminders, notifications, summaries, skill text, queued shell commands and tool errors" "$expected" "$(listed)"
expect_eq "items are numbered F1 onwards" "F1 F10" "$(cut -f1 "$list" | sed -n '1p;$p' | tr '\n' ' ' | sed 's/ $//')"

# check: a lesson diff that adds §B13 and WF14, and rule files that hold §R11 and **QA1.**
diff_file=$work_dir/lesson.diff
printf -- '--- a/rules.md\n+++ b/rules.md\n+- [ ] §B13 A new kind of actor\n+- **WF14.** The look-back lists\n- removed §B9 line\n' > "$diff_file"
rules_dir=$work_dir/rules
mkdir -p "$rules_dir"
printf -- '- [ ] §R11 Reads and writes\n- **QA1.** Sheets\n- [ ] §R16 other\n' > "$rules_dir/topic.md"

complete_ledger() {
  printf 'F1\tnot-feedback\tthe task\n'
  printf 'F2\tlesson\t§B13\n'
  printf 'F3\tlesson\tB13,WF14\n'
  printf 'F4\tcovered\t§R11\trule had no box for one-line helpers\n'
  printf 'F5\tone-off\tnaming call for this file\n'
  printf 'F6\tnot-feedback\tthe rejected call was a duplicate\n'
  printf 'F7\tcovered\tQA1\tsheet rows never counted\n'
  printf 'F8\tnot-feedback\tan interrupt to redirect, its message is F4\n'
  printf 'F9\tlesson\tWF14\n'
  printf 'F10\tone-off\ttax line is this sheet only\n'
}
ledger=$work_dir/ledger.tsv
run_check() { bash "$script" check "$list" "$ledger" --diff "$diff_file" --rules "$rules_dir" 2>&1; }
expect_check() {
  local expectation=$1 label=$2 output actual=passed
  output=$(run_check) || actual=failed
  expect_eq "$label" "$expectation" "$actual"
  last_output=$output
}

complete_ledger > "$ledger"
expect_check passed "a ledger with a verdict for every item passes"
expect_contains "it counts the items" "10 item(s), each with a verdict" "$last_output"

complete_ledger | sed '/^F5/d' > "$ledger"
expect_check failed "an item with no verdict fails"
expect_contains "it names the item" "F5: no verdict in the ledger" "$last_output"

{ complete_ledger; printf 'F2\tone-off\tagain\n'; } > "$ledger"
expect_check failed "an item given two verdicts fails"
expect_contains "it names the item" "F2: listed twice in the ledger" "$last_output"

{ complete_ledger; printf 'F11\tone-off\tno such item\n'; } > "$ledger"
expect_check failed "a verdict for an item not on the list fails"
expect_contains "it names the item" "F11: not on the feedback list" "$last_output"

complete_ledger | sed 's/^F2\tlesson\t§B13$/F2\tlesson\t§B9/' > "$ledger"
expect_check failed "a lesson whose rule the diff only removes fails"
expect_contains "it names the rule" "F2: lesson §B9 is not added by the lesson diff" "$last_output"

complete_ledger | sed 's/^F2\tlesson\t§B13$/F2\tlesson\t§B1/' > "$ledger"
expect_check failed "a lesson id that is only the start of an added id fails"

complete_ledger | sed 's/^F3\tlesson\tB13,WF14$/F3\tlesson\tB13,WF15/' > "$ledger"
expect_check failed "every id of a lesson must be added, not only the first"
expect_contains "it names the missing one" "F3: lesson WF15 is not added by the lesson diff" "$last_output"

complete_ledger | sed 's/^F9\tlesson\tWF14$/F9\tlesson\trules.md/' > "$ledger"
expect_check passed "a lesson may name the rule file its diff changes, for a file with no ids"
complete_ledger | sed 's/^F9\tlesson\tWF14$/F9\tlesson\tagreement.md/' > "$ledger"
expect_check failed "a lesson naming a file the diff doesn't change fails"
expect_contains "it names the file" "F9: lesson agreement.md is not a file the lesson diff changes" "$last_output"
complete_ledger | sed 's/^F9\tlesson\tWF14$/F9\tlesson\tr.les.md/' > "$ledger"
expect_check failed "a file name is matched literally, not as a pattern"

complete_ledger | sed 's/^F2\tlesson\t§B13$/F2\tlesson/' > "$ledger"
expect_check failed "a lesson with no rule id fails"
expect_contains "it says so" "F2: lesson names no rule id" "$last_output"

complete_ledger | sed 's/^F4\tcovered\t§R11\t.*/F4\tcovered\t§R12\tno box/' > "$ledger"
expect_check failed "covered by a rule no rule file has fails"
expect_contains "it names the rule" "F4: covered by §R12, which no rule file has" "$last_output"

complete_ledger | sed 's/^F4\tcovered\t§R11\t.*/F4\tcovered\t§R1\tno box/' > "$ledger"
expect_check failed "covered by an id that is only the start of a real one fails"

complete_ledger | sed 's/^F4\tcovered\t§R11\t.*/F4\tcovered\t§R11/' > "$ledger"
expect_check failed "covered with no reason it was still missed fails"
expect_contains "it asks why" "F4: covered by §R11 says nothing on why it was still missed" "$last_output"

complete_ledger | sed 's/^F4\tcovered\t§R11\t.*/F4\tcovered/' > "$ledger"
expect_check failed "covered with no rule id fails"
expect_contains "it says so" "F4: covered names no rule id" "$last_output"

complete_ledger | sed 's/^F5\tone-off\t.*/F5\tone-off/' > "$ledger"
expect_check failed "a one-off with no reason fails"
expect_contains "it asks for the reason" "F5: one-off gives no reason" "$last_output"

complete_ledger | sed 's/^F1\tnot-feedback\t.*/F1\tnot-feedback/' > "$ledger"
expect_check failed "not-feedback with no reason fails"

complete_ledger | sed 's/^F5\tone-off\t/F5\tskipped\t/' > "$ledger"
expect_check failed "an unknown verdict fails"
expect_contains "it lists the verdicts" "'skipped' is not lesson, covered, one-off or not-feedback" "$last_output"

complete_ledger > "$ledger"
output=$(bash "$script" check "$list" "$ledger" --rules "$rules_dir" 2>&1) && actual=passed || actual=failed
expect_eq "with no lesson diff given, no lesson can be shown" failed "$actual"

expect_eq "a missing transcript is a usage error" 2 "$(bash "$script" list "$work_dir/none.jsonl" >/dev/null 2>&1; echo $?)"
expect_eq "an unknown command is a usage error" 2 "$(bash "$script" tally >/dev/null 2>&1; echo $?)"

finish
