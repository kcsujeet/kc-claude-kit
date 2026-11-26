#!/usr/bin/env bash
# Checks a review's walk receipt against the `walk-item:` lines select-gates.sh printed, so a
# review that changed behaviour nobody ran cannot be posted or approved on the strength of "I
# looked at the code" (verification-gate §V11).
#
# Usage: check-walk-receipt.sh <select-gates-output> <walk-receipt.tsv> [<uses.txt>]
#
#   <uses.txt>             trace-uses.sh's output for the same diff (kc-code-review saves it beside
#                          review.diff). With it, a walk-item whose changed names have uses in other
#                          non-test files also needs a fifth field naming each of those consumers
#                          (see "Consumers" below). Without it that check is skipped.
#
#   <select-gates-output>  select-gates.sh's output saved to a file; only its `walk-item: <path>`
#                          lines are read. None means nothing to walk: the check passes.
#   <walk-receipt.tsv>     one line per item, tab-separated: <path> <what was seen> <evidence>
#                          (kc-code-review saves it as walk-receipt.tsv beside review.diff).
#                          select-gates.sh names each item's QA surface: `walk-item: <path> surface:
#                          browser|api|terminal|unit`, and only that surface's evidence is accepted
#                          (a line with no surface, from an older select-gates.sh, takes any kind):
#                            browser   a screenshot or recording (png, jpg, jpeg, gif, webp, mp4, mov,
#                                      webm; a relative path is read from the receipt's folder)
#                            api       `curl <args>: <file>`, a real request whose <file> exists, is not
#                                      empty and holds the response with headers (curl -si), so it has
#                                      an HTTP status line; or a bare request line with its status
#                                      (`GET /orders/7 200`)
#                            terminal  a run transcript, `exit <N>: <path>` (`exit 0: run.txt`), whose
#                                      <path> is an existing, non-empty text file holding the command's
#                                      output
#                            unit      a run transcript, or a request line or capture when the
#                                      function surfaces there
#                          A fourth field names the states walked, `states: <a>; <b>; ...`: at least
#                          two of the shapes the changed output can take (the data and the options:
#                          `empty list; one long row; many short rows; landscape`), or
#                          `only state: <why>` (three or more words) when it has one. One walk of one
#                          state is not QA: list every shape the output can take and walk each.
#
# A walk-item that select-gates.sh marks `walk-dimension: <path>: <dimension>` needs its states field
# to cover that dimension (the walk of the states the author picked can miss the one the change
# varies along): viewport (widths in px: 1920 or more, 1024 to 1919, 600 or less), locale (two
# codes such as de-DE, or one and rtl), print (the word print or pdf), data-size (an empty state
# and a large one), exits (each way out of a form or dialog: a submit or confirm, a cancel or
# close, and a failed save, walked for each set of fields that leads to a different exit).
#
# Consumers: a changed unit is checked from every consumer's side, not only for the values it
# stores. A walk-item with consumers in <uses.txt> (the files, other than tests and the item itself,
# that use a name the item changes) needs a fifth field, `consumers: <a>; <b>` entries joined by
# ` | `, one per consumer file, each `<consumer path>: omitted <the input left out or partial>;
# before <what it received>; after <what it receives>` (an input left out reads as a default, a
# return or event loses a key, a cache entry or preloaded record a caller holds is gone), or
# `<consumer path>: only state: <why>` (three or more words) when it can reach the unit one way
# only. An input left out or partial is its own state, never covered by "the full form saved fine".
#
# The environment the walk ran in is one line too, `env<TAB><command><TAB><evidence>`: the one command
# that brought the app up (never a chain of steps done by hand: no `&&`, `;`, `||` or `then`), and
# evidence of the kinds the items' surfaces take, joined (a browser-only diff: a capture; api: a curl
# response or request line; terminal: a transcript; a line with no surface takes any). Required
# whenever there is a walk-item; for a command-line change it is the one command that ran it,
# and its evidence can be its transcript (exit 0: run.txt). The check sees that the command is named, is one command and has
# evidence; that it was run as written and is a tested one is for the reviewer.
#
# Prints one line per problem (`walk-item <path>: <problem>`, or `env: <problem>`): no receipt line,
# nothing seen, evidence that is neither, or fewer than two states walked with no reason. Exits 0
# when every item has a full line, 1 when any does not, 2 on a usage error or an unreadable <select-gates-output>. A missing or unreadable receipt is not an
# error: every item then has no receipt line, which exits 1.
set -euo pipefail

# shellcheck source=lib/capture-paths.sh
. "$(dirname "$0")/lib/capture-paths.sh"
# shellcheck source=lib/risk-paths.sh
. "$(dirname "$0")/lib/risk-paths.sh"
# shellcheck source=lib/qa-surface.sh
. "$(dirname "$0")/lib/qa-surface.sh"

script_name=$(basename "$0")
[ "$#" -eq 2 ] || [ "$#" -eq 3 ] || { echo "usage: $script_name <select-gates-output> <walk-receipt.tsv> [<uses.txt>]" >&2; exit 2; }
[ -r "$1" ] || { echo "$script_name: cannot read $1" >&2; exit 2; }
select_output=$1
receipt=$2
uses_file=${3:-}
if [ -n "$uses_file" ] && [ ! -r "$uses_file" ]; then echo "$script_name: cannot read $uses_file" >&2; exit 2; fi
receipt_dir=$(dirname "$receipt")

items=$(sed -n 's/^walk-item: //p' "$select_output")

request_pattern='^(GET|HEAD|POST|PUT|PATCH|DELETE)[[:space:]]+[^[:space:]]+.*[[:space:]][1-5][0-9][0-9]([^0-9]|$)'
readonly MIN_STATES=2
transcript_pattern='^exit [0-9]+:[[:space:]]*[^[:space:]].*$'

curl_pattern='^curl[[:space:]].*:[[:space:]]+[^[:space:]]+$'

# Prints the path of an evidence file (a relative one is read from the receipt's folder) that exists.
find_evidence_file() {
  if [ -f "$1" ]; then printf '%s' "$1"; elif [ -f "$receipt_dir/$1" ]; then printf '%s' "$receipt_dir/$1"; fi
}

# Prints what is wrong with a run transcript (`exit <N>: <path>`), or nothing when its file exists and has text.
get_transcript_problem() {
  local transcript_path transcript_file
  transcript_path=$(printf '%s' "$1" | sed -E 's/^exit [0-9]+:[[:space:]]*//')
  transcript_file=$(find_evidence_file "$transcript_path")
  if [ -z "$transcript_file" ]; then printf 'transcript file does not exist: %s' "$transcript_path"
  elif [ ! -s "$transcript_file" ]; then printf 'transcript file is empty: %s' "$transcript_path"; fi
}

# Prints what is wrong with a curl request's saved response (`curl <args>: <path>`), or nothing when
# its file exists and holds an HTTP status line (curl -i or -si keeps it).
get_curl_problem() {
  local response_path response_file
  response_path=$(printf '%s' "$1" | sed -E 's/^.*:[[:space:]]+//')
  response_file=$(find_evidence_file "$response_path")
  if [ -z "$response_file" ]; then printf 'curl response file does not exist: %s' "$response_path"
  elif [ ! -s "$response_file" ]; then printf 'curl response file is empty: %s' "$response_path"
  elif ! grep -Eq '^HTTP/[0-9.]+ [1-5][0-9][0-9]' "$response_file"; then printf 'curl response file has no HTTP status line (save it with curl -si): %s' "$response_path"; fi
}

# get_evidence_problem <allowed kinds> <evidence>: prints "wrong-kind" when the evidence is not one
# of the allowed kinds (capture, request, curl, transcript), or what is wrong with its file; nothing
# when it is good.
get_evidence_problem() {
  local allowed_evidence_kinds=" $1 " receipt_evidence=$2 evidence_kind
  if printf '%s' "$receipt_evidence" | grep -Eq "$transcript_pattern"; then evidence_kind=transcript
  elif printf '%s' "$receipt_evidence" | grep -Eq "$curl_pattern"; then evidence_kind=curl
  elif printf '%s' "$receipt_evidence" | grep -Eiq "$KC_CAPTURE_PATH"; then evidence_kind=capture
  elif printf '%s' "$receipt_evidence" | grep -Eq "$request_pattern"; then evidence_kind=request
  else printf 'wrong-kind'; return 0; fi
  case "$allowed_evidence_kinds" in *" $evidence_kind "*) ;; *) printf 'wrong-kind'; return 0 ;; esac
  case "$evidence_kind" in
    transcript) get_transcript_problem "$receipt_evidence" ;;
    curl) get_curl_problem "$receipt_evidence" ;;
    capture) [ -n "$(find_evidence_file "$receipt_evidence")" ] || printf 'evidence file does not exist: %s' "$receipt_evidence" ;;
  esac
}

# Adds a surface's evidence kinds to the kinds the env line may use.
env_kinds=""
add_env_kinds() {
  local evidence_kind
  for evidence_kind in $(kc_get_surface_evidence_kinds "$1"); do
    case " $env_kinds " in *" $evidence_kind "*) ;; *) env_kinds="$env_kinds $evidence_kind" ;; esac
  done
}
readonly WIDE_DESKTOP_MIN_PX=1920
readonly LAPTOP_MIN_PX=1024
readonly PHONE_MAX_PX=600

# True when a receipt line's fourth field names two or more states ("states: a; b"), or says
# "only state:" with a reason of three or more words.
has_walked_states() {
  local text
  text=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$text" | grep -Eq '^[[:space:]]*only state:[[:space:]]*[^[:space:]]+([[:space:]]+[^[:space:]]+){2,}'; then return 0; fi
  text=$(printf '%s' "$text" | sed -E 's/^[[:space:]]*states:[[:space:]]*//')
  [ "$(printf '%s' "$text" | tr ';' '\n' | grep -c '[^[:space:]]')" -ge "$MIN_STATES" ]
}

# Prints the widths in a states field (`1920px`, `1920w`, `1920x1080`, `@1920`), one per line.
get_viewport_widths() {
  printf '%s' "$1" | grep -Eo '([0-9]{3,4})(px|w)([^a-z]|$)|@[0-9]{3,4}|[0-9]{3,4}x[0-9]{3,4}' | sed -E 's/^@//; s/[^0-9].*$//' || true
}

# Prints the width classes missing from a states field, or nothing when all three are there.
get_missing_width_classes() {
  local widths missing="" width has_wide=false has_laptop=false has_phone=false
  widths=$(get_viewport_widths "$1")
  for width in $widths; do
    if [ "$width" -ge "$WIDE_DESKTOP_MIN_PX" ]; then has_wide=true
    elif [ "$width" -ge "$LAPTOP_MIN_PX" ]; then has_laptop=true
    elif [ "$width" -le "$PHONE_MAX_PX" ]; then has_phone=true; fi
  done
  $has_wide || missing="a wide desktop (${WIDE_DESKTOP_MIN_PX}px or more)"
  $has_laptop || missing="${missing:+$missing, }a laptop (${LAPTOP_MIN_PX}px to $((WIDE_DESKTOP_MIN_PX - 1))px)"
  $has_phone || missing="${missing:+$missing, }a phone (${PHONE_MAX_PX}px or less)"
  printf '%s' "$missing"
}

# Prints what a states field still lacks for a dimension, or nothing when it covers it.
get_uncovered_dimension() {
  local dimension=$1 states_text locale_pattern locale_count has_two_locales has_rtl_locale has_one_locale mentions_rtl
  states_text=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
  case "$dimension" in
    viewport) get_missing_width_classes "$2" ;;
    locale)
      # Locale tags keep their capitals (de-DE, zh-Hans) unless the field says locale or lang, so a hyphenated word (no-op) is not one.
      locale_pattern='[a-z]{2}-([A-Z]{2}|[A-Z][a-z]{3})'
      if printf '%s' "$states_text" | grep -Eq 'locale|lang'; then locale_pattern='[A-Za-z]{2}-([A-Za-z]{2}|[A-Za-z]{4})'; fi
      locale_count=$(printf '%s' "$2" | grep -Ewo "$locale_pattern" | tr '[:upper:]' '[:lower:]' | sort -u | grep -c . || true)
      has_two_locales=false; has_rtl_locale=false; has_one_locale=false; mentions_rtl=false
      if [ "$locale_count" -ge 2 ]; then has_two_locales=true; fi
      if [ "$locale_count" -ge 1 ]; then has_one_locale=true; fi
      if printf '%s' "$states_text" | grep -Eq 'rtl'; then mentions_rtl=true; fi
      if $has_one_locale && $mentions_rtl; then has_rtl_locale=true; fi
      if $has_two_locales || $has_rtl_locale; then return 0; fi
      printf 'two locales such as de-DE and ar-SA, or one and rtl' ;;
    print) printf '%s' "$states_text" | grep -Eq 'print|pdf' || printf 'a print or pdf state' ;;
    exits)
      printf '%s' "$states_text" | grep -Eq 'submit|save|confirm|apply|send|(^|[^a-z])ok([^a-z]|$)' || printf 'a submit or confirm; '
      printf '%s' "$states_text" | grep -Eq 'cancel|close|dismiss|escape|discard' || printf 'a cancel or close; '
      printf '%s' "$states_text" | grep -Eq 'fail|error|reject|offline|timeout|(^|[^0-9a-z])[45][0-9][0-9]([^0-9a-z]|$)' || printf 'a failed save' ;;
    data-size)
      printf '%s' "$states_text" | grep -Eq 'empty|zero|no rows|no items' || printf 'an empty state; '
      printf '%s' "$states_text" | grep -Eq 'many|long|large|overflow|truncat|paginat|[0-9]{2,} (rows|items|results|records)' || printf 'a large state' ;;
  esac
  return 0
}

# Prints the files, other than tests and the item itself, that use a name the item changes, one per
# line. Every code use counts, with no cap. Prose and config files, comments, quoted words, plain
# `$name` reads and `name=` assignments, and an enclosing name that is never called do not.
get_consumers() {
  KC_TEST_PATHS=$KC_RISK_TEST_PATHS KC_SOURCE_PATHS=$KC_RISK_SOURCE_PATHS awk -v item="$1" '
    /^name / {
      in_item = (index($0, ", " item "): ") > 0)
      name_text = $2; gsub(/[?!]/, "", name_text)
      name_pattern = ""
      for (position = 1; position <= length(name_text); position++) {
        character = substr(name_text, position, 1)
        name_pattern = name_pattern (index("\\^$.[]|()*+?{}", character) ? "\\" : "") character
      }
      is_enclosing_name = ($3 == "(enclosing,")
      next
    }
    in_item && /^  [^ ]/ {
      consumer = $1; sub(/:[0-9]+:.*$/, "", consumer)
      use_text = $0; sub(/^  [^ ]*:[0-9]+: /, "", use_text)
      is_comment = (use_text ~ /^[ \t]*(#|\/\/|\*|\/\*)/)
      gsub(/"[^"$#]*"/, "", use_text); gsub(/\x27[^\x27]*\x27/, "", use_text); sub(/[ \t]+(#|\/\/).*$/, "", use_text)
      is_item_itself = (consumer == item)
      is_test_file = (consumer ~ ENVIRON["KC_TEST_PATHS"])
      is_code_file = (consumer ~ ENVIRON["KC_SOURCE_PATHS"])
      is_named = (use_text ~ ("(^|[^A-Za-z0-9_$\\{])" name_pattern "([^A-Za-z0-9_=]|=[=~]|$)"))
      is_assignment = (use_text ~ ("^[ \t]*((local|const|let|var|export) +)?" name_pattern "[ \t]*=([^=~]|$)"))
      is_command_position_call = (use_text ~ ("(^[ \t]*|[$][(]|[|&;(][ \t]*|then |do )" name_pattern "([( \t.]|$)"))
      is_member_or_argument_call = (use_text ~ ("[^A-Za-z0-9_$.{]" name_pattern "[(.]"))
      is_call = (is_command_position_call || is_member_or_argument_call)
      is_uncalled_enclosing_name = (is_enclosing_name && !is_call)
      if (is_item_itself || is_test_file || !is_code_file || is_comment || !is_named || is_assignment || is_uncalled_enclosing_name) next
      if (!(consumer in seen)) { seen[consumer] = 1; print consumer }
    }
    /^tests:/ { in_item = 0 }
  ' "$uses_file"
}

# Prints what is wrong with the entry for one consumer in a receipt's fifth field, or nothing.
get_consumer_problem() {
  local consumer=$1 consumers_field=$2 consumer_entry="" entry_line entry_text has_before has_after
  while IFS= read -r entry_line || [ -n "$entry_line" ]; do
    entry_line=${entry_line#"${entry_line%%[![:space:]]*}"}
    if [[ $entry_line == "$consumer":* ]]; then consumer_entry=$entry_line; break; fi
  done < <(printf '%s' "$consumers_field" | sed -E 's/^[[:space:]]*consumers:[[:space:]]*//' | tr '|' '\n')
  if [ -z "$consumer_entry" ]; then
    printf 'consumer %s uses what this item changes and has no entry: add "consumers: %s: omitted <the input left out or partial>; before <x>; after <y>" (entries joined by |) as the fifth field, or "%s: only state: <why>"' "$consumer" "$consumer" "$consumer"
    return 0
  fi
  entry_text=$(printf '%s' "${consumer_entry#"$consumer":}" | tr '[:upper:]' '[:lower:]')
  if printf '%s' "$entry_text" | grep -Eq '^[[:space:]]*only state:[[:space:]]*[^[:space:]]+([[:space:]]+[^[:space:]]+){2,}'; then return 0; fi
  has_before=false; has_after=false
  if printf '%s' "$entry_text" | grep -Eq 'before'; then has_before=true; fi
  if printf '%s' "$entry_text" | grep -Eq 'after'; then has_after=true; fi
  if ! printf '%s' "$entry_text" | grep -Eq 'omitted|partial|absent|missing|left out|not passed'; then
    printf 'consumer %s: walk it with an input left out or partial (omitted <input>), or give only state: <why>' "$consumer"
  elif ! $has_before || ! $has_after; then
    printf 'consumer %s: give what it received before and after the change (before <x>; after <y>), or only state: <why>' "$consumer"
  fi
}

dimension_lines=$(sed -n 's/^walk-dimension: //p' "$select_output")

problems=0
record_walk_problem() { echo "walk-item $1: $2"; problems=$((problems + 1)); }

while IFS= read -r item_line; do
  [ -n "$item_line" ] || continue
  # `<path> surface: <surface>`; an older line with no surface is the path alone.
  walk_item_path=$item_line
  surface=""
  if [[ $item_line =~ ^(.*)\ surface:\ ($KC_QA_SURFACES)$ ]]; then walk_item_path=${BASH_REMATCH[1]}; surface=${BASH_REMATCH[2]}; fi
  add_env_kinds "$surface"
  allowed_kinds=$(kc_get_surface_evidence_kinds "$surface")
  allowed_kinds_text=$(kc_describe_evidence_kinds "$allowed_kinds")
  line=""
  if [ -r "$receipt" ]; then
    line=$(awk -F'\t' -v item="$walk_item_path" '$1 == item { print; exit }' "$receipt")
  fi
  if [ -z "$line" ]; then
    record_walk_problem "$walk_item_path" "no receipt line in $receipt: walk it on its QA surface (browser, API, terminal, unit), then write <path><TAB><what was seen><TAB><evidence>"
    continue
  fi
  seen=$(printf '%s' "$line" | awk -F'\t' '{ print $2 }')
  evidence=$(printf '%s' "$line" | awk -F'\t' '{ print $3 }')
  if ! printf '%s' "$seen" | grep -q '[^[:space:]]'; then
    record_walk_problem "$walk_item_path" "nothing seen: say what the walk showed for this file's behaviour"
    continue
  fi
  evidence_problem=$(get_evidence_problem "$allowed_kinds" "$evidence")
  if [ "$evidence_problem" = "wrong-kind" ]; then
    if [ -n "$surface" ]; then
      record_walk_problem "$walk_item_path" "$walk_item_path is a $surface surface: give $allowed_kinds_text, not: $evidence"
    else
      record_walk_problem "$walk_item_path" "evidence is none of $allowed_kinds_text: $evidence"
    fi
  elif [ -n "$evidence_problem" ]; then
    record_walk_problem "$walk_item_path" "$evidence_problem"
  fi
  states=$(printf '%s' "$line" | awk -F'\t' '{ print $4 }')
  if ! has_walked_states "$states"; then
    record_walk_problem "$walk_item_path" "fewer than two states walked: list every shape the change's output can take (empty, one long row, many short rows, each option) and walk each; write states: <a>; <b> as the fourth field, or only state: <why, three or more words> when it has one"
  fi
  if [ -n "$uses_file" ]; then
    consumers_field=$(printf '%s' "$line" | awk -F'\t' '{ print $5 }')
    while IFS= read -r consumer; do
      [ -n "$consumer" ] || continue
      consumer_problem=$(get_consumer_problem "$consumer" "$consumers_field")
      if [ -n "$consumer_problem" ]; then record_walk_problem "$walk_item_path" "$consumer_problem"; fi
    done < <(get_consumers "$walk_item_path")
  fi
  while IFS= read -r dimension; do
    [ -n "$dimension" ] || continue
    uncovered=$(get_uncovered_dimension "$dimension" "$states")
    if [ -n "$uncovered" ]; then
      record_walk_problem "$walk_item_path" "its diff varies along $dimension, but the states field does not cover it ($uncovered): walk the change along that dimension too and list it in states:"
    fi
  done < <(printf '%s\n' "$dimension_lines" | awk -v item="$walk_item_path" -v separator=": " 'index($0, item separator) == 1 { print substr($0, length(item separator) + 1) }')
done <<EOF
$items
EOF

# The environment line.
if [ -n "$items" ]; then
  env_line=""
  if [ -r "$receipt" ]; then env_line=$(awk -F'\t' '$1 == "env" { print; exit }' "$receipt"); fi
  if [ -z "$env_line" ]; then
    echo "env: no env line in $receipt: write env<TAB><the one command that brings the review environment up or runs the change><TAB><evidence it ran or answered, of the kinds the surfaces take: a capture, a curl request and its saved response, a request line, or a run transcript>"
    problems=$((problems + 1))
  else
    env_command=$(printf '%s' "$env_line" | awk -F'\t' '{ print $2 }')
    env_evidence=$(printf '%s' "$env_line" | awk -F'\t' '{ print $3 }')
    if ! printf '%s' "$env_command" | grep -q '[^[:space:]]'; then
      echo "env: no command: name the one command that brought the environment up"
      problems=$((problems + 1))
    elif printf '%s' "$env_command" | grep -Eq '&&|;|\|\||(^|[[:space:]])then([[:space:]]|$)'; then
      echo "env: more than one step ($env_command): put the steps in one script or target and run that, never by hand step by step"
      problems=$((problems + 1))
    fi
    env_problem=$(get_evidence_problem "$env_kinds" "$env_evidence")
    if [ "$env_problem" = "wrong-kind" ]; then
      echo "env: evidence is none of $(kc_describe_evidence_kinds "$env_kinds"), after the command: $env_evidence"
      problems=$((problems + 1))
    elif [ -n "$env_problem" ]; then
      echo "env: $env_problem"
      problems=$((problems + 1))
    fi
  fi
fi

[ "$problems" -eq 0 ]
