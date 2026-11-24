#!/usr/bin/env bash
# Lists every piece of feedback a session received, and checks the look-back's ledger of them, so
# the look-back (the working agreement's "Order of work on a task", step 6) starts from a list
# instead of from what the agent remembers. A look-back written from memory keeps the corrections
# that were memorable and drops the rest, the same miss as a review that never lists its units.
#
#   feedback-ledger.sh list <transcript.jsonl> [--extra <file>]...
#       Prints one tab-separated line per item: <id> <source> <text>, ids F1, F2, ... in order.
#       From the session transcript (Claude Code keeps it at
#       ~/.claude/projects/<cwd with / as ->/<session id>.jsonl) it lists each message the
#       person typed, including ones typed while a turn ran (the task itself too, which the
#       ledger marks not-feedback); each answer to a question asked with a choice tool; each tool
#       call the person rejected; each interrupt; and each message another session relayed. Each
#       non-empty line of an --extra file (review comments, QA rows, one per line) is one item,
#       its source the file's name. Listing only: nothing is judged here.
#
#   feedback-ledger.sh check <list> <ledger> [--diff <file>]... [--public-diff <file>]... [--terms <file>]
#                            [--rules <dir>]... [--repo <dir> --base <ref>]
#       Fails unless the ledger gives every listed item one verdict, as a tab-separated line:
#         <id> lesson <rule id>[,<rule id>]...       a --diff (the lesson PR) adds a line that
#                                                     defines each id; a rule file with no ids (a
#                                                     working agreement) is named by its file
#                                                     name, which a --diff changes
#         <id> covered <rule id> <why it was missed> <what catches it now>
#                                                     a --rules dir, the rules as they were before
#                                                     the lesson PR, defines the id; a rule file
#                                                     with no ids is named by its file name, which
#                                                     a --rules dir holds in a `rules` or `.claude`
#                                                     folder (the dir itself may be one), or as
#                                                     CLAUDE.md, AGENTS.md or SKILL.md. A rule
#                                                     that existed and was still missed needs a
#                                                     box or a trigger, so the last field is
#                                                     `lesson:<rule id>[,<rule id>]...`, checked as
#                                                     a lesson is, or `no-change:<why the rule as
#                                                     written would have caught it>`
#         <id> one-off <reason>
#         <id> not-feedback <reason>
#       Future rules are a check that blocks the mistake: a `lesson` (and a `covered` line's
#       `lesson:` catch) passes only when a --diff adds or changes a script, hook, test, eval,
#       CI workflow or lint-rule file. There is no prose-only escape; a lesson no check can hold
#       is not written as a rule.
#       With --repo (the lesson PR's checkout, at its head) and --base (the ref it branches from),
#       a lesson must also prove its check blocks the mistake: its line carries a field
#       `held-by:<test file>[::<case>]` (after the rule id; on a `covered` line, after the
#       catch), naming a test the --diff adds or changes. The check runs that test at HEAD (it
#       must pass), then again in a throwaway copy of HEAD with the lesson PR's non-test changes
#       put back to --base (it must fail), and reports which went wrong: a test that fails at
#       HEAD, or one that still passes with the change reverted, holds nothing. The test is run
#       as `bash <file> [<case>]` from the checkout's root; the case, when given, is its first
#       argument. Without --repo a lesson is held when the diff changes any check file.
#       Every lesson record (a `lesson` line, and a `covered` line whose catch is `lesson:...`)
#       also states what it is a lesson of, as tab-separated tagged fields after the fields
#       above, in any order (each missing or empty one is its own problem):
#         class:<one sentence naming the class of mistake>
#         examples:<a>; <b>[; <c>]       two or more unlike cases the rule catches, split on "; "
#         mechanism:<check|guard|path-rule|skill|always-on>
#                                        the layer the lesson sits at, as kc-look-back's "Placing
#                                        a lesson by layer" ladder names them
#         why-not-higher:<why no higher layer holds it>
#                                        required unless the mechanism is check, the top layer
#         proof:<test file, eval, script or box id>
#                                        what fails without the lesson
#       A --public-diff is a lesson diff like --diff (it counts for rule ids and check files)
#       whose added lines must also name no client term: a word of --terms <file> (default
#       ${KC_CLIENT_TERMS:-$HOME/.claude/kc-client-terms.txt}), one term per line, blank and #
#       lines ignored, matched case-insensitively as whole words. Each hit is reported as
#       "<diff file>: line N names client term". With no terms file the check is skipped. The
#       terms are private: a --diff (a lesson diff for a private repo) is never checked for them.
#       A rule id is written as the rules write it (`§B13`, `B13`, `WF14`). A line defines it when
#       it starts with it, after any list marker, checkbox or heading marks (`- [ ] §B13 ...`,
#       `### §B13. ...`, `- **B13.** ...`); a line that only cites it does not. --rules defaults
#       to the current directory, and only its Markdown files are read.
#
# Needs jq for `list`. Exits 0 when the ledger is complete, 1 with one line per problem, 2 on
# usage errors.
set -euo pipefail

script_name=$(basename "$0")
usage() {
  awk '/^#   feedback-ledger.sh/ { show = 1 } /^# Needs jq/ { exit } show { sub(/^# ?/, ""); print }' "$0" >&2
  exit 2
}

# Turns a JSONL transcript into "<source>\t<text>" lines, in order.
list_transcript() {
  jq -L "$(dirname "$0")/lib" -r '
    include "typed-message";
    def oneline: gsub("[\t\r\n]+"; " ") | sub("^ +"; "") | sub(" +$"; "");
    if .type == "user" and (.isCompactSummary | not) then
      if (.isMeta == true) then
        (message_texts[] | select(test("^Another Claude session sent a message")) | "session\t" + oneline)
      else
        (typed_texts |
          if test("^\\[Request interrupted") then "interrupt\t" + oneline else "typed\t" + oneline end),
        (.message.content | if type == "array" then .[] else empty end
          | select(.type == "tool_result")
          | (.content | if type == "array" then map(.text? // "") | join(" ") else tostring end) as $text
          | if ($text | test("^The user answered|^User has answered|^Your questions have been answered")) then "answer\t" + ($text | oneline)
            elif ($text | test("^The user doesn.t want to proceed with this tool use")) then "rejected\t" + ($text | oneline)
            else empty end)
      end
    elif .type == "attachment" and .attachment.type == "queued_command" and .attachment.commandMode == "prompt" then
      (.attachment.prompt | if type == "array" then [.[] | select(.type == "text") | .text] else [tostring] end
        | .[] | select(is_not_typed | not) | "typed\t" + oneline)
    else empty end
  ' "$1"
}

run_list() {
  local transcript="" extra_feedback_files=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --extra) [ "$#" -ge 2 ] || usage; extra_feedback_files+=("$2"); shift 2 ;;
      -*) usage ;;
      *) [ -z "$transcript" ] || usage; transcript=$1; shift ;;
    esac
  done
  [ -n "$transcript" ] || usage
  command -v jq >/dev/null || { echo "$script_name: needs jq" >&2; exit 2; }
  [ -r "$transcript" ] || { echo "$script_name: cannot read $transcript" >&2; exit 2; }
  local extra_feedback_file
  for extra_feedback_file in ${extra_feedback_files[@]+"${extra_feedback_files[@]}"}; do
    [ -r "$extra_feedback_file" ] || { echo "$script_name: cannot read $extra_feedback_file" >&2; exit 2; }
  done
  {
    list_transcript "$transcript"
    for extra_feedback_file in ${extra_feedback_files[@]+"${extra_feedback_files[@]}"}; do
      awk -v source="$(basename "$extra_feedback_file")" 'NF { gsub(/\t/, " "); print source "\t" $0 }' "$extra_feedback_file"
    done
  } | awk -F'\t' '{ printf "F%d\t%s\n", NR, $0 }'
}

# True when a line of <file> defines <rule id>: the line starts with `§ID` or `**ID.**`, after any
# list marker, checkbox or heading marks, and the id is not the start of a longer one.
defines_rule_id() {
  local rule_id=${1#§} file=$2
  grep -Eq "^[[:space:]]*(-[[:space:]]+(\[[ xX]\][[:space:]]+)?|#+[[:space:]]+)?(§${rule_id}|\*\*${rule_id}\.\*\*)([^0-9A-Za-z]|$)" "$file"
}

# A file name as a pattern that matches it whole, for grep -E.
escape_file_name() {
  printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g'
}

# Where rules live, as a path starting at a --rules dir's own name: a `rules` or `.claude` folder
# (the dir itself may be one), or a file an agent reads as instructions. A Markdown file anywhere
# else (a changelog, a readme) is not one.
readonly RULE_FILE_PATH='(^|/)(rules|\.claude)/|(^|/)(CLAUDE|AGENTS|SKILL)\.md$'

run_check() {
  # shellcheck source=lib/risk-paths.sh
  . "$(dirname "$0")/lib/risk-paths.sh"
  local feedback_list=${1:-} ledger=${2:-} diffs=() public_diffs=() rules_dirs=() repo_dir="" base_ref="" terms_file=""
  [ -n "$feedback_list" ] && [ -n "$ledger" ] || usage
  shift 2
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --diff) [ "$#" -ge 2 ] || usage; diffs+=("$2"); shift 2 ;;
      --public-diff) [ "$#" -ge 2 ] || usage; diffs+=("$2"); public_diffs+=("$2"); shift 2 ;;
      --terms) [ "$#" -ge 2 ] || usage; terms_file=$2; shift 2 ;;
      --rules) [ "$#" -ge 2 ] || usage; rules_dirs+=("$2"); shift 2 ;;
      --repo) [ "$#" -ge 2 ] || usage; repo_dir=$2; shift 2 ;;
      --base) [ "$#" -ge 2 ] || usage; base_ref=$2; shift 2 ;;
      *) usage ;;
    esac
  done
  [ "${#rules_dirs[@]}" -gt 0 ] || rules_dirs=(.)
  # --repo and --base go together: both or neither.
  local neither_option_given=false both_options_given=false
  if [ -z "$repo_dir" ] && [ -z "$base_ref" ]; then neither_option_given=true; fi
  if [ -n "$repo_dir" ] && [ -n "$base_ref" ]; then both_options_given=true; fi
  "$neither_option_given" || "$both_options_given" || usage
  local input_path
  [ -z "$terms_file" ] || [ -r "$terms_file" ] || { echo "$script_name: cannot read $terms_file" >&2; exit 2; }
  for input_path in "$feedback_list" "$ledger" ${diffs[@]+"${diffs[@]}"}; do
    [ -r "$input_path" ] || { echo "$script_name: cannot read $input_path" >&2; exit 2; }
  done

  local scratch_dir added_lines changed_paths rule_lines_before rule_paths_before
  scratch_dir=$(mktemp -d)
  trap 'rm -rf "$scratch_dir"' RETURN
  added_lines=$scratch_dir/added
  changed_paths=$scratch_dir/changed
  rule_lines_before=$scratch_dir/rules
  rule_paths_before=$scratch_dir/rule-paths
  touch "$added_lines" "$changed_paths" "$rule_lines_before" "$rule_paths_before"
  # The lesson PRs' added lines, without their `+`, and the paths they change.
  for input_path in ${diffs[@]+"${diffs[@]}"}; do
    sed -n '/^+++ /d; s/^+//p' "$input_path" >> "$added_lines"
    sed -n 's|^+++ b/||p' "$input_path" >> "$changed_paths"
  done
  for input_path in "${rules_dirs[@]}"; do
    find "$input_path" -name '*.md' -type f -exec cat {} + >> "$rule_lines_before" 2>/dev/null || true
    (cd "$input_path" 2>/dev/null && find . -name '*.md' -type f | sed "s|^\.|$(basename "$(pwd -P)")|" | grep -E "$RULE_FILE_PATH") >> "$rule_paths_before" || true
  done

  # A path a check lives in: a script, hook, test, eval, CI workflow or lint-rule file.
  local has_check_file=false
  if grep -Eq "$KC_CHECK_PATHS" "$changed_paths"; then
    has_check_file=true
  fi

  local problems=0 ledger_line item_id verdict verdict_detail why_missed what_catches_it seen=" "
  record_problem() { echo "$1"; problems=$((problems + 1)); }
  # Each rule a lesson names is added by the lesson diff: an id it defines, or a file it changes.
  check_lesson_rules() {
    local rule escaped_name
    for rule in ${2//,/ }; do
      case "$rule" in
        *.*)
          escaped_name=$(escape_file_name "$rule")
          grep -Eq "(^|/)${escaped_name}\$" "$changed_paths" \
            || record_problem "$1: lesson $rule is not a file the lesson diff changes" ;;
        *) defines_rule_id "$rule" "$added_lines" || record_problem "$1: lesson $rule is not added by the lesson diff" ;;
      esac
    done
  }
  # Runs the held-by test at HEAD, then with the lesson's non-test changes reverted.
  check_held_by_test() {
    local item=$1 field=$2 spec test_file test_case path reverted
    spec=${field#held-by:}
    test_file=${spec%%::*}
    test_case=""
    case "$spec" in *::*) test_case=${spec#*::} ;; esac
    [ -n "$test_file" ] || { record_problem "$item: held-by names no test file"; return; }
    grep -Fxq "$test_file" "$changed_paths" || { record_problem "$item: held-by $test_file is not a test the lesson diff adds or changes"; return; }
    if ! (cd "$repo_dir" && bash "$test_file" ${test_case:+"$test_case"}) > "$scratch_dir/head-run" 2>&1; then
      record_problem "$item: held-by $test_file fails at HEAD, so it proves nothing: fix the test or the change"
      return
    fi
    reverted=$scratch_dir/reverted
    rm -rf "$reverted"; mkdir -p "$reverted"
    git -C "$repo_dir" archive HEAD | tar -x -C "$reverted"
    while IFS= read -r path; do
      [ "$path" != "$test_file" ] || continue
      if printf '%s\n' "$path" | grep -Eq "$KC_RISK_TEST_PATHS"; then continue; fi
      if git -C "$repo_dir" cat-file -e "$base_ref:$path" 2>/dev/null; then
        mkdir -p "$reverted/$(dirname "$path")"
        git -C "$repo_dir" show "$base_ref:$path" > "$reverted/$path"
      else
        rm -f "$reverted/$path"
      fi
    done < "$changed_paths"
    if (cd "$reverted" && bash "$test_file" ${test_case:+"$test_case"}) > "$scratch_dir/reverted-run" 2>&1; then
      record_problem "$item: held-by $test_file passes at HEAD and still passes with the lesson's non-test changes reverted, so it does not block the mistake: make it fail without the change"
    fi
  }
  # Each tagged field of a lesson line, from field number $2 on, as `name:value`.
  lesson_field() {
    local value
    value=$(printf '%s' "$ledger_line" | awk -F'\t' -v from="$2" -v tag="$1:" \
      'NR == 1 { for (i = from; i <= NF; i++) if (index($i, tag) == 1) found = substr($i, length(tag) + 1) } END { print found }')
    value=${value#"${value%%[![:space:]]*}"}
    printf '%s' "${value%"${value##*[![:space:]]}"}"
  }
  # A lesson record names its class, two unlike examples, the layer it sits at, why no higher
  # layer holds it, and its proof. $1 is the item, $2 the number of the first tagged field.
  check_lesson_record() {
    local item=$1 from=$2 tag value rest example example_count=0 empty_example=false
    for tag in class examples mechanism why-not-higher proof; do
      value=$(lesson_field "$tag" "$from")
      if [ -n "$value" ]; then continue; fi
      if printf '%s' "$ledger_line" | tr '\t' '\n' | tail -n +"$from" | grep -q "^$tag:"; then
        record_problem "$item: lesson $tag: is empty"
      elif [ "$tag" != why-not-higher ] || [ "$(lesson_field mechanism "$from")" != check ]; then
        record_problem "$item: lesson is missing $tag:"
      fi
    done
    value=$(lesson_field examples "$from")
    if [ -n "$value" ]; then
      rest=$value
      while :; do
        example=${rest%%; *}
        example_count=$((example_count + 1))
        [ -n "${example//[[:space:]]/}" ] || empty_example=true
        case "$rest" in *"; "*) rest=${rest#*; } ;; *) break ;; esac
      done
      if [ "$empty_example" = true ]; then
        record_problem "$item: lesson examples: has an empty example"
      elif [ "$example_count" -lt 2 ]; then
        record_problem "$item: lesson examples: has one example; a lesson needs two unlike cases, separated by \"; \""
      fi
    fi
    value=$(lesson_field mechanism "$from")
    case "$value" in
      "" | check | guard | path-rule | skill | always-on) ;;
      *) record_problem "$item: lesson mechanism:$value is not one of check, guard, path-rule, skill, always-on" ;;
    esac
  }
  # A lesson is held by a check in the diff; a ledger field cannot stand in for one.
  check_lesson_is_held() {
    if [ -n "$repo_dir" ]; then
      local held_field
      held_field=$(printf '%s' "$ledger_line" | tr '\t' '\n' | grep '^held-by:' | tail -n 1 || true)
      if [ -z "$held_field" ]; then
        record_problem "$1: lesson has no held-by:<test file>[::<case>]: name the test that fails without the change"
      else
        check_held_by_test "$1" "$held_field"
      fi
      return 0
    fi
    [ "$has_check_file" = true ] && return 0
    record_problem "$1: lesson is prose with no check: the lesson diff adds or changes no script, hook, test, eval, CI workflow or lint-rule file"
  }
  # No client term in the added lines of a --public-diff (private terms, one per line; no file, no check).
  check_client_terms() {
    local public_diff term added_text added_numbers hit
    [ "${#public_diffs[@]}" -gt 0 ] || return 0
    [ -n "$terms_file" ] || terms_file=${KC_CLIENT_TERMS:-$HOME/.claude/kc-client-terms.txt}
    [ -r "$terms_file" ] || return 0
    for public_diff in "${public_diffs[@]}"; do
      added_text=$scratch_dir/public-text
      added_numbers=$scratch_dir/public-numbers
      awk '/^\+\+\+ / { next } /^\+/ { print substr($0, 2) }' "$public_diff" > "$added_text"
      awk '/^\+\+\+ / { next } /^\+/ { print NR }' "$public_diff" > "$added_numbers"
      while IFS= read -r term || [ -n "$term" ]; do
        term=${term%$'\r'}
        case "$term" in "" | "#"*) continue ;; esac
        while IFS=: read -r hit _; do
          record_problem "$public_diff: line $(sed -n "${hit}p" "$added_numbers") names client term \"$term\""
        done < <(grep -n -i -w -F -e "$term" "$added_text" || true)
      done < "$terms_file"
    done
  }
  while IFS= read -r ledger_line || [ -n "$ledger_line" ]; do
    [ -n "$ledger_line" ] || continue
    # A separator that is not whitespace, so `read` keeps an empty field instead of skipping it.
    IFS=$'\x1f' read -r item_id verdict verdict_detail why_missed what_catches_it _ <<< "${ledger_line//$'\t'/$'\x1f'}"
    case "$seen" in *" $item_id "*) record_problem "$item_id: listed twice in the ledger"; continue ;; esac
    seen="$seen$item_id "
    grep -q "^$item_id"$'\t' "$feedback_list" || { record_problem "$item_id: not on the feedback list"; continue; }
    case "$verdict" in
      lesson)
        [ -n "$verdict_detail" ] || { record_problem "$item_id: lesson names no rule id"; continue; }
        check_lesson_rules "$item_id" "$verdict_detail"
        check_lesson_record "$item_id" 4
        check_lesson_is_held "$item_id" ;;
      covered)
        [ -n "$verdict_detail" ] || { record_problem "$item_id: covered names no rule id"; continue; }
        case "$verdict_detail" in
          *.*)
            grep -Eq "(^|/)$(escape_file_name "$verdict_detail")\$" "$rule_paths_before" \
              || record_problem "$item_id: covered by $verdict_detail, which is not a rule file" ;;
          *) defines_rule_id "$verdict_detail" "$rule_lines_before" || record_problem "$item_id: covered by $verdict_detail, which no rule file had" ;;
        esac
        [ -n "$why_missed" ] || record_problem "$item_id: covered by $verdict_detail says nothing on why it was still missed"
        case "$what_catches_it" in
          lesson:?*)
            check_lesson_rules "$item_id" "${what_catches_it#lesson:}"
            check_lesson_record "$item_id" 6
            check_lesson_is_held "$item_id" ;;
          no-change:?*) ;;
          *) record_problem "$item_id: covered by $verdict_detail says nothing on what catches the miss now (lesson:<rule id> or no-change:<why>)" ;;
        esac ;;
      one-off | not-feedback)
        [ -n "$verdict_detail" ] || record_problem "$item_id: $verdict gives no reason" ;;
      *) record_problem "$item_id: '$verdict' is not lesson, covered, one-off or not-feedback" ;;
    esac
  done < "$ledger"

  check_client_terms
  local listed_id
  while IFS=$'\t' read -r listed_id _; do
    [ -n "$listed_id" ] || continue
    case "$seen" in *" $listed_id "*) ;; *) record_problem "$listed_id: no verdict in the ledger" ;; esac
  done < "$feedback_list"

  if [ "$problems" -gt 0 ]; then
    echo "ledger: $problems problem(s)" >&2
    return 1
  fi
  echo "ledger: $(grep -c . "$feedback_list") item(s), each with a verdict"
}

[ "$#" -ge 1 ] || usage
subcommand=$1
shift
case "$subcommand" in
  list) run_list "$@" ;;
  check) run_check "$@" ;;
  *) usage ;;
esac
