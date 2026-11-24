#!/usr/bin/env bash
# PreToolUse guard for sharing an investigation's findings (kc-investigate). When the checkout's
# current branch has an investigation write-up at `$(git rev-parse --git-path kc-investigation)/<branch>.md`,
# a command that opens a pull request or writes a comment or review from that checkout (`gh pr create`,
# `gh pr comment`, `gh pr review`, `gh issue comment`, a `gh api` call to a comments endpoint
# with a write method or fields, or an MCP tool whose name starts with create, add, post, save,
# update or reply and names a comment) is denied while `check-investigation.sh` fails on the write-up, with its problems in
# the reason. Reading comments (a `gh api` GET, an MCP list or get tool) is never denied: those
# are records the investigation reads. No write-up, another command, or a passing
# write-up: nothing printed. The checkout is the payload's cwd, or the directory of a leading
# `cd <dir> &&`. Without jq it reads nothing and lets every call through (it never blocks what it
# can't read). Output: the deny JSON or nothing; always exits 0.
set -u

hook_dir=$(cd "$(dirname "$0")" && pwd)
checker="$hook_dir/../skills/kc-investigate/scripts/check-investigation.sh"

# Prints the value of a payload field, read with jq.
get_field() {
  printf '%s' "$1" | jq -r "$2 // empty" 2>/dev/null
}

# True when the command opens a pull request or writes a comment or review. A `gh api` call to a
# comments endpoint counts only with a write method or fields; a plain GET reads.
is_sharing_command() {
  local is_comments_api=false is_write_call=false
  printf '%s' "$1" | grep -Eq '(^|[;&|[:space:](])gh[[:space:]]+(pr[[:space:]]+(create|comment|review)|issue[[:space:]]+comment)([[:space:]]|$)' && return 0
  printf '%s' "$1" | grep -Eq '(^|[;&|[:space:](])gh[[:space:]]+api[[:space:]].*comments' && is_comments_api=true
  printf '%s' "$1" | grep -Eq '(-X|--method)[[:space:]=]*(POST|PATCH|PUT)|(^|[[:space:]])(-f|-F|--field|--raw-field|--input)([[:space:]=]|$)' && is_write_call=true
  [ "$is_comments_api" = true ] && [ "$is_write_call" = true ]
}

# True when an MCP tool writes a comment: the tool part of mcp__<server>__<tool> starts with create,
# add, post, save, update or reply and names a comment (save_comment, add_issue_comment,
# comment_create). The server part is not read, so a server named like a verb changes nothing.
is_comment_writing_tool() {
  local tool_part=${1##*__}
  printf '%s' "$tool_part" | grep -Eiq '^(create|add|post|save|update|reply)[_-]([a-z]+[_-])*comments?$|^comments?[_-](create|add|post|save|update|reply)$'
}

escape_json() {
  local text=$1
  text=${text//\\/\\\\}
  text=${text//\"/\\\"}
  text=${text//$'\t'/ }
  printf '%s' "$text" | awk 'BEGIN { ORS = "" } { if (NR > 1) print "\\n"; print }'
}

handle_investigation_hook() {
  local hook_input tool_name command dir branch write_up problems
  hook_input=$(cat)
  tool_name=$(get_field "$hook_input" '.tool_name')
  dir=$(get_field "$hook_input" '.cwd')
  case "$tool_name" in
    Bash)
      command=$(get_field "$hook_input" '.tool_input.command')
      is_sharing_command "$command" || exit 0
      if [[ "$command" =~ ^[[:space:]]*cd[[:space:]]+([^[:space:]\;\&]+)[[:space:]]*\&\& ]]; then
        dir=${BASH_REMATCH[1]}
        dir=${dir//[\'\"]/}
      fi
      ;;
    mcp__*) is_comment_writing_tool "$tool_name" || exit 0 ;;
    *) exit 0 ;;
  esac
  [ -n "$dir" ] || dir=$PWD
  branch=$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null) || exit 0
  write_up=$(cd "$dir" && git rev-parse --path-format=absolute --git-path "kc-investigation/$branch.md" 2>/dev/null) || exit 0
  [ -f "$write_up" ] || exit 0
  problems=$(bash "$checker" "$write_up" 2>&1) && exit 0
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked by the kc-conventions plugin: the investigation write-up for this branch (%s) does not pass check-investigation.sh, so its findings are not ready to share. Fill each box with evidence from the records that already exist (kc-conventions:kc-investigate), then try again. Problems:\\n%s"}}\n' \
    "$(escape_json "$write_up")" "$(escape_json "$problems")"
  exit 0
}

handle_investigation_hook
