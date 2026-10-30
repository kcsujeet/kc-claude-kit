#!/usr/bin/env bash
# PreToolUse guard for Bash: blocks GitHub review writes that lack the
# approval token.
#
# A write is `gh pr comment`, `gh pr review`, `gh issue comment`, or a
# `gh api` call on a PR's or issue's comments or reviews that uses a write
# method (-X/--method POST, PATCH, PUT or DELETE, or any -f/-F/--field/
# --raw-field/--input without an explicit GET). Such a command passes only
# when it contains the literal KC_REVIEW_POST_APPROVED=1, which the
# kc-post-review skill adds after the user's explicit post signal.
#
# Output: the PreToolUse deny JSON on a blocked write, nothing otherwise.
# Always exits 0. Hook schema: https://code.claude.com/docs/en/hooks
#
# KC_GUARD_NO_JQ=1 forces the sed fallback (used by the tests).

set -u

# shellcheck source=lib/hook-input.sh
. "$(dirname "$0")/lib/hook-input.sh"

readonly APPROVAL_TOKEN='KC_REVIEW_POST_APPROVED=1'

readonly GH_WORD='(^|[^[:alnum:]_.-])gh[[:space:]]+'
readonly REVIEW_ENDPOINT='(pulls|issues)/([0-9]+/(comments|reviews)|comments/[0-9]+)'
readonly WRITE_METHOD='(-X|--method)[[:space:]=]*["'"'"']?(POST|PATCH|PUT|DELETE)'
readonly GET_METHOD='(-X|--method)[[:space:]=]*["'"'"']?GET([^[:alpha:]]|$)'
readonly FIELD_FLAG='(^|[[:space:]])(-f|-F|--field|--raw-field|--input)([[:space:]=]|[^[:space:]-]|$)'

is_review_write_segment() {
  local segment="$1"
  if printf '%s' "$segment" | grep -Eq "${GH_WORD}(pr[[:space:]]+(comment|review)|issue[[:space:]]+comment)([[:space:]]|$)"; then
    return 0
  fi
  if ! printf '%s' "$segment" | grep -Eq "${GH_WORD}api([[:space:]]|$)"; then
    return 1
  fi
  if ! printf '%s' "$segment" | grep -Eq "$REVIEW_ENDPOINT"; then
    return 1
  fi
  if printf '%s' "$segment" | grep -Eiq "$WRITE_METHOD"; then
    return 0
  fi
  if printf '%s' "$segment" | grep -Eiq "$GET_METHOD"; then
    return 1
  fi
  printf '%s' "$segment" | grep -Eq "$FIELD_FLAG"
}

contains_review_write() {
  local segment
  while IFS= read -r segment; do
    if is_review_write_segment "$segment"; then
      return 0
    fi
  done <<EOF
$(split_segments "$1")
EOF
  return 1
}

print_deny() {
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked by the kc-gates plugin: this command writes a PR or issue comment or review to GitHub without the approval token. Do not retry and do not add the token yourself. Show the user the full draft, the head SHA it anchors to and the posting shape, then stop and wait for an explicit, fresh post signal in their latest message. Only after that signal, prefix each write command with KC_REVIEW_POST_APPROVED=1 in the same command (see /kc-gates:kc-post-review)."}}
EOF
}

main() {
  local input command
  input="$(cat)"
  command="$(extract_field "$input" command)"
  if [ -z "$command" ]; then
    exit 0
  fi
  case "$command" in
    *"$APPROVAL_TOKEN"*) exit 0 ;;
  esac
  if contains_review_write "$command"; then
    print_deny
  fi
  exit 0
}

main
