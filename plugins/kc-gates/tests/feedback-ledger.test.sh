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
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t4","content":"Your questions have been answered: \"Round when?\"=\"At the total\". You can now continue with these answers in mind."}]}}
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
answer\tYour questions have been answered: "Round when?"="At the total". You can now continue with these answers in mind.
interrupt\t[Request interrupted by user for tool use]
qa-rows.txt\tRow 1: total shows 0 for a free order
qa-rows.txt\tRow 2: tax missing'
expect_eq "list finds each kind of feedback, in order, and skips reminders, notifications, summaries, skill text, queued shell commands and tool errors" "$expected" "$(cut -f2,3 "$list")"
expect_eq "items are numbered F1 onwards" "F1 F11" "$(cut -f1 "$list" | sed -n '1p;$p' | tr '\n' ' ' | sed 's/ $//')"

# check: a lesson diff that adds §B13 and WF14, and rule files that hold §R11 and **QA1.**
diff_file=$work_dir/lesson.diff
printf -- '--- a/rules.md\n+++ b/rules.md\n+- [ ] §B13 A new kind of actor\n+- **WF14.** The look-back lists\n- removed §B9 line\n--- a/plugin/tests/rules.test.sh\n+++ b/plugin/tests/rules.test.sh\n+echo held\n' > "$diff_file"
rules_dir=$work_dir/repo
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
  printf 'F4\tcovered\t§R11\trule had no box for one-line helpers\tlesson:§B13\n'
  printf 'F5\tone-off\tnaming call for this file\n'
  printf 'F6\tnot-feedback\tthe rejected call was a duplicate\n'
  printf 'F7\tcovered\tQA1\tsheet rows never counted\tno-change:the box names sheet rows; it was skipped\n'
  printf 'F8\tnot-feedback\tan interrupt to redirect, its message is F4\n'
  printf 'F9\tlesson\tWF14\n'
  printf 'F10\tone-off\ttax line is this sheet only\n'
  printf 'F11\tone-off\twhen to round is this order page only\n'
}
ledger=$work_dir/ledger.tsv
# The tagged fields every lesson record carries (class, examples, mechanism, proof).
record_fields=$'class:a name that hides what a value is\texamples:an order total; a storefront slug\tmechanism:check\tproof:plugin/tests/rules.test.sh'
# Appends them to each lesson line that names a rule, and to each covered line with a lesson: catch.
add_record_fields() {
  awk -F'\t' -v OFS='\t' -v fields="$record_fields" '
    {
      is_lesson_line = ($2 == "lesson" && NF >= 3)
      is_lesson_catch_line = ($2 == "covered" && $5 ~ /^lesson:./)
    }
    is_lesson_line || is_lesson_catch_line { print $0 OFS fields; next } { print }'
}
# The complete ledger with F4's covered verdict replaced by the given fields, tab-joined.
ledger_with_covered_f4() {
  local fields
  fields=$(printf '\t%s' "$@")
  complete_ledger | awk -v line="F4\tcovered$fields" -F'\t' '$1 == "F4" { print line; next } { print }' | add_record_fields > "$ledger"
}
run_check() { bash "$script" check "$list" "$ledger" --diff "$diff_file" --rules "$rules_dir" 2>&1; }
expect_check() {
  local expectation=$1 label=$2 output actual=passed
  output=$(run_check) || actual=failed
  expect_eq "$label" "$expectation" "$actual"
  last_output=$output
}

complete_ledger | add_record_fields > "$ledger"
expect_check passed "a ledger with a verdict for every item passes"
expect_contains "it counts the items" "11 item(s), each with a verdict" "$last_output"

complete_ledger | sed '/^F5/d' | add_record_fields > "$ledger"
expect_check failed "an item with no verdict fails"
expect_contains "it names the item" "F5: no verdict in the ledger" "$last_output"

{ complete_ledger; printf 'F2\tone-off\tagain\n'; } | add_record_fields > "$ledger"
expect_check failed "an item given two verdicts fails"
expect_contains "it names the item" "F2: listed twice in the ledger" "$last_output"

{ complete_ledger; printf 'F12\tone-off\tno such item\n'; } | add_record_fields > "$ledger"
expect_check failed "a verdict for an item not on the list fails"
expect_contains "it names the item" "F12: not on the feedback list" "$last_output"

complete_ledger | sed 's/^F2\tlesson\t§B13$/F2\tlesson\t§B9/' | add_record_fields > "$ledger"
expect_check failed "a lesson whose rule the diff only removes fails"
expect_contains "it names the rule" "F2: lesson §B9 is not added by the lesson diff" "$last_output"

complete_ledger | sed 's/^F2\tlesson\t§B13$/F2\tlesson\t§B1/' | add_record_fields > "$ledger"
expect_check failed "a lesson id that is only the start of an added id fails"

complete_ledger | sed 's/^F3\tlesson\tB13,WF14$/F3\tlesson\tB13,WF15/' | add_record_fields > "$ledger"
expect_check failed "every id of a lesson must be added, not only the first"
expect_contains "it names the missing one" "F3: lesson WF15 is not added by the lesson diff" "$last_output"

complete_ledger | sed 's/^F9\tlesson\tWF14$/F9\tlesson\trules.md/' | add_record_fields > "$ledger"
expect_check passed "a lesson may name the rule file its diff changes, for a file with no ids"
complete_ledger | sed 's/^F9\tlesson\tWF14$/F9\tlesson\tagreement.md/' | add_record_fields > "$ledger"
expect_check failed "a lesson naming a file the diff doesn't change fails"
expect_contains "it names the file" "F9: lesson agreement.md is not a file the lesson diff changes" "$last_output"
complete_ledger | sed 's/^F9\tlesson\tWF14$/F9\tlesson\tr.les.md/' | add_record_fields > "$ledger"
expect_check failed "a file name is matched literally, not as a pattern"

complete_ledger | sed 's/^F2\tlesson\t§B13$/F2\tlesson/' | add_record_fields > "$ledger"
expect_check failed "a lesson with no rule id fails"
expect_contains "it says so" "F2: lesson names no rule id" "$last_output"

ledger_with_covered_f4 '§R12' 'no box' 'no-change:x'
expect_check failed "covered by a rule no rule file has fails"
expect_contains "it names the rule" "F4: covered by §R12, which no rule file had" "$last_output"

ledger_with_covered_f4 '§R1' 'no box' 'no-change:x'
expect_check failed "covered by an id that is only the start of a real one fails"

# A rule file with no ids (a working agreement) is named by its file name.
ledger_with_covered_f4 'topic.md' 'the line is there and was not applied' 'no-change:x'
expect_check passed "covered by a rule file named by its file name passes"

ledger_with_covered_f4 'other.md' 'no such file' 'no-change:x'
expect_check failed "covered by a file no rules dir holds fails"
expect_contains "it names the file" "F4: covered by other.md, which is not a rule file" "$last_output"

ledger_with_covered_f4 'topicxmd' 'a dot is not a wildcard' 'no-change:x'
expect_check failed "covered by a name that only matches as a pattern fails"

ledger_with_covered_f4 'changes.md' 'a Markdown file that holds no rules' 'no-change:x'
expect_check failed "covered by a Markdown file outside where rules live fails"
expect_contains "it names the file" "F4: covered by changes.md, which is not a rule file" "$last_output"

ledger_with_covered_f4 'SKILL.md' 'an instructions file outside a rules folder' 'no-change:x'
expect_check passed "covered by an instructions file named as agents read it passes"

# A --rules dir that is itself a rules folder holds its rule files at its top.
mkdir -p "$work_dir/home/.claude" && printf 'house rules\n' > "$work_dir/home/.claude/house.md"
ledger_with_covered_f4 'topic.md' 'a rule file at the top of a rules folder' 'no-change:x'
output=$(bash "$script" check "$list" "$ledger" --diff "$diff_file" --rules "$rules_dir/rules" --rules "$rules_dir" 2>&1) && actual=passed || actual=failed
expect_eq "covered by a file at the top of a dir named rules passes" passed "$actual"
output=$(cd "$rules_dir/rules" && bash "$script" check "$list" "$ledger" --diff "$diff_file" --rules . --rules "$rules_dir" 2>&1) && actual=passed || actual=failed
expect_eq "covered by a file at the top of the current folder, a rules folder, passes" passed "$actual"
ledger_with_covered_f4 'house.md' 'a rule file at the top of a .claude folder' 'no-change:x'
output=$(bash "$script" check "$list" "$ledger" --diff "$diff_file" --rules "$work_dir/home/.claude/" --rules "$rules_dir" 2>&1) && actual=passed || actual=failed
expect_eq "covered by a file at the top of a dir named .claude passes" passed "$actual"

ledger_with_covered_f4 'c++.md' 'pattern characters in a name are plain text' 'no-change:x'
expect_check passed "covered by a rule file whose name holds pattern characters passes"

ledger_with_covered_f4 'notes.txt' 'not a Markdown rule file' 'no-change:x'
expect_check failed "covered by a file that is not a Markdown rule file fails"

ledger_with_covered_f4 '§R11'
expect_check failed "covered with no reason it was still missed fails"
expect_contains "it asks why" "F4: covered by §R11 says nothing on why it was still missed" "$last_output"

# A rule that existed and was still missed says what catches the miss now.
ledger_with_covered_f4 '§R11' 'no box for it'
expect_check failed "covered with nothing on what catches the miss now fails"
expect_contains "it asks what catches it" "F4: covered by §R11 says nothing on what catches the miss now" "$last_output"
ledger_with_covered_f4 '§R11' 'no box for it' 'no-change:'
expect_check failed "covered with an empty no-change reason fails"
ledger_with_covered_f4 '§R11' 'no box for it' 'lesson:'
expect_check failed "covered with an empty lesson id fails"
expect_contains "it asks what catches it" "F4: covered by §R11 says nothing on what catches the miss now" "$last_output"
ledger_with_covered_f4 '§R11' 'no box for it' 'lesson:ZZ9'
expect_check failed "covered caught by a rule the lesson diff doesn't add fails"
ledger_with_covered_f4 '§R11' 'no box for it' 'lesson:B13,WF14'
expect_check passed "covered caught by rules the lesson diff adds passes"
ledger_with_covered_f4 '§R11' 'no box for it' 'skipped'
expect_check failed "covered with a catch that is neither lesson: nor no-change: fails"

ledger_with_covered_f4
expect_check failed "covered with no rule id fails"
expect_contains "it says so" "F4: covered names no rule id" "$last_output"

complete_ledger | sed 's/^F5\tone-off\t.*/F5\tone-off/' | add_record_fields > "$ledger"
expect_check failed "a one-off with no reason fails"
expect_contains "it asks for the reason" "F5: one-off gives no reason" "$last_output"

complete_ledger | sed 's/^F1\tnot-feedback\t.*/F1\tnot-feedback/' | add_record_fields > "$ledger"
expect_check failed "not-feedback with no reason fails"

complete_ledger | sed 's/^F5\tone-off\t/F5\tskipped\t/' | add_record_fields > "$ledger"
expect_check failed "an unknown verdict fails"
expect_contains "it lists the verdicts" "'skipped' is not lesson, covered, one-off or not-feedback" "$last_output"

complete_ledger | add_record_fields > "$ledger"
output=$(bash "$script" check "$list" "$ledger" --rules "$rules_dir" 2>&1) && actual=passed || actual=failed
expect_eq "with no lesson diff given, no lesson can be shown" failed "$actual"

# A lesson must be defined by the diff, not only cited by it; a covered rule must be defined.
printf -- '--- a/rules.md\n+++ b/rules.md\n+see §B13 for context\n+- **WF14.** The look-back lists\n' > "$work_dir/citing.diff"
complete_ledger | add_record_fields > "$ledger"
output=$(bash "$script" check "$list" "$ledger" --diff "$work_dir/citing.diff" --rules "$rules_dir" 2>&1) && actual=passed || actual=failed
expect_eq "a diff that only cites a rule does not add it" failed "$actual"
expect_contains "it names the rule" "F2: lesson §B13 is not added by the lesson diff" "$output"
ledger_with_covered_f4 '§R17' 'cited only' 'no-change:x'
expect_check failed "a rule only cited in the rules is not covered"
ledger_with_covered_f4 '§R12' 'not in Markdown' 'no-change:x'
expect_check failed "only Markdown rule files count"

# An empty field stays empty: the reason doesn't slide into the rule id.
complete_ledger | sed 's/^F2\tlesson\t§B13$/F2\tlesson\t\tsee F3/' | add_record_fields > "$ledger"
expect_check failed "a lesson with an empty rule field fails"
expect_contains "it reads the field as empty" "F2: lesson names no rule id" "$last_output"

# Blank lines and a last line with no newline are read.
printf '%s' "$(complete_ledger | add_record_fields | sed '3a\
')" > "$ledger"
{ cat "$list"; printf '\n'; } > "$work_dir/list-blank.tsv"
output=$(bash "$script" check "$work_dir/list-blank.tsv" "$ledger" --diff "$diff_file" --rules "$rules_dir" 2>&1) && actual=passed || actual=failed
expect_eq "a blank line in the list or ledger and no final newline still pass" passed "$actual"

# A diff with no added lines, and rules with no ids, report problems instead of stopping.
printf -- '--- a/rules.md\n+++ b/rules.md\n- removed §B9 line\n' > "$work_dir/removal.diff"
mkdir -p "$work_dir/no-rules" && printf 'nothing here\n' > "$work_dir/no-rules/readme.md"
complete_ledger | add_record_fields > "$ledger"
output=$(bash "$script" check "$list" "$ledger" --diff "$work_dir/removal.diff" --rules "$work_dir/no-rules" 2>&1) && actual=passed || actual=failed
expect_eq "a removal-only diff and rules with no ids fail the ledger" failed "$actual"
expect_contains "it says the lesson isn't added" "F2: lesson §B13 is not added by the lesson diff" "$output"
expect_contains "it says the rule wasn't there" "F4: covered by §R11, which no rule file had" "$output"

# A --rules folder that isn't there has no rule files: the ledger is still checked item by item.
output=$(bash "$script" check "$list" "$ledger" --diff "$diff_file" --rules "$work_dir/gone" 2>&1) && actual=passed || actual=failed
expect_eq "a rules folder that does not exist fails the covered verdict" failed "$actual"
expect_contains "it still reports the item" "F4: covered by §R11, which no rule file had" "$output"

# Lesson records: class, examples, mechanism, why-not-higher and proof, each checked on its own.
get_record_without() { printf '%s' "$record_fields" | tr '\t' '\n' | grep -v "^$1:" | paste -sd '\t' -; }
build_ledger_with_f2_fields() {
  complete_ledger | awk -F'\t' -v OFS='\t' -v fields="$1" '$1 == "F2" { print $0 OFS fields; next } { print }' | add_record_fields_except_f2 > "$ledger"
}
add_record_fields_except_f2() {
  awk -F'\t' -v OFS='\t' -v fields="$record_fields" '
    {
      is_not_f2 = ($1 != "F2")
      is_lesson_line = ($2 == "lesson" && NF >= 3)
      is_lesson_catch_line = ($2 == "covered" && $5 ~ /^lesson:./)
    }
    is_not_f2 && (is_lesson_line || is_lesson_catch_line) { print $0 OFS fields; next } { print }'
}
for missing_field in class examples mechanism proof; do
  build_ledger_with_f2_fields "$(get_record_without "$missing_field")"
  expect_check failed "a lesson with no $missing_field: field fails"
  expect_contains "it names the item and the field" "F2: lesson is missing $missing_field:" "$last_output"
  build_ledger_with_f2_fields "$(get_record_without "$missing_field")"$'\t'"$missing_field:"
  expect_check failed "a lesson with an empty $missing_field: field fails"
  expect_contains "it names the item and the empty field" "F2: lesson $missing_field: is empty" "$last_output"
done
build_ledger_with_f2_fields "$(get_record_without examples)"$'\texamples:only one case'
expect_check failed "a lesson with one example fails"
expect_contains "it says a lesson needs 2 unlike cases" "F2: lesson examples: has one example; a lesson needs 2 unlike cases" "$last_output"
build_ledger_with_f2_fields "$(get_record_without examples)"$'\texamples:a case; ; another'
expect_check failed "a lesson with an empty example fails"
expect_contains "it names the empty example" "F2: lesson examples: has an empty example" "$last_output"
build_ledger_with_f2_fields "$(get_record_without examples)"$'\texamples:a case; another case; a third'
expect_check passed "a lesson with three examples passes"
build_ledger_with_f2_fields "$(get_record_without mechanism)"$'\tmechanism:memo'
expect_check failed "a mechanism that is not on the layer ladder fails"
expect_contains "it names the mechanism" "F2: lesson mechanism:memo is not one of check, guard, path-rule, skill, always-on" "$last_output"
build_ledger_with_f2_fields "$(get_record_without mechanism)"$'\tmechanism:guard'
expect_check failed "a guard with no why-not-higher fails"
expect_contains "it asks for why-not-higher" "F2: lesson is missing why-not-higher:" "$last_output"
build_ledger_with_f2_fields "$(get_record_without mechanism)"$'\tmechanism:guard\twhy-not-higher:the mistake happens at commit time, outside any test'
expect_check passed "a guard with why-not-higher passes"
build_ledger_with_f2_fields "$(get_record_without mechanism)"$'\tmechanism:check'
expect_check passed "a check needs no why-not-higher"
complete_ledger | add_record_fields | awk -F'\t' '$1 == "F4" { print "F4\tcovered\t§R11\tno box for it\tlesson:B13\tclass:a missed box"; next } { print }' > "$ledger"
expect_check failed "a covered line whose catch is a lesson: needs the record fields too"
expect_contains "it names what is missing" "F4: lesson is missing examples:" "$last_output"
ledger_with_covered_f4 '§R11' 'no box for it' 'no-change:the box covers it'
expect_check passed "a covered line with a no-change: catch needs no record fields"

# Client terms: a --public-diff's added lines name none of the terms; a plain --diff is not checked.
terms_file=$work_dir/terms.txt
printf '# private list\n\nAcmeCorp\r\nwidget shop\n' > "$terms_file"
public_diff=$work_dir/public.diff
printf -- '--- a/rules.md\n+++ b/rules.md\n+- [ ] §B13 A new kind of actor\n+- **WF14.** Seen at the acmecorp checkout\n+Reading acmecorps is fine, not a whole word\n+# private list\n- removed AcmeCorp line\n--- a/plugin/tests/rules.test.sh\n+++ b/plugin/tests/rules.test.sh\n+echo held widget shop\n' > "$public_diff"
complete_ledger | add_record_fields > "$ledger"
output=$(bash "$script" check "$list" "$ledger" --public-diff "$public_diff" --terms "$terms_file" --rules "$rules_dir" 2>&1) && actual=passed || actual=failed
expect_eq "a client term in a --public-diff fails" failed "$actual"
expect_contains "it names the diff, the line and the term" "$public_diff: line 4 names client term \"AcmeCorp\"" "$output"
expect_contains "a multi-word term is matched" "$public_diff: line 10 names client term \"widget shop\"" "$output"
expect_eq "a term inside a longer word and a removed line are not hits" 2 "$(printf '%s\n' "$output" | grep -c 'names client term')"
output=$(bash "$script" check "$list" "$ledger" --diff "$public_diff" --terms "$terms_file" --rules "$rules_dir" 2>&1) && actual=passed || actual=failed
expect_eq "the same terms in a plain --diff pass" passed "$actual"
output=$(KC_CLIENT_TERMS=$work_dir/no-such-terms.txt bash "$script" check "$list" "$ledger" --public-diff "$public_diff" --rules "$rules_dir" 2>&1) && actual=passed || actual=failed
expect_eq "with no terms file the client-term check is skipped" passed "$actual"
output=$(KC_CLIENT_TERMS=$terms_file bash "$script" check "$list" "$ledger" --public-diff "$public_diff" --rules "$rules_dir" 2>&1) && actual=passed || actual=failed
expect_eq "KC_CLIENT_TERMS names the default terms file" failed "$actual"
expect_eq "an unreadable --terms file is a usage error" 2 "$(bash "$script" check "$list" "$ledger" --public-diff "$public_diff" --terms "$work_dir/none.txt" --rules "$rules_dir" >/dev/null 2>&1; echo $?)"
printf -- '--- a/rules.md\n+++ b/rules.md\n+- [ ] §B13 A new kind of actor\n+- **WF14.** The look-back lists\n--- a/plugin/tests/rules.test.sh\n+++ b/plugin/tests/rules.test.sh\n+echo held\n' > "$work_dir/clean-public.diff"
output=$(bash "$script" check "$list" "$ledger" --public-diff "$work_dir/clean-public.diff" --terms "$terms_file" --rules "$rules_dir" 2>&1) && actual=passed || actual=failed
expect_eq "a --public-diff with no term counts for rule ids and check files, and passes" passed "$actual"

# Usage and unreadable inputs.
output=$(bash "$script" 2>&1 || true)
expect_contains "usage shows every verdict form" "<id> not-feedback <reason>" "$output"
expect_contains "usage shows the lesson record fields" "why-not-higher:<why no higher layer holds it>" "$output"
expect_contains "usage shows --public-diff" "[--public-diff <file>]..." "$output"
expect_eq "check with no ledger is a usage error" 2 "$(bash "$script" check "$list" >/dev/null 2>&1; echo $?)"
expect_contains "a missing transcript says so" "cannot read $work_dir/none.jsonl" "$(bash "$script" list "$work_dir/none.jsonl" 2>&1 || true)"
expect_contains "a missing extra file says so" "cannot read $work_dir/none.txt" "$(bash "$script" list "$transcript" --extra "$work_dir/none.txt" 2>&1 || true)"
no_jq_bin=$work_dir/no-jq-bin
mkdir -p "$no_jq_bin"
ln -s "$(command -v basename)" "$no_jq_bin/basename"
expect_contains "list without jq says so" "needs jq" "$(PATH=$no_jq_bin "$BASH" "$script" list "$transcript" 2>&1 || true)"

expect_eq "a missing transcript is a usage error" 2 "$(bash "$script" list "$work_dir/none.jsonl" >/dev/null 2>&1; echo $?)"
expect_eq "an unknown command is a usage error" 2 "$(bash "$script" tally >/dev/null 2>&1; echo $?)"

# Lessons are checks first, with no prose-only escape: a diff with no check file fails, whatever the line says.
prose_diff=$work_dir/prose.diff
printf -- '--- a/rules.md\n+++ b/rules.md\n+- [ ] §B13 A new kind of actor\n+- **WF14.** The look-back lists\n' > "$prose_diff"
run_prose_check() { output=$(bash "$script" check "$list" "$ledger" --diff "$prose_diff" --rules "$rules_dir" 2>&1) && actual=passed || actual=failed; }
complete_ledger | add_record_fields > "$ledger"
run_prose_check
expect_eq "a lesson whose diff adds only rule text fails" failed "$actual"
expect_contains "it says the lesson is prose with no check" "F2: lesson is prose with no check" "$output"
complete_ledger | sed -E 's/^(F2\tlesson\t§B13)$/\1\tprose-only: no script can tell whether a name is honest/; s/^(F3\tlesson\tB13,WF14)$/\1\tprose-only: judgment/; s/^(F9\tlesson\tWF14)$/\1\tprose-only: judgment/; s/^(F4\tcovered\t§R11\t[^\t]*\tlesson:§B13)$/\1\tprose-only: judgment/' | add_record_fields > "$ledger"
run_prose_check
expect_eq "a prose-only field with a reason no longer passes a prose diff" failed "$actual"
expect_contains "it still says the lesson is prose with no check" "F2: lesson is prose with no check" "$output"
expect_contains "a covered line's lesson: catch needs a check too" "F4: lesson is prose with no check" "$output"
for held_path in plugin/scripts/check.sh plugin/hooks/hooks.json plugin/evals/case/setup.sh src/total.test.ts biome.json .github/workflows/ci.yml; do
  printf -- '--- a/rules.md\n+++ b/rules.md\n+- [ ] §B13 A new kind of actor\n+- **WF14.** The look-back lists\n--- a/%s\n+++ b/%s\n+x\n' "$held_path" "$held_path" > "$prose_diff"
  complete_ledger | add_record_fields > "$ledger"
  run_prose_check
  expect_eq "a diff that changes $held_path holds the lessons" passed "$actual"
done

# --- held-by: the lesson's test must pass at HEAD and fail with the lesson's non-test changes reverted ---
held_repo=$work_dir/held-repo
mkdir -p "$held_repo/tests"
git init -q "$held_repo"
run_git_in_held_repo() { git -C "$held_repo" -c user.email=t@example.com -c user.name=t "$@"; }
printf 'echo 1\n' > "$held_repo/tool.sh"
run_git_in_held_repo add -A && run_git_in_held_repo commit -q -m base
run_git_in_held_repo branch base
printf 'echo 2\n' > "$held_repo/tool.sh"
# shellcheck disable=SC2016 # the fixture tests are written literally
printf '[ "$(bash "$(dirname "$0")/../tool.sh")" = 2 ]\n' > "$held_repo/tests/good.test.sh"
# shellcheck disable=SC2016
printf 'bash "$(dirname "$0")/../tool.sh" > /dev/null\n' > "$held_repo/tests/vacuous.test.sh"
# shellcheck disable=SC2016
printf '[ "$(bash "$(dirname "$0")/../tool.sh")" = 3 ]\n' > "$held_repo/tests/broken.test.sh"
# shellcheck disable=SC2016
printf '[ "$1" = case-a ]\n' > "$held_repo/tests/cased.test.sh"
# A test that reads a helper the lesson also changes: the helper is a test file, so it stays.
mkdir -p "$held_repo/tests/lib" "$held_repo/checks"
printf 'true\n' > "$held_repo/tests/lib/helper.sh"
# shellcheck disable=SC2016
printf '. "$(dirname "$0")/lib/helper.sh" || exit 1\nbash "$(dirname "$0")/../tool.sh" > /dev/null\n' > "$held_repo/tests/helped.test.sh"
# A held check outside any tests folder: it is the check, so it stays too.
# shellcheck disable=SC2016
printf 'bash "$(dirname "$0")/../tool.sh" > /dev/null\n' > "$held_repo/checks/vacuous.sh"
run_git_in_held_repo add -A && run_git_in_held_repo commit -q -m lesson
held_diff=$work_dir/held.diff
printf -- '--- a/rules.md\n+++ b/rules.md\n+- [ ] §B13 A new kind of actor\n--- a/tool.sh\n+++ b/tool.sh\n+echo 2\n' > "$held_diff"
for held_test in good vacuous broken cased helped; do printf -- '--- /dev/null\n+++ b/tests/%s.test.sh\n+x\n' "$held_test" >> "$held_diff"; done
printf -- '--- /dev/null\n+++ b/tests/lib/helper.sh\n+true\n--- /dev/null\n+++ b/checks/vacuous.sh\n+x\n' >> "$held_diff"
printf 'F1\ttyped\tdon'"'"'t do that\n' > "$work_dir/held-list.tsv"
held_rules=$work_dir/held-rules; mkdir -p "$held_rules"
run_held() {
  printf 'F1\tlesson\t§B13\t%s\t%s\n' "$1" "$record_fields" > "$work_dir/held-ledger.tsv"
  held_output=$(bash "$script" check "$work_dir/held-list.tsv" "$work_dir/held-ledger.tsv" --diff "$held_diff" --rules "$held_rules" --repo "$held_repo" --base base 2>&1) && held_actual=passed || held_actual=failed
}
run_held 'held-by:tests/good.test.sh'
expect_eq "held-by: a test that fails with the change reverted passes" passed "$held_actual"
run_held 'held-by:tests/vacuous.test.sh'
expect_eq "held-by: a test that still passes with the change reverted fails" failed "$held_actual"
expect_contains "it says the test does not block the mistake" "F1: held-by tests/vacuous.test.sh passes at HEAD and still passes with the lesson's non-test changes reverted" "$held_output"
run_held 'held-by:tests/broken.test.sh'
expect_eq "held-by: a test that fails at HEAD fails" failed "$held_actual"
expect_contains "it says the test fails at HEAD" "F1: held-by tests/broken.test.sh fails at HEAD" "$held_output"
run_held 'prose-only: judgment'
expect_eq "held-by: a lesson with no held-by field fails" failed "$held_actual"
expect_contains "it asks for the field" "F1: lesson has no held-by" "$held_output"
run_held 'held-by:tests/other.test.sh'
expect_eq "held-by: a test the lesson diff does not change fails" failed "$held_actual"
expect_contains "it names the test" "F1: held-by tests/other.test.sh is not a test the lesson diff adds or changes" "$held_output"
# The case name reaches the test as $1; the test ignores tool.sh, so it passes with the change reverted too.
run_held 'held-by:tests/cased.test.sh::case-a'
expect_eq "held-by: a case test that passes with the change reverted fails as vacuous" failed "$held_actual"
expect_contains "the case test is run, and caught as vacuous" "tests/cased.test.sh passes at HEAD and still passes" "$held_output"
run_held 'held-by:'
expect_eq "held-by: an empty held-by field fails" failed "$held_actual"
expect_contains "it says held-by names no test file" "F1: held-by names no test file" "$held_output"
run_held 'held-by:tests/helped.test.sh'
expect_eq "held-by: another test file the lesson changes is not reverted, so a test reading it still fails as vacuous" failed "$held_actual"
expect_contains "the helper test is caught as vacuous, not failed by a missing helper" "tests/helped.test.sh passes at HEAD and still passes" "$held_output"
run_held 'held-by:checks/vacuous.sh'
expect_eq "held-by: the held file is not reverted even outside a tests folder, so it fails as vacuous" failed "$held_actual"
expect_contains "the held file is caught as vacuous, not failed by being reverted away" "checks/vacuous.sh passes at HEAD and still passes" "$held_output"

# --repo and --base go together: one without the other is a usage error.
status=0
bash "$script" check "$work_dir/held-list.tsv" "$work_dir/held-ledger.tsv" --repo "$held_repo" > /dev/null 2>&1 || status=$?
expect_eq "--repo without --base is a usage error" 2 "$status"
status=0
bash "$script" check "$work_dir/held-list.tsv" "$work_dir/held-ledger.tsv" --base base > /dev/null 2>&1 || status=$?
expect_eq "--base without --repo is a usage error" 2 "$status"

finish
