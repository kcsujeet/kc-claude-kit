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
{"type":"user","message":{"role":"user","content":"<command-message>review is running</command-message>"}}
JSONL
qa_rows=$work_dir/qa-rows.txt
printf 'Row 1: total shows 0 for a free order\n\nRow 2: tax\tmissing\n' > "$qa_rows"

list=$work_dir/feedback.tsv
bash "$script" list "$transcript" --extra "$qa_rows" > "$list"
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
expect_eq "list finds each kind of feedback, in order, and skips reminders, notifications, summaries, skill text, queued shell commands and tool errors" "$expected" "$(cut -f2,3 "$list")"
expect_eq "items are numbered F1 onwards" "F1 F10" "$(cut -f1 "$list" | sed -n '1p;$p' | tr '\n' ' ' | sed 's/ $//')"

# check: a lesson diff that adds §B13 and WF14, and rule files that hold §R11 and **QA1.**
diff_file=$work_dir/lesson.diff
printf -- '--- a/rules.md\n+++ b/rules.md\n+- [ ] §B13 A new kind of actor\n+- **WF14.** The look-back lists\n- removed §B9 line\n' > "$diff_file"
rules_dir=$work_dir/rules
mkdir -p "$rules_dir/rules"
printf -- '- [ ] §R11 Reads and writes\n- **QA1.** Sheets\n- [ ] §R16 other, see §R17\n' > "$rules_dir/rules/topic.md"
printf 'c++ notes\n' > "$rules_dir/rules/c++.md"
printf 'what changed\n' > "$rules_dir/changes.md"
printf 'how to review\n' > "$rules_dir/SKILL.md"
printf -- '- [ ] §R12 a rule outside Markdown\n' > "$rules_dir/notes.txt"

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
expect_contains "it names the rule" "F4: covered by §R12, which no rule file had" "$last_output"

complete_ledger | sed 's/^F4\tcovered\t§R11\t.*/F4\tcovered\t§R1\tno box/' > "$ledger"
expect_check failed "covered by an id that is only the start of a real one fails"

# A rule file with no ids (a working agreement) is named by its file name.
complete_ledger | sed 's/^F4\tcovered\t§R11\t.*/F4\tcovered\ttopic.md\tthe line is there and was not applied/' > "$ledger"
expect_check passed "covered by a rule file named by its file name passes"

complete_ledger | sed 's/^F4\tcovered\t§R11\t.*/F4\tcovered\tother.md\tno such file/' > "$ledger"
expect_check failed "covered by a file no rules dir holds fails"
expect_contains "it names the file" "F4: covered by other.md, which is not a rule file" "$last_output"

complete_ledger | sed 's/^F4\tcovered\t§R11\t.*/F4\tcovered\ttopicxmd\ta dot is not a wildcard/' > "$ledger"
expect_check failed "covered by a name that only matches as a pattern fails"

complete_ledger | sed 's/^F4\tcovered\t§R11\t.*/F4\tcovered\tchanges.md\ta Markdown file that holds no rules/' > "$ledger"
expect_check failed "covered by a Markdown file outside where rules live fails"
expect_contains "it names the file" "F4: covered by changes.md, which is not a rule file" "$last_output"

complete_ledger | sed 's/^F4\tcovered\t§R11\t.*/F4\tcovered\tSKILL.md\tan instructions file outside a rules folder/' > "$ledger"
expect_check passed "covered by an instructions file named as agents read it passes"

complete_ledger | sed 's/^F4\tcovered\t§R11\t.*/F4\tcovered\tc++.md\tpattern characters in a name are plain text/' > "$ledger"
expect_check passed "covered by a rule file whose name holds pattern characters passes"

complete_ledger | sed 's/^F4\tcovered\t§R11\t.*/F4\tcovered\tnotes.txt\tnot a Markdown rule file/' > "$ledger"
expect_check failed "covered by a file that is not a Markdown rule file fails"

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

# A lesson must be defined by the diff, not only cited by it; a covered rule must be defined.
printf -- '--- a/rules.md\n+++ b/rules.md\n+see §B13 for context\n+- **WF14.** The look-back lists\n' > "$work_dir/citing.diff"
complete_ledger > "$ledger"
output=$(bash "$script" check "$list" "$ledger" --diff "$work_dir/citing.diff" --rules "$rules_dir" 2>&1) && actual=passed || actual=failed
expect_eq "a diff that only cites a rule does not add it" failed "$actual"
expect_contains "it names the rule" "F2: lesson §B13 is not added by the lesson diff" "$output"
complete_ledger | sed 's/^F4\tcovered\t§R11\t.*/F4\tcovered\t§R17\tcited only/' > "$ledger"
expect_check failed "a rule only cited in the rules is not covered"
complete_ledger | sed 's/^F4\tcovered\t§R11\t.*/F4\tcovered\t§R12\tnot in Markdown/' > "$ledger"
expect_check failed "only Markdown rule files count"

# An empty field stays empty: the reason doesn't slide into the rule id.
complete_ledger | sed 's/^F2\tlesson\t§B13$/F2\tlesson\t\tsee F3/' > "$ledger"
expect_check failed "a lesson with an empty rule field fails"
expect_contains "it reads the field as empty" "F2: lesson names no rule id" "$last_output"

# Blank lines and a last line with no newline are read.
printf '%s' "$(complete_ledger | sed '3a\
')" > "$ledger"
{ cat "$list"; printf '\n'; } > "$work_dir/list-blank.tsv"
output=$(bash "$script" check "$work_dir/list-blank.tsv" "$ledger" --diff "$diff_file" --rules "$rules_dir" 2>&1) && actual=passed || actual=failed
expect_eq "a blank line in the list or ledger and no final newline still pass" passed "$actual"

# A diff with no added lines, and rules with no ids, report problems instead of stopping.
printf -- '--- a/rules.md\n+++ b/rules.md\n- removed §B9 line\n' > "$work_dir/removal.diff"
mkdir -p "$work_dir/no-rules" && printf 'nothing here\n' > "$work_dir/no-rules/readme.md"
complete_ledger > "$ledger"
output=$(bash "$script" check "$list" "$ledger" --diff "$work_dir/removal.diff" --rules "$work_dir/no-rules" 2>&1) && actual=passed || actual=failed
expect_eq "a removal-only diff and rules with no ids fail the ledger" failed "$actual"
expect_contains "it says the lesson isn't added" "F2: lesson §B13 is not added by the lesson diff" "$output"
expect_contains "it says the rule wasn't there" "F4: covered by §R11, which no rule file had" "$output"

# A --rules folder that isn't there has no rule files: the ledger is still checked item by item.
output=$(bash "$script" check "$list" "$ledger" --diff "$diff_file" --rules "$work_dir/gone" 2>&1) && actual=passed || actual=failed
expect_eq "a rules folder that does not exist fails the covered verdict" failed "$actual"
expect_contains "it still reports the item" "F4: covered by §R11, which no rule file had" "$output"

# Usage and unreadable inputs.
output=$(bash "$script" 2>&1 || true)
expect_contains "usage shows every verdict form" "<id> not-feedback <reason>" "$output"
expect_eq "check with no ledger is a usage error" 2 "$(bash "$script" check "$list" >/dev/null 2>&1; echo $?)"
expect_contains "a missing transcript says so" "cannot read $work_dir/none.jsonl" "$(bash "$script" list "$work_dir/none.jsonl" 2>&1 || true)"
expect_contains "a missing extra file says so" "cannot read $work_dir/none.txt" "$(bash "$script" list "$transcript" --extra "$work_dir/none.txt" 2>&1 || true)"
no_jq_bin=$work_dir/no-jq-bin
mkdir -p "$no_jq_bin"
ln -s "$(command -v basename)" "$no_jq_bin/basename"
expect_contains "list without jq says so" "needs jq" "$(PATH=$no_jq_bin "$BASH" "$script" list "$transcript" 2>&1 || true)"

expect_eq "a missing transcript is a usage error" 2 "$(bash "$script" list "$work_dir/none.jsonl" >/dev/null 2>&1; echo $?)"
expect_eq "an unknown command is a usage error" 2 "$(bash "$script" tally >/dev/null 2>&1; echo $?)"

finish
