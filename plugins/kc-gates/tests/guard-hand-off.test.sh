#!/usr/bin/env bash
# Tests scripts/guard-hand-off.sh and scripts/ready-receipt.sh: handing a PR
# to review is denied unless its head commit has a receipt, against the stub
# gh in lib/ answering from fixtures/guard-hand-off/ (PR 12 and the --head
# branch `feature` are at the reviewed commit, PR 13 is not). Each guard case
# runs twice, once with jq and once through the sed fallback.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
require_jq
use_gh_fixtures "$tests_dir/fixtures/guard-hand-off"
export KC_READY_DIR="$work_dir/receipts"

reviewed=$(printf 'a%.0s' {1..40})
unreviewed=$(printf 'b%.0s' {1..40})
# Two local repos for `gh pr create` without --head: one whose HEAD has a
# receipt, one whose HEAD has none.
make_repo() {
  git init -q "$1"
  git -C "$1" -c user.name=t -c user.email=t@example.test commit -q --allow-empty -m "$2"
}
make_repo "$work_dir/ready-repo" ready
make_repo "$work_dir/draft-repo" draft

receipt=$(bash "$scripts/ready-receipt.sh" write "$reviewed" --rounds 2 --open 1)
expect_contains "receipt: written for the reviewed commit" "$KC_READY_DIR/$reviewed" "$receipt"
bash "$scripts/ready-receipt.sh" write "$(git -C "$work_dir/ready-repo" rev-parse HEAD)" --rounds 1 --open 0 >/dev/null
if bash "$scripts/ready-receipt.sh" write "$unreviewed" --after "$(printf 'c%.0s' {1..40})" >/dev/null 2>&1; then
  record "receipt: --after refuses a pass with no receipt" fail "it wrote one"
else
  record "receipt: --after refuses a pass with no receipt" ok
fi
if bash "$scripts/ready-receipt.sh" write "$reviewed" --rounds 3 --open 0 >/dev/null 2>&1; then
  record "receipt: a third round is refused" fail "it wrote one"
else
  record "receipt: a third round is refused" ok
fi
if bash "$scripts/ready-receipt.sh" check "$unreviewed" >/dev/null; then
  record "receipt: check fails for a commit without one" fail "check passed"
else
  record "receipt: check fails for a commit without one" ok
fi

# Wraps a shell command (no double quotes or backslashes in it) and a working
# directory in the PreToolUse stdin payload.
build_payload() {
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"test"},"tool_use_id":"t"}' "$2" "$1"
}

check() {
  local expectation=$1 label=$2 command=$3 cwd=${4:-$work_dir/ready-repo} mode output verdict
  for mode in jq sed; do
    if [ "$mode" = sed ]; then
      output=$(build_payload "$command" "$cwd" | KC_GUARD_NO_JQ=1 bash "$scripts/guard-hand-off.sh")
    else
      output=$(build_payload "$command" "$cwd" | bash "$scripts/guard-hand-off.sh")
    fi
    if [ -z "$output" ]; then
      verdict=allow
    elif printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then
      verdict=deny
    else
      verdict="unexpected output: $output"
    fi
    expect_eq "[$mode] $label" "$expectation" "$verdict"
  done
}

check deny  "blocked: gh pr ready on an unreviewed PR" \
  "gh pr ready 13"
check deny  "blocked: adding a reviewer to an unreviewed PR" \
  "gh pr edit 13 --repo acme/widgets --add-reviewer ana"
check deny  "blocked: opening a ready PR from an unreviewed HEAD" \
  "gh pr create --title 'Add widgets' --body-file /tmp/body.md" "$work_dir/draft-repo"
check deny  "blocked: cd into an unreviewed repo, then gh pr create" \
  "cd $work_dir/draft-repo && gh pr create --fill"
check deny  "blocked: reviewer request through gh api" \
  "gh api repos/acme/widgets/pulls/13/requested_reviewers -X POST -f 'reviewers[]=ana'"
check deny  "blocked: head commit cannot be found" \
  "gh pr ready 99"

check allow "allowed: gh pr ready on a reviewed PR" \
  "gh pr ready 12 --repo acme/widgets"
check allow "allowed: current branch's PR is reviewed" \
  "gh pr edit --add-reviewer ana"
check allow "allowed: reviewer request on a reviewed PR" \
  "gh api repos/acme/widgets/pulls/12/requested_reviewers -X POST -f 'reviewers[]=ana'"
check allow "allowed: ready PR whose --head branch is reviewed" \
  "gh pr create --repo acme/widgets --head feature --fill"
check allow "allowed: ready PR whose --head branch is reviewed, repo from the directory" \
  "gh pr create --head=feature --fill"
check allow "allowed: ready PR from a reviewed HEAD" \
  "gh pr create --title 'Add widgets' --body-file /tmp/body.md"
check allow "allowed: cd into a reviewed repo, then gh pr create" \
  "cd $work_dir/ready-repo && gh pr create --fill" "$work_dir/draft-repo"
check allow "allowed: draft PR" \
  "gh pr create --draft --fill" "$work_dir/draft-repo"
check allow "allowed: back to draft" \
  "gh pr ready 13 --undo"
check allow "allowed: edit without a reviewer" \
  "gh pr edit 13 --title 'Add widgets'"
check allow "allowed: user said to skip the pass" \
  "KC_READY_SKIP=1 gh pr ready 13"
check allow "allowed: reading reviewers" \
  "gh api repos/acme/widgets/pulls/13/requested_reviewers"
check allow "allowed: gh pr view" \
  "gh pr view 13 --json headRefOid"
check allow "allowed: non-gh command" \
  "git push origin HEAD"

finish
