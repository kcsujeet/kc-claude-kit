#!/usr/bin/env bash
# Tests scripts/guard-tracker-transition.sh (§H7): a tracker call that moves an
# issue to a review status is denied until the hand-off checklist has verdicts
# (PASS, or N/A with a reason) for every box, read from the session's repo or,
# outside a repo, from verdicts recorded with --task <KEY>.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
export KC_READY_DIR="$work_dir/receipts"
unset KC_READY_SKIP KC_REVIEW_STATUS_REGEX || true

git_commit() { git -C "$1" -c user.name=t -c user.email=t@example.test commit -q --allow-empty -m "$2"; }
git init -q "$work_dir/plain-repo"
git_commit "$work_dir/plain-repo" base
git init -q "$work_dir/list-repo"
mkdir -p "$work_dir/list-repo/.claude"
printf '# Hand-off checklist\n\n- [ ] The walkthrough video is in the How to test section.\n- [ ] The assignee is the named reviewer.\n' > "$work_dir/list-repo/.claude/hand-off-checklist.md"
git -C "$work_dir/list-repo" add -A
git_commit "$work_dir/list-repo" checklist
head_sha=$(git -C "$work_dir/list-repo" rev-parse HEAD)
mkdir "$work_dir/not-a-repo"

save_verdicts() {
  printf '%b' "$1" > "$work_dir/graded.md"
  (cd "$work_dir/list-repo" && bash "$scripts/ready-receipt.sh" write "$head_sha" --verdicts "$work_dir/graded.md" "${@:2}" >/dev/null 2>&1)
}

# <event> <tool> <tool_input json> <cwd>
payload() {
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"%s","tool_name":"%s","tool_input":%s,"tool_response":{"issue":{"fields":{"assignee":{"displayName":"me"},"status":{"name":"In Review"}}}}}' "$4" "$1" "$2" "$3"
}
run() { payload "$@" | bash "$scripts/guard-tracker-transition.sh" 2>/dev/null; }
verdict_of() {
  if [ -z "$1" ]; then echo allow
  elif printf '%s' "$1" | grep -q '"permissionDecision":"deny"'; then echo deny
  else echo "unexpected: $1"; fi
}
check() {
  local expectation=$1 label=$2
  shift 2
  expect_eq "$label" "$expectation" "$(verdict_of "$(run "$@")")"
}

readonly TOOL=mcp__tracker__transitionIssue
readonly REVIEW='{"issueIdOrKey":"ABC-1","transitionName":"In Review"}'
list=$work_dir/list-repo plain=$work_dir/plain-repo none=$work_dir/not-a-repo

check deny  "blocked: move to review, repo with a checklist and no verdicts" PreToolUse $TOOL "$REVIEW" "$list"
save_verdicts '- [PASS] The walkthrough video is in the How to test section.\n- [FAIL] The assignee is the named reviewer.\n'
check deny  "blocked: a FAIL box" PreToolUse $TOOL "$REVIEW" "$list"
out=$(run PreToolUse $TOOL "$REVIEW" "$list")
expect_contains "the block names the box, one line" "FAIL: The assignee is the named reviewer." "$out"
expect_contains "the block gives the command to record verdicts" "ready-receipt.sh write $head_sha --verdicts" "$out"
save_verdicts '- [PASS] The assignee is the named reviewer.\n'
expect_contains "the block names a box with no verdict" "no verdict: The walkthrough video is in the How to test section." "$(run PreToolUse $TOOL "$REVIEW" "$list")"
save_verdicts '- [PASS] The walkthrough video is in the How to test section.\n- [N/A] The assignee is the named reviewer.\n'
check deny  "blocked: N/A with no reason" PreToolUse $TOOL "$REVIEW" "$list"
save_verdicts '- [PASS] The walkthrough video is in the How to test section.\n- [N/A: the author reviews their own repo] The assignee is the named reviewer.\n'
check allow "allowed: every box PASS or N/A with a reason" PreToolUse $TOOL "$REVIEW" "$list"
check allow "allowed: move to a status that is not review (verdicts or not)" PreToolUse $TOOL '{"issueIdOrKey":"ABC-1","transitionName":"Done"}' "$list"
check allow "allowed: a transition named by id only can't be read" PreToolUse $TOOL '{"issueIdOrKey":"ABC-1","transitionId":"31"}' "$list"
check allow "allowed: a repo with no checklist file" PreToolUse $TOOL "$REVIEW" "$plain"
check allow "allowed: a tool that does not transition" PreToolUse mcp__tracker__addComment '{"issueIdOrKey":"ABC-1","comment":"ready for review"}' "$list"
rm "$KC_READY_DIR/$head_sha.checklist"
check allow "allowed: user said to skip (token in the input)" PreToolUse $TOOL '{"issueIdOrKey":"ABC-1","transitionName":"In Review","comment":"KC_READY_SKIP=1"}' "$list"
expect_eq "allowed: user said to skip (environment)" allow "$(verdict_of "$(payload PreToolUse $TOOL "$REVIEW" "$list" | KC_READY_SKIP=1 bash "$scripts/guard-tracker-transition.sh" 2>/dev/null)")"
check deny  "blocked: the verdicts were removed" PreToolUse $TOOL "$REVIEW" "$list"

# A generic execute tool names the operation in its input.
EXEC='{"name":"transitionJiraIssue","inputs":{"issueIdOrKey":"ABC-1","transition":{"name":"Code Review"}}}'
check deny  "blocked: a generic execute tool running a transition to review" PreToolUse mcp__tracker__executeWrite "$EXEC" "$list"
check allow "allowed: a generic execute tool creating an issue" PreToolUse mcp__tracker__executeWrite '{"name":"createJiraIssue","inputs":{"summary":"Review the totals"}}' "$list"
check allow "allowed: a generic execute tool moving to another status" PreToolUse mcp__tracker__executeWrite '{"name":"transitionJiraIssue","inputs":{"issueIdOrKey":"ABC-1","transition":{"name":"Blocked"}}}' "$list"

check allow "allowed: a generic execute tool running another operation that mentions a review status" PreToolUse mcp__tracker__executeWrite '{"name":"updateJiraIssue","inputs":{"issueIdOrKey":"ABC-1","fields":{"status":"In Review"}}}' "$list"

# The status pattern can be set.
expect_eq "a status pattern from the environment: matching" deny "$(verdict_of "$(payload PreToolUse $TOOL '{"issueIdOrKey":"ABC-1","transitionName":"Ready for QA"}' "$list" | KC_REVIEW_STATUS_REGEX='review|qa' bash "$scripts/guard-tracker-transition.sh" 2>/dev/null)")"
expect_eq "a status pattern from the environment: review no longer matches" allow "$(verdict_of "$(payload PreToolUse $TOOL "$REVIEW" "$list" | KC_REVIEW_STATUS_REGEX='qa' bash "$scripts/guard-tracker-transition.sh" 2>/dev/null)")"

# Outside a repo, the receipt is found by the issue key.
check deny  "blocked: outside a repo, no verdicts recorded for the key" PreToolUse $TOOL "$REVIEW" "$none"
expect_contains "it names the key" "no checklist receipt names ABC-1" "$(run PreToolUse $TOOL "$REVIEW" "$none")"
check deny  "blocked: outside a repo, no issue key in the call" PreToolUse $TOOL '{"transitionName":"In Review"}' "$none"
save_verdicts '- [PASS] The walkthrough video is in the How to test section.\n- [FAIL] The assignee is the named reviewer.\n' --task ABC-1
check deny  "blocked: outside a repo, the key's verdicts have a FAIL box" PreToolUse $TOOL "$REVIEW" "$none"
expect_contains "it names the box" "FAIL: The assignee is the named reviewer." "$(run PreToolUse $TOOL "$REVIEW" "$none")"
save_verdicts '- [PASS] The walkthrough video is in the How to test section.\n- [PASS] The assignee is the named reviewer.\n' --task ABC-1
check allow "allowed: outside a repo, the key's verdicts are met" PreToolUse $TOOL "$REVIEW" "$none"
check deny  "blocked: outside a repo, another key has none" PreToolUse $TOOL '{"issueIdOrKey":"ABC-2","transitionName":"In Review"}' "$none"
check allow "allowed: outside a repo, a move to done" PreToolUse $TOOL '{"issueIdOrKey":"ABC-2","transitionName":"Done"}' "$none"

expect_eq "nothing is printed on an allowed move" "" "$(run PreToolUse $TOOL '{"issueIdOrKey":"ABC-1","transitionName":"Done"}' "$list")"

finish
