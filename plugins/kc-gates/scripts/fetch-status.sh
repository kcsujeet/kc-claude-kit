#!/usr/bin/env bash
# UserPromptSubmit hook: when the prompt asks where work stands (asks_status in lib/reply-misses.sh:
# "can it be merged", "is QA done", "what next", "status", "any update"), fetches the current state
# of the pull requests the session is working on and hands it to Claude before it writes a word, so
# the answer starts from what is true now, not from what Claude remembers of an earlier turn. A
# reminder to "read the state first" was not enough: a reply stated a ticket was still in testing
# when it had moved on an hour before. A Stop hook can't help either, because no hook runs between
# a reply being written and the person seeing it.
#
# Which pull requests: the current branch's, when the session runs in a git checkout, and the pull
# request URLs named most recently in the session's transcript, newest first, until
# KC_STATUS_MAX_PRS (default 3) have been read. A URL gh can't read (an example in a file, a pull
# request the account can't see) is skipped for the next one.
# Each is read with one `gh pr view` call: state, review decision and pending reviewers, merge
# state, head commit and its checks. A project adds its tracker (ticket status, assignee, latest
# comment) through its own UserPromptSubmit hook; this one reads only the code host.
#
# Input: the UserPromptSubmit payload on stdin (prompt, cwd, transcript_path). Output: the fetched
# state as context, or one line saying what could not be read. Prints nothing for a prompt that
# doesn't ask for status. Always exits 0; without jq or gh it says so and stops.
# Hook schema: https://code.claude.com/docs/en/hooks
set -u

# shellcheck source=lib/reply-misses.sh
. "$(dirname "$0")/lib/reply-misses.sh"

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
prompt=$(printf '%s' "$payload" | jq -r '.prompt // empty' 2>/dev/null)
asks_status "$prompt" || exit 0
cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
max_prs=${KC_STATUS_MAX_PRS:-3}
# One line per pull request: what it is, its review, and its merge and check state.
# shellcheck disable=SC2016  # a jq program: its $url is jq's, not the shell's
pr_summary_filter='
    def checks: [.statusCheckRollup[]? | (.conclusion // .status // .state // "" | ascii_downcase)];
    def count(s): [checks[] | select(. == s)] | length;
    "- \($url) \(.title)\n  state \(.state)\(if .isDraft then " (draft)" else "" end)\(if .mergedAt then ", merged \(.mergedAt)" else "" end); review \(if (.reviewDecision // "") == "" then "none" else .reviewDecision end)"
    + "; pending reviewers: \([.reviewRequests[]? | .login // .name] | join(", ") | if . == "" then "none" else . end)"
    + "; latest reviews: \([.latestReviews[]? | "\(.author.login) \(.state)"] | join(", ") | if . == "" then "none" else . end)"
    + "\n  merge state \(.mergeStateStatus // "unknown"); head \(.headRefOid[0:9]); checks: \(count("success")) passed, \(count("failure") + count("error") + count("cancelled") + count("timed_out")) failed, \(count("in_progress") + count("queued") + count("pending") + count("expected")) running, \(checks | length) total"'

if ! command -v gh >/dev/null 2>&1; then
  echo "Status prompt: gh is not installed, so no pull request state was fetched. Read it with a tool before stating it."
  exit 0
fi

# The candidates: the branch's pull request first, then the transcript's URLs, newest first.
candidates=()
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  branch_pr=$(cd "$cwd" && gh pr view --json url -q .url 2>/dev/null)
  [ -n "$branch_pr" ] && candidates+=("$branch_pr")
fi
if [ -r "$transcript" ]; then
  while IFS= read -r url; do
    [ -n "$url" ] && candidates+=("$url")
  done <<EOF
$(grep -Eo 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+' "$transcript" 2>/dev/null | awk '{ lines[NR] = $0 } END { for (i = NR; i >= 1; i--) if (!seen[lines[i]]++) print lines[i] }')
EOF
fi

read_count=0
summary=""
for url in "${candidates[@]+"${candidates[@]}"}"; do
  [ "$read_count" -ge "$max_prs" ] && break
  case "$summary" in *"- $url "*) continue ;; esac
  pr_json=$(gh pr view "$url" --json number,title,state,isDraft,reviewDecision,mergeStateStatus,headRefOid,mergedAt,reviewRequests,latestReviews,statusCheckRollup 2>/dev/null) || continue
  read_count=$((read_count + 1))
  summary="$summary$(printf '%s' "$pr_json" | jq -r --arg url "$url" "$pr_summary_filter")
"
done

if [ "$read_count" -eq 0 ]; then
  echo "Status prompt: no pull request could be read for this session (none for the branch, none named in the transcript that gh can open). Read the state with a tool before stating it."
  exit 0
fi
echo "Status prompt: fetched just now, before your reply. Answer from this, not from memory of earlier turns; read again anything it doesn't cover (the ticket, a comment) before stating it."
printf '%s' "$summary"
exit 0
