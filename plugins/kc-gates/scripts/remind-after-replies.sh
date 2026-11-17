#!/usr/bin/env bash
# PostToolUse hook for Bash: after a command that posts a reply on a pull request, reminds Claude
# of the steps the reply leaves owed, without being asked: wait for CI, re-request the reviewer,
# move the tracker ticket back to review, then the look-back. Posting the replies reads as the end
# of the work, and nothing else marks that the round is not handed back yet.
#
# A reply is a `gh pr comment`, or a `gh api` write to a PR review comment's `replies` endpoint, or
# to a PR's `comments` endpoint with an `in_reply_to` field. A `gh api` call writes when it names
# POST, or passes a field or an --input file (gh then defaults to POST) without naming another
# method; a plain GET reads. An `in_reply_to` held only in an --input file is not seen.
#
# It splits the command as the other hooks do, quotes or not, so a body holding `;` can cost a
# reminder or add one; a reminder is harmless either way. It does not drop heredoc bodies (see
# remind-look-back.sh): a heredoc that only writes those words costs one line.
#
# Output: PostToolUse JSON with the reminder as additionalContext, nothing otherwise. Always exits
# 0. Hook schema: https://code.claude.com/docs/en/hooks
#
# KC_GUARD_NO_JQ=1 forces the sed fallback (used by the tests).

set -u

# shellcheck source=lib/hook-input.sh
. "$(dirname "$0")/lib/hook-input.sh"

# A number, or a shell variable reference ($PR, ${ID}) the command holds unexpanded.
readonly ID='([0-9]+|\$\{?[[:alpha:]_][[:alnum:]_]*\}?)'
readonly REPLY_ENDPOINT="pulls/$ID/comments/$ID/replies([^/[:alnum:]]|\$)"
readonly PR_COMMENTS_ENDPOINT="pulls/$ID/comments([^/[:alnum:]]|\$)"

# True when the `gh api` segment writes: it names POST (any case), or passes a field or --input,
# also attached as `-fbody=x`, and names no other method. The method and field patterns are the
# ones guard-github-post.sh uses, narrowed to POST.
is_write_segment() {
  local segment=$1
  if printf '%s' "$segment" | grep -Eiq -- "(-X|--method)[[:space:]=]*[\"']?POST"; then
    return 0
  fi
  if printf '%s' "$segment" | grep -Eiq -- "(-X|--method)[[:space:]=]*[\"']?[A-Za-z]"; then
    return 1
  fi
  printf '%s' "$segment" | grep -Eq -- '(^|[[:space:]])(-f|-F|--field|--raw-field|--input)([[:space:]=]|[^[:space:]-]|$)'
}

is_reply_segment() {
  local segment=$1
  if printf '%s' "$segment" | grep -Eq "${GH_COMMAND_START}pr[[:space:]]+comment([[:space:]]|$)"; then
    return 0
  fi
  printf '%s' "$segment" | grep -Eq "${GH_COMMAND_START}api([[:space:]]|$)" || return 1
  is_write_segment "$segment" || return 1
  if printf '%s' "$segment" | grep -Eq "$REPLY_ENDPOINT"; then
    return 0
  fi
  printf '%s' "$segment" | grep -Eq "$PR_COMMENTS_ENDPOINT" || return 1
  printf '%s' "$segment" | grep -Eq 'in_reply_to'
}

main() {
  local input command segment
  input="$(cat)"
  command="$(extract_field "$input" command)"
  while IFS= read -r segment; do
    if is_reply_segment "$segment"; then
      cat <<'REMINDER'
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"kc-gates: Replies are posted. Still owed, without being asked: wait for CI on the pull request head to pass; re-request the reviewer (`gh pr edit <n> --add-reviewer <login>`); move the tracker ticket back to the review status, assigned to that reviewer; then, once the round is handed off, the look-back (`kc-conventions:kc-look-back`). Put them on the task list."}}
REMINDER
      exit 0
    fi
  done <<EOF
$(split_segments "$command")
EOF
  exit 0
}

main
