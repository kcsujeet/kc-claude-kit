#!/usr/bin/env bash
# Checks a review's walk receipt against the `walk-item:` lines select-gates.sh printed, so a
# review that changed behaviour nobody ran cannot be posted or approved on the strength of "I
# looked at the code" (verification-gate §V11).
#
# Usage: check-walk-receipt.sh <select-gates-output> <walk-receipt.tsv>
#
#   <select-gates-output>  select-gates.sh's output saved to a file; only its `walk-item: <path>`
#                          lines are read. None means nothing to walk: the check passes.
#   <walk-receipt.tsv>     one line per item, tab-separated: <path> <what was seen> <evidence>
#                          (kc-code-review saves it as walk-receipt.tsv beside review.diff).
#                          Evidence is an existing screenshot or recording (png, jpg, jpeg, gif,
#                          webp, mp4, mov, webm; a relative path is read from the receipt's
#                          folder), or a request line with its status (`GET /orders/7 200`).
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
# and a large one).
#
# The environment the walk ran in is one line too, `env<TAB><command><TAB><evidence>`: the one command
# that brought the app up (never a chain of steps done by hand: no `&&`, `;`, `||` or `then`), and
# evidence the app answered after it (a request line with its status, or a capture). Required
# whenever there is a walk-item. The check sees that the command is named, is one command and has
# evidence; that it was run as written and is a tested one is for the reviewer.
#
# Prints one line per problem (`walk-item <path>: <problem>`, or `env: <problem>`): no receipt line,
# nothing seen, evidence that is neither, or fewer than two states walked with no reason. Exits 0
# when every item has a full line, 1 when any does not, 2 on a usage error or an unreadable <select-gates-output>. A missing or unreadable receipt is not an
# error: every item then has no receipt line, which exits 1.
set -euo pipefail

# shellcheck source=lib/capture-paths.sh
. "$(dirname "$0")/lib/capture-paths.sh"

script_name=$(basename "$0")
[ "$#" -eq 2 ] || { echo "usage: $script_name <select-gates-output> <walk-receipt.tsv>" >&2; exit 2; }
[ -r "$1" ] || { echo "$script_name: cannot read $1" >&2; exit 2; }
select_output=$1
receipt=$2
receipt_dir=$(dirname "$receipt")

items=$(sed -n 's/^walk-item: //p' "$select_output")

request_pattern='^(GET|HEAD|POST|PUT|PATCH|DELETE)[[:space:]]+[^[:space:]]+.*[[:space:]][1-5][0-9][0-9]([^0-9]|$)'
readonly MIN_STATES=2
# Viewport width classes a layout change is walked at, in px.
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
  local dimension=$1 states_text locale_count has_two_locales has_rtl_locale
  states_text=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
  case "$dimension" in
    viewport) get_missing_width_classes "$2" ;;
    locale)
      locale_count=$(printf '%s' "$states_text" | grep -Eo '(^|[^a-z])[a-z]{2}-[a-z]{2,4}([^a-z]|$)' | grep -Eo '[a-z]{2}-[a-z]{2,4}' | sort -u | grep -c . || true)
      has_two_locales=false; has_rtl_locale=false
      if [ "$locale_count" -ge 2 ]; then has_two_locales=true; fi
      if [ "$locale_count" -ge 1 ] && printf '%s' "$states_text" | grep -Eq 'rtl'; then has_rtl_locale=true; fi
      if $has_two_locales || $has_rtl_locale; then return 0; fi
      printf 'two locales such as de-DE and ar-SA, or one and rtl' ;;
    print) printf '%s' "$states_text" | grep -Eq 'print|pdf' || printf 'a print or pdf state' ;;
    data-size)
      printf '%s' "$states_text" | grep -Eq 'empty|zero|no rows|no items' || printf 'an empty state; '
      printf '%s' "$states_text" | grep -Eq 'many|long|large|overflow|truncat|paginat|[0-9]{2,} (rows|items|results|records)' || printf 'a large state' ;;
  esac
  return 0
}

dimension_lines=$(sed -n 's/^walk-dimension: //p' "$select_output")

problems=0
record_walk_problem() { echo "walk-item $1: $2"; problems=$((problems + 1)); }

while IFS= read -r item; do
  [ -n "$item" ] || continue
  line=""
  if [ -r "$receipt" ]; then
    line=$(awk -F'\t' -v item="$item" '$1 == item { print; exit }' "$receipt")
  fi
  if [ -z "$line" ]; then
    record_walk_problem "$item" "no receipt line in $receipt: walk it in the running app or at the API, then write <path><TAB><what was seen><TAB><evidence>"
    continue
  fi
  seen=$(printf '%s' "$line" | awk -F'\t' '{ print $2 }')
  evidence=$(printf '%s' "$line" | awk -F'\t' '{ print $3 }')
  if ! printf '%s' "$seen" | grep -q '[^[:space:]]'; then
    record_walk_problem "$item" "nothing seen: say what the app or the API showed for this file's behaviour"
    continue
  fi
  if printf '%s' "$evidence" | grep -Eiq "$KC_CAPTURE_PATH"; then
    evidence_exists=false
    if [ -f "$evidence" ] || [ -f "$receipt_dir/$evidence" ]; then evidence_exists=true; fi
    if [ "$evidence_exists" = false ]; then
      record_walk_problem "$item" "evidence file does not exist: $evidence"
    fi
  elif ! printf '%s' "$evidence" | grep -Eq "$request_pattern"; then
    record_walk_problem "$item" "evidence is neither an existing screenshot or recording nor a request line with its status (GET /path 200): $evidence"
  fi
  states=$(printf '%s' "$line" | awk -F'\t' '{ print $4 }')
  if ! has_walked_states "$states"; then
    record_walk_problem "$item" "fewer than two states walked: list every shape the change's output can take (empty, one long row, many short rows, each option) and walk each; write states: <a>; <b> as the fourth field, or only state: <why, three or more words> when it has one"
  fi
  while IFS= read -r dimension; do
    [ -n "$dimension" ] || continue
    uncovered=$(get_uncovered_dimension "$dimension" "$states")
    if [ -n "$uncovered" ]; then
      record_walk_problem "$item" "its diff varies along $dimension, but the states field does not cover it ($uncovered): walk the change along that dimension too and list it in states:"
    fi
  done < <(printf '%s\n' "$dimension_lines" | awk -v item="$item" 'index($0, item ": ") == 1 { print substr($0, length(item) + 3) }')
done <<EOF
$items
EOF

# The environment line.
if [ -n "$items" ]; then
  env_line=""
  if [ -r "$receipt" ]; then env_line=$(awk -F'\t' '$1 == "env" { print; exit }' "$receipt"); fi
  if [ -z "$env_line" ]; then
    echo "env: no env line in $receipt: write env<TAB><the one command that brings the review environment up><TAB><evidence the app answered, e.g. GET /health 200>"
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
    if printf '%s' "$env_evidence" | grep -Eiq "$KC_CAPTURE_PATH"; then
      if [ ! -f "$env_evidence" ] && [ ! -f "$receipt_dir/$env_evidence" ]; then
        echo "env: evidence file does not exist: $env_evidence"
        problems=$((problems + 1))
      fi
    elif ! printf '%s' "$env_evidence" | grep -Eq "$request_pattern"; then
      echo "env: evidence is neither an existing screenshot nor a request line with its status after the command (GET /health 200): $env_evidence"
      problems=$((problems + 1))
    fi
  fi
fi

[ "$problems" -eq 0 ]
