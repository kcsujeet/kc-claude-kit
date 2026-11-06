#!/usr/bin/env bash
# Tests scripts/guard-github-post.sh: GitHub review writes without the
# approval token are denied; everything else passes silently. Each case runs
# twice, once with jq and once through the sed fallback.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
guard="$(dirname "$tests_dir")/scripts/guard-github-post.sh"

passes=0
failures=0

# Wraps a shell command (no double quotes or backslashes in it) in the
# PreToolUse stdin payload.
build_payload() {
  printf '{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"test"},"tool_use_id":"t"}' "$1"
}

run_guard() {
  local command=$1 mode=$2
  if [ "$mode" = sed ]; then
    build_payload "$command" | KC_GUARD_NO_JQ=1 bash "$guard"
  else
    build_payload "$command" | bash "$guard"
  fi
}

check() {
  local expectation=$1 label=$2 command=$3 mode output verdict
  for mode in jq sed; do
    if [ "$mode" = jq ] && ! command -v jq >/dev/null 2>&1; then
      continue
    fi
    output=$(run_guard "$command" "$mode")
    if [ -z "$output" ]; then
      verdict=allow
    elif printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then
      verdict=deny
    else
      verdict="unexpected output: $output"
    fi
    if [ "$verdict" = "$expectation" ]; then
      echo "ok   [$mode] $label"
      passes=$((passes + 1))
    else
      echo "FAIL [$mode] $label"
      echo "     expected: $expectation"
      echo "     actual:   $verdict"
      failures=$((failures + 1))
    fi
  done
}

check deny  "blocked: gh pr comment" \
  "gh pr comment 12 --body-file /tmp/note.md"
check deny  "blocked: review POST through gh api" \
  "gh api repos/acme/widgets/pulls/12/reviews -X POST --input /tmp/review-12.json"
check deny  "blocked: gh pr review" \
  "gh pr review 12 --comment -b 'Looks off'"
check deny  "blocked: gh issue comment" \
  "gh issue comment 7 --body 'Thanks'"
check deny  "blocked: inline comment with fields and no method" \
  "gh api repos/acme/widgets/pulls/12/comments -f body='x' -F line=4"
check deny  "blocked: edit a posted comment" \
  "gh api repos/acme/widgets/pulls/comments/991 --method=PATCH --input /tmp/edit.json"
check deny  "blocked: write chained after a read" \
  "gh pr view 12 && gh api repos/acme/widgets/issues/12/comments -X POST -f body='hi'"

check allow "allowed: token in the same command" \
  "KC_REVIEW_POST_APPROVED=1 gh api repos/acme/widgets/pulls/12/reviews -X POST --input /tmp/review-12.json"
check allow "allowed: gh pr create" \
  "gh pr create --title 'Add widgets' --body-file /tmp/body.md"
check allow "allowed: gh pr merge" \
  "gh pr merge 12 --squash"
check allow "allowed: gh api GET on comments" \
  "gh api 'repos/acme/widgets/pulls/12/comments?per_page=100'"
check allow "allowed: explicit GET with query fields" \
  "gh api -X GET repos/acme/widgets/pulls/12/comments -f per_page=100"
check allow "allowed: gh pr view" \
  "gh pr view 12 --json headRefOid,title,files"
check allow "allowed: non-gh command" \
  "git diff main...HEAD > /tmp/review.diff"

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
