#!/usr/bin/env bash
# Hook: no review verdict while the review's walk receipt fails. kc-code-review's walk rule says
# every behaviour a diff changes is seen on its QA surface (browser, API, terminal, unit) before the verdict;
# guard-github-post.sh already refuses to post or approve such a review, and this guard holds the
# verdict itself, so a review is never called done in chat with its walk skipped.
#
# The review is the `$KC_REVIEW_DIR` folder, or else the newest saved `${TMPDIR:-/tmp}/kc-review-*`
# folder from the last day (gather-review.sh; lib/review-dir.sh) whose head commit is in the git
# checkout the session runs in (the payload's cwd), so another session's review in another repo
# never holds this one's replies. select-gates.sh is run on its
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
#   - Stop: a reply that gives a verdict is also run through check-review-report.sh (§G6) and
#     blocked when its report does not lead with the does-it-work section or leaves a style
#     finding unlabeled, so the reader sees effectiveness and blast radius first. A reply with no
#     verdict is never checked.
#   - Stop: a reply that gives a verdict is also run through check-report-findings.sh when the
#     review folder has a verdicts/ directory (kc-code-review Step 4 saves each gate block there):
#     every finding a gate confirmed, cited as path:line, must be in the reply by file basename
#     and line, or on a "Dropped:" line, so a confirmed finding never vanishes from the report.
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
  review_dir=$(session_review_dir)
  has_review_files "$review_dir" || return 0
  selected=$(mktemp)
  if bash "$scripts_dir/select-gates.sh" "$review_dir/review.diff" "$review_dir/changed-files.txt" . > "$selected" 2>/dev/null; then
    uses_arg=()
    if [ -r "$review_dir/uses.txt" ]; then uses_arg=("$review_dir/uses.txt"); fi
    bash "$scripts_dir/check-walk-receipt.sh" "$selected" "$review_dir/walk-receipt.tsv" ${uses_arg[@]+"${uses_arg[@]}"} 2>&1 | tr '\n' ' ' | cut -c1-600
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
if [ -z "$problems" ]; then
  report_problems=
  report_problems_max_chars=600
  findings_problems=
  findings_problems_max_chars=1200
  is_verdict_reply=false
  [ "${stop_kind:-}" = verdict ] && is_verdict_reply=true
  if "$is_verdict_reply"; then
    review_dir=$(session_review_dir)
    verdicts_dir=$review_dir/verdicts
    report_problems=$(printf '%s' "$reply" | bash "$(dirname "$0")/check-review-report.sh" - 2>&1 | tr '\n' ' ' | cut -c1-"$report_problems_max_chars")
    if has_review_files "$review_dir" && [ -d "$verdicts_dir" ]; then
      findings_problems=$(printf '%s' "$reply" | bash "$(dirname "$0")/check-report-findings.sh" "$verdicts_dir" - 2>&1 | tr '\n' ' ' | cut -c1-"$findings_problems_max_chars")
    fi
  fi
  has_report_problems=false
  [ -n "$report_problems" ] && has_report_problems=true
  has_findings_problems=false
  [ -n "$findings_problems" ] && has_findings_problems=true
  if "$has_findings_problems" && ! "$has_report_problems"; then
    block_reason="Blocked by the kc-gates plugin: this reply gives a review verdict, but the report leaves out findings the gates confirmed. Add each to the report, or list it on a \"Dropped: <file:line> <reason>\" line that names the finding as file:line and says why. $findings_problems"
    printf '%s' "$block_reason" | jq -Rsc '{decision: "block", reason: .}'
  elif "$has_report_problems"; then
    block_reason="Blocked by the kc-gates plugin: this reply gives a review verdict, but its report does not lead with whether the change works and what it can break. Add a \"**Does it work / what can it break**\" section right under the \`### Review:\` title, above the gate table: what was measured with before and after numbers (or \"not measured: <why>\"), and a \"Uses:\" line with the trace-uses.sh count and which uses were run or checked. End each naming and clarity finding with \"(non-blocking)\". $report_problems"
    "$has_findings_problems" && block_reason="$block_reason $findings_problems"
    printf '%s' "$block_reason" | jq -Rsc '{decision: "block", reason: .}'
  fi
  exit 0
fi
walk_steps="Walk each changed behaviour on its QA surface (browser, API, terminal, unit), as every audience that can reach it (signed out too for a public path, replaying each write with another record's id and again with the same id), and write one line per walk-item to walk-receipt.tsv beside review.diff: path, what was seen, evidence (the surface's evidence: browser a screenshot or recording path, api a curl request and its saved response, terminal or unit a run transcript, exit 0: run.txt)."
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
