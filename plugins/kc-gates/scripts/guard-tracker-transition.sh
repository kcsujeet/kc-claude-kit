#!/usr/bin/env bash
# PreToolUse hook for MCP tools that move a tracker issue to its review status:
# the same hand-off as `gh pr ready`, done through a tracker instead of GitHub,
# so it needs the same proof. It blocks the move until the repo's hand-off
# checklist has verdicts with every box PASS, or N/A with a reason.
#
# A call is a transition when its tool name matches /transition.*issue/i, or it
# is a generic execute tool (name contains "execute") whose input names such an
# operation, or it is a save or update call on an issue (a name like save_issue,
# updateIssue, issue_update: trackers that move status through their general
# edit call) whose input has a state or status field (state, status, stateName,
# statusName, workflowState; a value or its nested name). It is a move to review
# when a status field of the input (transitionName, targetStatus, transition,
# status, to, name; for a save or update call only its state and status fields,
# so a title or description that mentions the review status is not a move) matches
# $KC_REVIEW_STATUS_REGEX (default `review`, case-insensitive; set it in the
# repo's or the user's settings `env`). A call that names only a transition id
# can't be read and is not blocked.
#
# Which commit's checklist: the session's working directory when it is a git
# repo holding .claude/hand-off-checklist.md (its HEAD; a repo without the file
# is not checked), otherwise the newest verdicts recorded with
# `ready-receipt.sh write <sha> --verdicts <file> --task <KEY>` for the issue
# key in the input; none found blocks.
#
# KC_READY_SKIP=1 in the input (a comment field, say) or in the hook's
# environment passes: only when the user has said, in their latest message, to
# skip the hand-off check for this move.
#
# Output: the deny JSON, nothing otherwise. Always exits 0.

set -u

scripts_dir=$(dirname "$0")

readonly SKIP_TOKEN='KC_READY_SKIP=1'
readonly STATUS_KEYS='(transitionName|targetStatus|transition|status|statusName|toStatus|to|name)'
# A save or update call moves status only through its state or status field, whose value is the
# status or an object holding its name.
readonly SAVE_STATE_KEYS='(state|status|stateName|statusName|workflowState|workflow_state)'
readonly SAVE_TOOL_PATTERN='(save|update|edit|set)[-_]?issue|issue[-_]?(save|update|edit)'

print_deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked by the kc-gates plugin: %s Only when the user has said in their latest message to skip it for this move, add KC_READY_SKIP=1 to the call (a comment field) or the environment; never on your own."}}\n' "$1"
}

escape_json() {
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

main() {
  local input tool dir status_regex key root unmet lines status_key_pattern value_prefix=""
  input=$(cat)
  input=${input%%'"tool_response"'*}
  case "$input" in *"$SKIP_TOKEN"*) exit 0 ;; esac
  [ "${KC_READY_SKIP:-}" != 1 ] || exit 0
  tool=$(printf '%s' "$input" | tr '\n' ' ' | sed -nE 's/.*"tool_name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p')
  status_key_pattern=$STATUS_KEYS
  if printf '%s' "$tool" | grep -Eiq 'transition.*issue'; then
    :
  elif printf '%s' "$tool" | grep -Eiq "$SAVE_TOOL_PATTERN"; then
    status_key_pattern=$SAVE_STATE_KEYS
    value_prefix='(\{[^{}]*"name"[[:space:]]*:[[:space:]]*)?'
  else
    printf '%s' "$tool" | grep -Eiq 'execute' || exit 0
    printf '%s' "$input" | grep -Eiq '"(name|operation|operationId|tool)"[[:space:]]*:[[:space:]]*"[^"]*transition[^"]*issue' || exit 0
  fi
  status_regex=${KC_REVIEW_STATUS_REGEX:-review}
  printf '%s' "$input" | tr '\n' ' ' | grep -Eiq "\"$status_key_pattern\"[[:space:]]*:[[:space:]]*$value_prefix\"[^\"]*($status_regex)" || exit 0
  dir=$(printf '%s' "$input" | tr '\n' ' ' | sed -nE 's/.*"cwd"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p')
  dir=${dir:-$PWD}
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || root=""
  if [ -n "$root" ]; then
    local sha
    sha=$(git -C "$root" rev-parse HEAD)
    if unmet=$(bash "$scripts_dir/ready-receipt.sh" check "$sha" --checklist --repo "$root" 2>/dev/null); then
      exit 0
    fi
    lines=$(printf '%s' "$unmet" | escape_json | awk '{ printf "%s%s", (NR > 1 ? "\\n" : ""), "- " $0 }')
    print_deny "this moves the issue to its review status, and the hand-off checklist of $sha is not met:\\n$lines\\nGrade each box and record it: bash $scripts_dir/ready-receipt.sh write $sha --verdicts <graded-checklist-file> --task <KEY>."
    exit 0
  fi
  key=$(printf '%s' "$input" | grep -Eo '"(issueIdOrKey|issueKey|issue_key|key|issueId)"[[:space:]]*:[[:space:]]*"[A-Z][A-Z0-9]+-[0-9]+"' | head -n 1 | grep -Eo '[A-Z][A-Z0-9]+-[0-9]+')
  [ -n "$key" ] || key=$(printf '%s' "$input" | grep -Eo '[A-Z][A-Z0-9]+-[0-9]+' | head -n 1)
  if [ -z "$key" ]; then
    print_deny "this moves an issue to its review status from a directory that is no git repo, and the call names no issue key to find a checklist receipt for."
    exit 0
  fi
  if ! unmet=$(bash "$scripts_dir/ready-receipt.sh" check-task "$key" 2>/dev/null); then
    lines=$(printf '%s' "$unmet" | escape_json | awk '{ printf "%s%s", (NR > 1 ? "\\n" : ""), "- " $0 }')
    print_deny "this moves $key to its review status, and its hand-off checklist is not met:\\n$lines\\nRecord it from the repo: bash $scripts_dir/ready-receipt.sh write <sha> --verdicts <graded-checklist-file> --task $key."
  fi
  exit 0
}

main
