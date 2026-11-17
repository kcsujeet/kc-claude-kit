#!/usr/bin/env bash
# UserPromptSubmit hook: before Claude writes its reply, reminds it of the reply rules the Stop
# hooks check (check-reply-length.sh, check-reply-sources.sh), and names what the last reply
# missed. The check runs here, at the start of the turn, because no hook runs before a reply is
# shown: a Stop hook that blocks makes Claude write the reply again, and the person sees both.
#
# When the prompt is a question, the reminder adds the trigger for "answer the question asked": the
# first sentence answers that question in its own terms, before any other work. A question is a
# prompt that ends with `?` or opens with a question word (do, does and did only before a subject,
# so "do this" stays an instruction). A reply that opens with background and then does the work
# misses it, and "answer first" alone did not stop that.
#
# Input: the UserPromptSubmit payload on stdin (its session_id and prompt). Output: the reminder,
# which Claude Code adds to the turn as context; the misses file is removed once named. Always
# exits 0. Hook schema: https://code.claude.com/docs/en/hooks
#
# KC_GUARD_NO_JQ=1 forces the sed fallback for the prompt (used by the tests).
set -u

# shellcheck source=lib/hook-input.sh
. "$(dirname "$0")/lib/hook-input.sh"
# shellcheck source=lib/reply-misses.sh
. "$(dirname "$0")/lib/reply-misses.sh"

# True when the prompt is a question.
is_question() {
  local text
  text=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  case "$text" in *'?') return 0 ;; esac
  printf '%s' "$text" | grep -Eq "^(when|why|what|how|where|who|which|is|are|can|should|will)([^[:alnum:]]|$)|^(do|does|did)[[:space:]]+(you|we|i|they|it|he|she)([^[:alnum:]]|$)"
}

input="$(cat)"

echo "Reply rules for this turn: answer first, under $REPLY_MAX_WORDS words of prose (code blocks and tables don't count), with no recap, background or explanation nobody asked for. Before saying what instructions require, read them this turn and cite the file and line. Before handing over an account CLI's command, check its access."

if is_question "$(extract_field "$input" prompt)"; then
  echo "This prompt is a question: your first sentence answers exactly that question in its own terms (a \"when\" gets a time, a \"why\" the cause, a yes/no question a yes or no), and no tool work or other action starts before it unless answering needs a lookup."
fi

command -v jq >/dev/null 2>&1 || exit 0
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
misses_file=$(reply_misses_file "$session_id")
[ -s "$misses_file" ] || exit 0

echo "Your last reply broke them. Don't repeat or rewrite it; just keep this one within them:"
sed 's/^/- /' "$misses_file"
rm -f "$misses_file"
exit 0
