#!/usr/bin/env bash
# PreToolUse guard for Bash: blocks GitHub review writes that lack the
# approval token.
#
# A write is `gh pr comment`, `gh pr review`, `gh issue comment`, or a
# `gh api` call on a PR's or issue's comments or reviews that uses a write
# method (-X/--method POST, PATCH, PUT or DELETE, or any -f/-F/--field/
# --raw-field/--input without an explicit GET). Such a command passes only
# when it contains the literal KC_REVIEW_POST_APPROVED=1, which the
# post-review skill adds after the user's explicit post signal.
#
# Output: the PreToolUse deny JSON on a blocked write, nothing otherwise.
# Always exits 0. Hook schema: https://code.claude.com/docs/en/hooks
#
# KC_GUARD_NO_JQ=1 forces the sed fallback (used by the tests).

set -u

readonly APPROVAL_TOKEN='KC_REVIEW_POST_APPROVED=1'

extract_command() {
  local input="$1"
  if [ "${KC_GUARD_NO_JQ:-0}" != 1 ] && command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null
    return
  fi
  # JSON strings hold no raw newlines, so joining lines is safe. The capture
  # keeps escapes such as \" and \n; the checks below tolerate them.
  printf '%s' "$input" \
    | tr '\n' ' ' \
    | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' \
    | sed -e 's/\\n/\
/g' -e 's/\\"/"/g'
}

# One shell segment per line: split on newlines, ;, &&, || and |.
split_segments() {
  printf '%s\n' "$1" | sed -e 's/&&/\
/g' -e 's/||/\
/g' -e 's/;/\
/g' -e 's/|/\
/g'
}

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
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked by the code-review plugin: this command writes a PR or issue comment or review to GitHub without the approval token. Do not retry and do not add the token yourself. Show the user the full draft, the head SHA it anchors to and the posting shape, then stop and wait for an explicit, fresh post signal in their latest message. Only after that signal, prefix each write command with KC_REVIEW_POST_APPROVED=1 in the same command (see /code-review:post-review)."}}
EOF
}

main() {
  local input command
  input="$(cat)"
  command="$(extract_command "$input")"
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
