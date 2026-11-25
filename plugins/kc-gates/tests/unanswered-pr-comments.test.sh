#!/usr/bin/env bash
# Tests scripts/unanswered-pr-comments.sh with the stub gh: it lists each inline or top-level
# comment on the branch's PR that its author has not answered (a bot's top-level comment is
# skipped, its inline comments are not), passes when
# every comment has a later reply from the author, and passes with a note when there is no PR.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
script="$(dirname "$tests_dir")/scripts/unanswered-pr-comments.sh"
fixtures="$tests_dir/fixtures/unanswered-pr-comments"
require_jq
use_gh_fixtures "$fixtures/none"

run_with() {
  export KC_GH_ROUTES="$fixtures/$1/routes.tsv"
  status=0
  output=$(bash "$script" 2>&1) || status=$?
}

run_with unanswered
expect_eq "unanswered comments exit 1" 1 "$status"
expect_contains "an unanswered inline bot comment is named by path:line and author" "src/total.ts:12 @review-bot[bot]: This rounds down." "$output"
expect_contains "an unanswered top-level human comment is named" "top-level @sam: Can you add a test?" "$output"
expect_not_contains "a top-level comment from a [bot] login is skipped" "coverage-bot" "$output"
expect_not_contains "a top-level comment from a Bot-type account without [bot] is skipped" "preview-deploys" "$output"
expect_not_contains "a top-level comment from a [bot] login with no type is skipped" "tracker-link" "$output"
case "$output" in
  *"src/tax.ts"*) record "an inline thread the author replied to is not listed" fail "$output" ;;
  *) record "an inline thread the author replied to is not listed" ok ;;
esac
case "$output" in
  *"@me"*) record "the author's own comments are not listed" fail "$output" ;;
  *) record "the author's own comments are not listed" ok ;;
esac

run_with answered
expect_eq "every comment answered exits 0" 0 "$status"
expect_eq "and prints nothing" "" "$output"

run_with none
expect_eq "no PR for the branch exits 0" 0 "$status"
expect_contains "and says the comments were not checked" "PR comments not checked" "$output"

finish
