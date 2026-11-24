#!/usr/bin/env bash
# PreToolUse guard for sharing an investigation's findings (kc-investigate). When the checkout's
# current branch has an investigation write-up at `$(git rev-parse --git-path kc-investigation)/<branch>.md`,
# a command that opens a pull request or posts a comment from that checkout (`gh pr create`,
# `gh pr comment`, `gh pr review`, `gh issue comment`, a `gh api` write to a comments endpoint,
# or an MCP tool whose name has "comment" in it) is denied while `check-investigation.sh` fails on
# the write-up, with its problems in the reason. No write-up, another command, or a passing
# write-up: nothing printed. The checkout is the payload's cwd, or the directory of a leading
# `cd <dir> &&`. Output: the deny JSON or nothing; always exits 0. KC_GUARD_NO_JQ=1 forces the sed
# fallback (for the tests).
set -u

hook_dir=$(cd "$(dirname "$0")" && pwd)
checker="$hook_dir/../skills/kc-investigate/scripts/check-investigation.sh"

# Prints the value of a top-level or tool_input string field (jq, or a sed fallback).
get_field() {
  local input=$1 jq_path=$2 key=$3
  if command -v jq >/dev/null 2>&1 && [ "${KC_GUARD_NO_JQ:-0}" != 1 ]; then
    printf '%s' "$input" | jq -r "$jq_path // empty" 2>/dev/null
    return
  fi
  printf '%s' "$input" | tr '\n' ' ' \
    | sed -nE "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\".*/\\1/p" \
    | sed -e 's/\\"/"/g'
}

# True when the command opens a pull request or posts a comment or review.
is_sharing_command() {
  printf '%s' "$1" | grep -Eq '(^|[;&|[:space:](])gh[[:space:]]+(pr[[:space:]]+(create|comment|review)|issue[[:space:]]+comment)([[:space:]]|$)' && return 0
  printf '%s' "$1" | grep -Eq '(^|[;&|[:space:](])gh[[:space:]]+api[[:space:]].*comments' && return 0
  return 1
}

json_escape() {
  local text=$1
  text=${text//\\/\\\\}
  text=${text//\"/\\\"}
  text=${text//$'\t'/ }
  printf '%s' "$text" | awk 'BEGIN { ORS = "" } { if (NR > 1) print "\\n"; print }'
}

main() {
  local input tool_name command dir branch write_up problems
  input=$(cat)
  tool_name=$(get_field "$input" '.tool_name' tool_name)
  dir=$(get_field "$input" '.cwd' cwd)
  case "$tool_name" in
    Bash)
      command=$(get_field "$input" '.tool_input.command' command)
      is_sharing_command "$command" || exit 0
      if [[ "$command" =~ ^[[:space:]]*cd[[:space:]]+([^[:space:]\;\&]+)[[:space:]]*\&\& ]]; then
        dir=${BASH_REMATCH[1]}
        dir=${dir//[\'\"]/}
      fi
      ;;
    mcp__*[Cc]omment*) ;;
    *) exit 0 ;;
  esac
  [ -n "$dir" ] || dir=$PWD
  [ -d "$dir" ] || exit 0
  branch=$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null) || exit 0
  write_up=$(cd "$dir" && git rev-parse --path-format=absolute --git-path "kc-investigation/$branch.md" 2>/dev/null) || exit 0
  [ -f "$write_up" ] || exit 0
  problems=$(bash "$checker" "$write_up" 2>&1) && exit 0
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked by the kc-conventions plugin: the investigation write-up for this branch (%s) does not pass check-investigation.sh, so its findings are not ready to share. Fill each box with evidence from the records that already exist (kc-conventions:kc-investigate), then try again. Problems:\\n%s"}}\n' \
    "$(json_escape "$write_up")" "$(json_escape "$problems")"
  exit 0
}

main
