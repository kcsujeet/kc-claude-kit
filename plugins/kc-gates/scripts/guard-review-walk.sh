#!/usr/bin/env bash
# Hook: no review verdict while the review's walk receipt fails. kc-code-review's walk rule says
# every behaviour a diff changes is seen in the running app or at the API before the verdict;
# guard-github-post.sh already refuses to post or approve such a review, and this guard holds the
# verdict itself, so a review is never called done in chat with its walk skipped.
#
# The review is the `$KC_REVIEW_DIR` folder, or else the newest saved `${TMPDIR:-/tmp}/kc-review-*`
# folder from the last day (gather-review.sh; lib/review-dir.sh). select-gates.sh is run on its
# diff, and check-walk-receipt.sh on its walk-receipt.tsv. While that check fails:
#   - PreToolUse (Agent): a dispatch of the verification gate (`kc-gates:verification-gate`, the
#     review's phase 2, which comes right before the verdict) is denied, so the walk comes first;
#   - Stop: a reply that gives a review verdict (a `### Review:` heading or a `Verdict: PASSED` /
#     `FAILED` line) is blocked, so Claude walks the items or takes the verdict back. It blocks
#     again on a second try (`stop_hook_active`): a reply that holds no verdict, saying the review
#     is not finished and what the walk needs, is the way out when the walk can't be run;
#   - Stop: a reply that asks the person whether to walk, QA or try the change in the running app is
#     blocked too: the walk is required by the review, so it is done and never offered as a choice.
#     Saying the review is not finished, without asking, passes.
# Everything the guard can't read (no jq, no review folder, select-gates.sh failing) lets the
# action through: it never blocks what it can't read. Always exits 0.
# Hook schema: https://code.claude.com/docs/en/hooks
set -u

# shellcheck source=lib/review-dir.sh
. "$(dirname "$0")/lib/review-dir.sh"

# True when the text on stdin gives a review verdict, in kc-code-review's report shapes.
is_review_verdict() {
  grep -Eq '^#{2,4} Review:|Verdict:[^A-Za-z]*(PASSED|FAILED)'
}

# True when the text on stdin asks the person whether to walk, QA or try the change in the running
# app: a question sentence naming a walk or QA, or naming a try, test, run, check or open of it in
# the app, browser or locally. The review's walk is required, so it is done, not offered.
is_walk_offer() {
  grep -Eo '[^.!?]*\?' | grep -Eiq '(^|[^[:alnum:]])(walk(ing|ed)?|qa)([^[:alnum:]]|$)|(^|[^[:alnum:]])(try(ing)?|test(ing)?|run(ning)?|check(ing)?|open(ing)?|see(ing)?|verify(ing)?)([^[:alnum:]].*)?[^[:alnum:]](the (running )?app|in the browser|the browser|locally|dev server|in a browser|on staging)([^[:alnum:]]|$)'
}

# Prints check-walk-receipt.sh's problems for the saved review; nothing when it passes or can't run.
get_walk_problems() {
  local scripts_dir review_dir selected
  scripts_dir=$(dirname "$0")
  review_dir=${KC_REVIEW_DIR:-$(find_review_dir "" "")}
  has_review_files "$review_dir" || return 0
  selected=$(mktemp)
  if bash "$scripts_dir/select-gates.sh" "$review_dir/review.diff" "$review_dir/changed-files.txt" . > "$selected" 2>/dev/null; then
    bash "$scripts_dir/check-walk-receipt.sh" "$selected" "$review_dir/walk-receipt.tsv" 2>&1 | tr '\n' ' ' | cut -c1-600
  fi
  rm -f "$selected"
}

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
event=$(printf '%s' "$payload" | jq -r '.hook_event_name // empty' 2>/dev/null)
case "$event" in
  PreToolUse)
    [ "$(printf '%s' "$payload" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)" = kc-gates:verification-gate ] || exit 0
    ;;
  Stop)
    reply=$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty' 2>/dev/null)
    if printf '%s' "$reply" | is_review_verdict; then
      stop_kind=verdict
    elif printf '%s' "$reply" | is_walk_offer; then
      stop_kind=offer
    else
      exit 0
    fi
    ;;
  *) exit 0 ;;
esac

problems=$(get_walk_problems)
[ -n "$problems" ] || exit 0
walk_steps="Walk each changed behaviour in the running app or at the API, as every audience that can reach it (signed out too for a public path, replaying each write with another record's id and again with the same id), and write one line per walk-item to walk-receipt.tsv beside review.diff: path, what was seen, evidence (a screenshot or recording path, or a request line with its status)."
if [ "$event" = PreToolUse ]; then
  block_reason="Blocked by the kc-gates plugin: the review has items it has not walked, so the verification gate cannot run yet (it audits the walk receipt). $walk_steps Then dispatch it again. $problems"
  printf '%s' "$block_reason" | jq -Rsc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: .}}'
elif [ "${stop_kind:-}" = offer ]; then
  block_reason="Blocked by the kc-gates plugin: this reply asks whether to walk or try the change in the running app, but the review requires that walk, so it is not a choice to offer. Do it now. $walk_steps $problems"
  printf '%s' "$block_reason" | jq -Rsc '{decision: "block", reason: .}'
else
  block_reason="Blocked by the kc-gates plugin: this reply gives a review verdict, but the review has items it has not walked, so the review is not finished. $walk_steps Then give the verdict. If the walk cannot be run here, reply without a verdict: say the review is not finished, which items are unwalked and what the walk needs. $problems"
  printf '%s' "$block_reason" | jq -Rsc '{decision: "block", reason: .}'
fi
exit 0
