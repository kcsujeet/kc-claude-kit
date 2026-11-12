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
#   feedback-ledger.sh check <list> <ledger> [--diff <file>]... [--rules <dir>]...
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
  local feedback_list=${1:-} ledger=${2:-} diffs=() rules_dirs=()
  [ -n "$feedback_list" ] && [ -n "$ledger" ] || usage
  shift 2
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --diff) [ "$#" -ge 2 ] || usage; diffs+=("$2"); shift 2 ;;
      --rules) [ "$#" -ge 2 ] || usage; rules_dirs+=("$2"); shift 2 ;;
      *) usage ;;
    esac
  done
  [ "${#rules_dirs[@]}" -gt 0 ] || rules_dirs=(.)
  local input_path
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
  while IFS= read -r ledger_line || [ -n "$ledger_line" ]; do
    [ -n "$ledger_line" ] || continue
    # A separator that is not whitespace, so `read` keeps an empty field instead of skipping it.
    IFS=$'\x1f' read -r item_id verdict verdict_detail why_missed what_catches_it <<< "${ledger_line//$'\t'/$'\x1f'}"
    case "$seen" in *" $item_id "*) record_problem "$item_id: listed twice in the ledger"; continue ;; esac
    seen="$seen$item_id "
    grep -q "^$item_id"$'\t' "$feedback_list" || { record_problem "$item_id: not on the feedback list"; continue; }
    case "$verdict" in
      lesson)
        [ -n "$verdict_detail" ] || { record_problem "$item_id: lesson names no rule id"; continue; }
        check_lesson_rules "$item_id" "$verdict_detail" ;;
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
          lesson:?*) check_lesson_rules "$item_id" "${what_catches_it#lesson:}" ;;
          no-change:?*) ;;
          *) record_problem "$item_id: covered by $verdict_detail says nothing on what catches the miss now (lesson:<rule id> or no-change:<why>)" ;;
        esac ;;
      one-off | not-feedback)
        [ -n "$verdict_detail" ] || record_problem "$item_id: $verdict gives no reason" ;;
      *) record_problem "$item_id: '$verdict' is not lesson, covered, one-off or not-feedback" ;;
    esac
  done < "$ledger"

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
