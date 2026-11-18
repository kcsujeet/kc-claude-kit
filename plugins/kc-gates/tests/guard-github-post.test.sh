#!/usr/bin/env bash
# Tests scripts/guard-github-post.sh: GitHub review writes without the
# approval token are denied; everything else passes silently. Each case runs
# twice, once with jq and once through the sed fallback. The cases at the end
# give a token and a transcript: a body the user was not shown before their
# latest message is denied (they need jq, which reads the transcript).
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
  "KC_REVIEW_POST_APPROVED=1 gh pr comment 12 --body-file /tmp/note.md"
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

# --- §PC3: token present, each posted body must have been shown before the user's latest message ---

if command -v jq >/dev/null 2>&1; then
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT

  user_line() { jq -nc --arg t "$1" '{type: "user", message: {role: "user", content: $t}}'; }
  assistant_line() { jq -nc --arg t "$1" '{type: "assistant", message: {role: "assistant", content: [{type: "text", text: $t}]}}'; }
  noise_lines() {
    jq -nc '{type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: "x", content: "ok"}]}}'
    jq -nc '{type: "user", message: {role: "user", content: "<system-reminder>note</system-reminder>"}}'
  }

  # before: the drafts, then the approval. after: the approval, then the drafts.
  { user_line "reply to the review"
    assistant_line $'Drafts:\n> Fixed in 1a2b3c4d5e6f.\n> Renamed the helper.'
    noise_lines
    user_line "yes, post them"; } > "$work/before.jsonl"
  { user_line "reply to the review"
    assistant_line "Ready to commit, push and reply?"
    user_line "yes"
    assistant_line "Fixed in 1a2b3c4d5e6f."; } > "$work/after.jsonl"
  { user_line "reply to the review"
    assistant_line 'Draft: Fixed in <full SHA>. Commit, push and reply?'
    user_line "yes"; } > "$work/placeholder.jsonl"
  printf '{"body":"Renamed the helper.","comments":[{"path":"a.rb","body":"Fixed in 1a2b3c4d5e6f."},{"path":"b.rb","body":"Never shown."}]}' > "$work/review.json"
  printf '{"body":"Renamed the helper.","comments":[{"path":"a.rb","body":"Fixed in 1a2b3c4d5e6f."}]}' > "$work/review-ok.json"
  # shellcheck source=../scripts/lib/file-sha256.sh
  . "$(dirname "$guard")/lib/file-sha256.sh"
  stamp_review_checked() { print_file_sha256 "$1" > "$1.checked"; }
  stamp_review_checked "$work/review.json"
  stamp_review_checked "$work/review-ok.json"
  # Built by the payload builder and then edited by hand, or never built by it.
  cp "$work/review-ok.json" "$work/review-edited.json"
  stamp_review_checked "$work/review-edited.json"
  printf '{"body":"Renamed the helper.","comments":[{"path":"a.rb","body":"Renamed the helper."}]}' > "$work/review-edited.json"
  cp "$work/review-ok.json" "$work/review-unbuilt.json"
  printf '{"body":"Renamed the helper."}' > "$work/review-body-only.json"

  # check_with_transcript <expectation> <label> <command> <transcript>
  check_with_transcript() {
    local expectation=$1 label=$2 command=$3 transcript=$4 mode output verdict payload
    for mode in jq sed; do
      payload=$(printf '{"session_id":"s","transcript_path":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"},"tool_use_id":"t"}' "$transcript" "$command")
      if [ "$mode" = sed ]; then
        output=$(printf '%s' "$payload" | KC_GUARD_NO_JQ=1 bash "$guard")
      else
        output=$(printf '%s' "$payload" | bash "$guard")
      fi
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
        echo "     actual:   $verdict $output"
        failures=$((failures + 1))
      fi
    done
  }

  token=KC_REVIEW_POST_APPROVED=1
  check_with_transcript allow "shown: body quoted in a draft before the approval" \
    "$token gh api repos/acme/widgets/issues/comments/9 -X PATCH -f body='Fixed in 1a2b3c4d5e6f.'" "$work/before.jsonl"
  check_with_transcript allow "shown: body in a --body argument" \
    "$token gh pr comment 12 --body 'Renamed the helper.'" "$work/before.jsonl"
  check_with_transcript deny  "not shown: body shown only after the latest user message" \
    "$token gh api repos/acme/widgets/issues/12/comments -X POST -f body='Fixed in 1a2b3c4d5e6f.'" "$work/after.jsonl"
  check_with_transcript deny  "not shown: draft had a placeholder, body has the real SHA" \
    "$token gh api repos/acme/widgets/issues/12/comments -X POST -F body='Fixed in 1a2b3c4d5e6f.'" "$work/placeholder.jsonl"
  check_with_transcript allow "shown: blockquoted draft posted without the marker" \
    "$token gh pr comment 12 -b 'Fixed in 1a2b3c4d5e6f. Renamed the helper.'" "$work/before.jsonl"
  # shellcheck disable=SC2016 # literal $( in the command
  check_with_transcript allow "shown: heredoc body between the delimiters" \
    "$token gh pr comment 12 --body '\$(cat <<EOF\nRenamed the helper.\nEOF\n)'" "$work/before.jsonl"
  check_with_transcript deny  "not shown: --input review with one comment never shown" \
    "$token gh api repos/acme/widgets/pulls/12/reviews -X POST --input $work/review.json" "$work/before.jsonl"
  check_with_transcript allow "shown: --input review whose bodies were all shown" \
    "$token gh api repos/acme/widgets/pulls/12/reviews -X POST --input $work/review-ok.json" "$work/before.jsonl"
  check_with_transcript deny  "unchecked: a review payload the builder never stamped" \
    "$token gh api repos/acme/widgets/pulls/12/reviews -X POST --input $work/review-unbuilt.json" "$work/before.jsonl"
  check_with_transcript deny  "unchecked: a review payload edited after the builder stamped it" \
    "$token gh api repos/acme/widgets/pulls/12/reviews -X POST --input $work/review-edited.json" "$work/before.jsonl"
  check_with_transcript allow "unchecked: a body-only review needs no stamp" \
    "$token gh api repos/acme/widgets/pulls/12/reviews -X POST --input $work/review-body-only.json" "$work/before.jsonl"
  check_with_transcript deny  "unchecked: a review payload read from stdin" \
    "$token gh api repos/acme/widgets/pulls/12/reviews -X POST --input - < $work/review-ok.json" "$work/before.jsonl"
  check_with_transcript deny  "unchecked: a review payload file that does not exist before the command" \
    "$token gh api repos/acme/widgets/pulls/12/reviews -X POST --input $work/written-later.json" "$work/before.jsonl"
  check_with_transcript deny  "unchecked: inline comments sent as fields" \
    "$token gh api repos/acme/widgets/pulls/12/reviews -X POST -f event=COMMENT -f 'comments[][path]=a.rb' -f 'comments[][body]=Renamed the helper.'" "$work/before.jsonl"
  check_with_transcript allow "unchecked: a review with only a body field needs no stamp" \
    "$token gh api repos/acme/widgets/pulls/12/reviews -X POST -f event=COMMENT -f body='Renamed the helper.'" "$work/before.jsonl"
  check_with_transcript deny  "unchecked: a new inline comment through the single-comment endpoint" \
    "$token gh api repos/acme/widgets/pulls/12/comments -X POST -f body='Fixed in 1a2b3c4d5e6f.' -F line=4" "$work/before.jsonl"
  check_with_transcript allow "unchecked: a reply in a thread is not an inline comment" \
    "$token gh api repos/acme/widgets/pulls/12/comments/55/replies -X POST -f body='Fixed in 1a2b3c4d5e6f.'" "$work/before.jsonl"
  check_with_transcript deny  "not shown: second write in a chain" \
    "$token gh pr comment 12 -b 'Fixed in 1a2b3c4d5e6f.' && $token gh pr comment 12 -b 'Never shown.'" "$work/before.jsonl"
  check_with_transcript allow "unreadable: body from a file is not checked" \
    "$token gh pr comment 12 --body-file /tmp/note.md" "$work/after.jsonl"
  check_with_transcript allow "unreadable: body from a shell substitution is not checked" \
    "$token gh pr comment 12 --body '\$(cat /tmp/note.md)'" "$work/after.jsonl"
  check_with_transcript allow "unreadable: no transcript file means no check" \
    "$token gh pr comment 12 -b 'Never shown.'" "$work/missing.jsonl"
  check_with_transcript allow "untouched: non-GitHub command carrying the token" \
    "$token git commit -m 'Never shown.'" "$work/after.jsonl"
  check_with_transcript allow "untouched: gh pr view with a body-like flag" \
    "$token gh pr view 12 -b 'Never shown.'" "$work/after.jsonl"
  check_with_transcript deny  "no token: existing deny unchanged" \
    "gh pr comment 12 -b 'Fixed in 1a2b3c4d5e6f.'" "$work/before.jsonl"
  check_with_transcript allow "non-GitHub command without token" \
    "git fetch origin" "$work/after.jsonl"
fi

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
