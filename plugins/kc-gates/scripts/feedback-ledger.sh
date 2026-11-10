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
#       ledger marks not-feedback); each answer to a question asked with a choice tool; each tool call the person
#       rejected; each interrupt; and each message another session relayed. Each non-empty line of
#       an --extra file (review comments, QA rows, one per line) is one item, its source the
#       file's name. Listing only: nothing is judged here.
#
#   feedback-ledger.sh check <list> <ledger> [--diff <file>]... [--rules <dir>]...
#       Fails unless the ledger gives every listed item one verdict, as a tab-separated line:
#         <id> lesson <rule id>[,<rule id>]...       each id is added by a --diff (the lesson PR);
#                                                     a rule file with no ids (a working agreement)
#                                                     is named by its file name, which a --diff changes
#         <id> covered <rule id> <why it was missed>  the id exists under a --rules dir
#         <id> one-off <reason>
#         <id> not-feedback <reason>
#       A rule id is written as the rules write it (`§B13`, `B13`, `WF14`); it matches `§B13` or
#       `**B13.**` in the text. --rules defaults to the current directory.
#
# Needs jq for `list`. Exits 0 when the ledger is complete, 1 with one line per problem, 2 on
# usage errors.
set -euo pipefail

script_name=$(basename "$0")
usage() {
  sed -n '7,22p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

# Turns a JSONL transcript into "<source>\t<text>" lines, in order.
list_transcript() {
  jq -r '
    def oneline: gsub("[\t\r\n]+"; " ") | sub("^ +"; "") | sub(" +$"; "");
    def typed_text:
      if (.message.content | type) == "string" then [.message.content]
      else [.message.content[]? | select(.type == "text") | .text] end;
    def skipped: test("^(<system-reminder>|<task-notification>|<local-command|<command-name>|Caveat: |Base directory for this skill: )");
    if .type == "user" and (.isCompactSummary | not) then
      if (.isMeta == true) then
        (typed_text[] | select(test("^Another Claude session sent a message")) | "session\t" + oneline)
      else
        (typed_text[] | select(skipped | not) |
          if test("^\\[Request interrupted") then "interrupt\t" + oneline else "typed\t" + oneline end),
        (.message.content | if type == "array" then .[] else empty end
          | select(.type == "tool_result")
          | (.content | if type == "array" then map(.text? // "") | join(" ") else tostring end) as $text
          | if ($text | test("^The user answered|^User has answered")) then "answer\t" + ($text | oneline)
            elif ($text | test("^The user doesn.t want to proceed with this tool use")) then "rejected\t" + ($text | oneline)
            else empty end)
      end
    elif .type == "attachment" and .attachment.type == "queued_command" and .attachment.commandMode == "prompt" then
      (.attachment.prompt | if type == "array" then [.[] | select(.type == "text") | .text] else [tostring] end
        | .[] | select(skipped | not) | "typed\t" + oneline)
    else empty end
  ' "$1"
}

run_list() {
  local transcript="" extras=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --extra) [ "$#" -ge 2 ] || usage; extras+=("$2"); shift 2 ;;
      -*) usage ;;
      *) [ -z "$transcript" ] || usage; transcript=$1; shift ;;
    esac
  done
  [ -n "$transcript" ] || usage
  command -v jq >/dev/null || { echo "$script_name: needs jq" >&2; exit 2; }
  [ -r "$transcript" ] || { echo "$script_name: cannot read $transcript" >&2; exit 2; }
  {
    list_transcript "$transcript"
    local extra
    for extra in ${extras[@]+"${extras[@]}"}; do
      [ -r "$extra" ] || { echo "$script_name: cannot read $extra" >&2; exit 2; }
      awk -v source="$(basename "$extra")" 'NF { gsub(/\t/, " "); print source "\t" $0 }' "$extra"
    done
  } | awk -F'\t' '{ printf "F%d\t%s\n", NR, $0 }'
}

# True when <id> appears in <file> as a rule id: `§ID` or `**ID.**`, not as part of a longer id.
names_rule() {
  local id=${1#§} file=$2
  grep -Eq "(§|\*\*)${id}([^0-9A-Za-z]|$)" "$file"
}

run_check() {
  local list=${1:-} ledger=${2:-} diffs=() rules=()
  [ -n "$list" ] && [ -n "$ledger" ] || usage
  shift 2
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --diff) [ "$#" -ge 2 ] || usage; diffs+=("$2"); shift 2 ;;
      --rules) [ "$#" -ge 2 ] || usage; rules+=("$2"); shift 2 ;;
      *) usage ;;
    esac
  done
  [ "${#rules[@]}" -gt 0 ] || rules=(.)
  local file
  for file in "$list" "$ledger" ${diffs[@]+"${diffs[@]}"}; do
    [ -r "$file" ] || { echo "$script_name: cannot read $file" >&2; exit 2; }
  done

  local work added corpus headers
  work=$(mktemp -d)
  trap 'rm -rf "$work"' RETURN
  added=$work/added
  corpus=$work/corpus
  # The lines a lesson PR adds, from each diff.
  for file in ${diffs[@]+"${diffs[@]}"}; do
    grep -E '^\+' "$file" | grep -vE '^\+\+\+ ' >> "$added" || true
  done
  touch "$added"
  headers=$work/headers
  for file in ${diffs[@]+"${diffs[@]}"}; do
    grep -E '^\+\+\+ b/' "$file" | sed 's|^+++ b/||' >> "$headers" || true
  done
  touch "$headers"
  for file in "${rules[@]}"; do
    grep -rhE '(§|\*\*)[A-Z]+[0-9]' "$file" >> "$corpus" 2>/dev/null || true
  done
  touch "$corpus"

  local problems=0 id verdict ref why seen=" "
  problem() { echo "$1"; problems=$((problems + 1)); }
  while IFS=$'\t' read -r id verdict ref why || [ -n "$id" ]; do
    [ -n "$id" ] || continue
    case "$seen" in *" $id "*) problem "$id: listed twice in the ledger"; continue ;; esac
    seen="$seen$id "
    grep -q "^$id"$'\t' "$list" || { problem "$id: not on the feedback list"; continue; }
    case "$verdict" in
      lesson)
        [ -n "$ref" ] || { problem "$id: lesson names no rule id"; continue; }
        local rule
        for rule in ${ref//,/ }; do
          case "$rule" in
            *.*) grep -Eq "(^|/)$(printf '%s' "$rule" | sed 's/[.[\*^$]/\\&/g')\$" "$headers" \
                   || problem "$id: lesson $rule is not a file the lesson diff changes" ;;
            *) names_rule "$rule" "$added" || problem "$id: lesson $rule is not added by the lesson diff" ;;
          esac
        done ;;
      covered)
        [ -n "$ref" ] || { problem "$id: covered names no rule id"; continue; }
        names_rule "$ref" "$corpus" || problem "$id: covered by $ref, which no rule file has"
        [ -n "$why" ] || problem "$id: covered by $ref says nothing on why it was still missed" ;;
      one-off | not-feedback)
        [ -n "$ref" ] || problem "$id: $verdict gives no reason" ;;
      *) problem "$id: '$verdict' is not lesson, covered, one-off or not-feedback" ;;
    esac
  done < "$ledger"

  local listed missing=0
  while IFS=$'\t' read -r listed _; do
    [ -n "$listed" ] || continue
    case "$seen" in *" $listed "*) ;; *) missing=$((missing + 1)); problem "$listed: no verdict in the ledger" ;; esac
  done < "$list"

  if [ "$problems" -gt 0 ]; then
    echo "ledger: $problems problem(s)" >&2
    return 1
  fi
  echo "ledger: $(grep -c . "$list") item(s), each with a verdict"
}

[ "$#" -ge 1 ] || usage
command=$1
shift
case "$command" in
  list) run_list "$@" ;;
  check) run_check "$@" ;;
  *) usage ;;
esac
