#!/usr/bin/env bash
# UserPromptSubmit hook: when the person's message says a pull request was merged or approved,
# reminds Claude that the look-back is due (kc-do-a-task step 6). remind-look-back.sh only sees a merge or an approval this session runs or reads; a pull
# request merged on GitHub by someone else reaches the session only as the person saying so, and
# the cleanup that follows then starts without the look-back.
#
# It reads the prompt as plain words, so it can miss a phrasing or fire on an odd one; a reminder
# is harmless either way. A merge or an approval that has not happened (negated, or after
# "before", "once", "until", "unless", "if", "when", "after") is cut from the text before it
# looks, and "approved" counts only next to a pull request, a review or "it".
#
# Input: the UserPromptSubmit payload on stdin (its prompt). Output: UserPromptSubmit JSON with
# the reminder as additionalContext, nothing otherwise. Always exits 0.
# Hook schema: https://code.claude.com/docs/en/hooks
#
# KC_GUARD_NO_JQ=1 forces the sed fallback (used by the tests).
set -u

# shellcheck source=lib/hook-input.sh
. "$(dirname "$0")/lib/hook-input.sh"

# The prompt lower-cased, with curly apostrophes plain and each negated or future mention of a
# merge or approval removed.
prompt_without_unreached() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E \
    -e "s/(’|‘)/'/g" \
    -e "s/n't[^.,;!?]{0,30}(merged|approved)/ /g" \
    -e "s/(^|[^[:alnum:]])(not|never|before|once|until|unless|if|when|whenever|after)([^[:alnum:]][^.,;!?]{0,30})?(merged|approved)/ /g"
}

main() {
  local input prompt text
  input="$(cat)"
  prompt="$(extract_field "$input" prompt)"
  [ -n "$prompt" ] || exit 0
  text="$(prompt_without_unreached "$prompt")"
  printf '%s' "$text" | grep -Eq "(pr|pull request|pull-request)[^.!?]{0,40}(merged|approved)|(^|[^[:alnum:]])(it|that|this|review)('s| is| was| has been| got| had been)( now| just| already)?( been)? (merged|approved)|(merged|approved) (it|the pr|my pr|this pr|the pull request)([^[:alnum:]]|$)" || exit 0
  cat <<EOF
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"kc-gates: the person says a pull request was merged or approved, so its task is handed off and the look-back is due now (kc-do-a-task step 6), before the cleanup or the next step. List every piece of feedback the session got (feedback-ledger.sh list over its transcript), give each one a verdict, and write the lessons that pass step 6's bar, without being asked. $LOOK_BACK_TRACKING"}}
EOF
  exit 0
}

main
