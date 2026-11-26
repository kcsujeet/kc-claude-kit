#!/usr/bin/env bash
# PreToolUse hook (Agent): no verification-gate dispatch while the review's walk receipt fails.
# kc-code-review's walk rule says every behaviour a diff changes is seen on its QA surface (browser,
# API, terminal, unit) before the verdict; guard-github-post.sh already refuses to post or approve
# such a review, and the verification gate is the review's phase 2, which comes right before the
# verdict, so holding its dispatch holds the verdict at the action that leads to it. The check ran
# at Stop before; a Stop hook runs after the reply was read, so it only showed a second copy.
#
# The review is the `$KC_REVIEW_DIR` folder, or else the newest saved `${TMPDIR:-/tmp}/kc-review-*`
# folder from the last day (gather-review.sh; lib/review-dir.sh) whose head commit is in the git
# checkout the session runs in (the payload's cwd), so another session's review in another repo
# never holds this one's dispatches. select-gates.sh is run on its diff, and check-walk-receipt.sh
# on its walk-receipt.tsv. While that check fails, a dispatch of `kc-gates:verification-gate` is
# denied, so the walk comes first. The report's shape (§G6) and its confirmed findings (§G7) are
# checked by kc-code-review's own step, which runs check-review-report.sh and
# check-report-findings.sh on the drafted report before it is sent.
# Everything the guard can't read (no jq, no review folder, select-gates.sh failing) lets the
# action through: it never blocks what it can't read. Always exits 0.
# Hook schema: https://code.claude.com/docs/en/hooks
set -u

# shellcheck source=lib/review-dir.sh
. "$(dirname "$0")/lib/review-dir.sh"

# Prints check-walk-receipt.sh's problems for the saved review; nothing when it passes or can't run.
get_walk_problems() {
  local scripts_dir review_dir selected
  scripts_dir=$(dirname "$0")
  review_dir=$(session_review_dir)
  has_review_files "$review_dir" || return 0
  selected=$(mktemp)
  if bash "$scripts_dir/select-gates.sh" "$review_dir/review.diff" "$review_dir/changed-files.txt" . > "$selected" 2>/dev/null; then
    bash "$scripts_dir/check-walk-receipt.sh" "$selected" "$review_dir/walk-receipt.tsv" 2>&1 | tr '\n' ' ' | cut -c1-600
  fi
  rm -f "$selected"
}

# Prints $KC_REVIEW_DIR, or the newest saved review gathered from the session's checkout.
session_review_dir() {
  local found
  if [ -n "${KC_REVIEW_DIR:-}" ]; then printf '%s' "$KC_REVIEW_DIR"; return 0; fi
  found=$(find_review_dir "" "")
  [ -n "$found" ] && review_belongs_to "$found" "$session_cwd" && printf '%s' "$found"
  return 0
}

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
session_cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$session_cwd" ] || session_cwd=$PWD
[ "$(printf '%s' "$payload" | jq -r '.hook_event_name // empty' 2>/dev/null)" = PreToolUse ] || exit 0
[ "$(printf '%s' "$payload" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)" = kc-gates:verification-gate ] || exit 0

problems=$(get_walk_problems)
[ -n "$problems" ] || exit 0
walk_steps="Walk each changed behaviour on its QA surface (browser, API, terminal, unit), as every audience that can reach it (signed out too for a public path, replaying each write with another record's id and again with the same id), and write one line per walk-item to walk-receipt.tsv beside review.diff: path, what was seen, evidence (the surface's evidence: browser a screenshot or recording path, api a curl request and its saved response, terminal or unit a run transcript, exit 0: run.txt)."
block_reason="Blocked by the kc-gates plugin: the review has items it has not walked, so the verification gate cannot run yet (it audits the walk receipt). $walk_steps Then dispatch it again. $problems"
printf '%s' "$block_reason" | jq -Rsc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: .}}'
exit 0
