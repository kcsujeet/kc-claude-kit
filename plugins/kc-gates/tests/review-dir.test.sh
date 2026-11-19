#!/usr/bin/env bash
# Tests scripts/lib/review-dir.sh: has_review_files knows a saved review by its diff and changed
# files, and find_review_dir picks the newest saved review for a repo and a pull request.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
# shellcheck source=../scripts/lib/review-dir.sh
. "$(dirname "$tests_dir")/scripts/lib/review-dir.sh"

TMPDIR=$work_dir/tmp
mkdir -p "$TMPDIR"
export TMPDIR

# Saves a review the way gather-review.sh does: save_review <folder> <pr> <owner/repo> <age-seconds>.
save_review() {
  local folder=$TMPDIR/$1
  mkdir -p "$folder"
  : > "$folder/review.diff"
  : > "$folder/changed-files.txt"
  printf 'HEAD_SHA=abc\nPR=%s\nURL=https://github.com/%s/pull/%s\n' "$2" "$3" "$2" > "$folder/meta.env"
  perl -e 'utime(time - $ARGV[1], time - $ARGV[1], $ARGV[0])' "$folder/meta.env" "$4"
}

save_review kc-review-old 12 acme/shop 300
save_review kc-review-new 12 acme/shop 60
save_review kc-review-other-pr 13 acme/shop 10
save_review kc-review-other-repo 12 acme/storefront 5

if has_review_files "$TMPDIR/kc-review-new"; then verdict=yes; else verdict=no; fi
expect_eq "a folder with its diff and changed files is a review" yes "$verdict"
mkdir -p "$TMPDIR/kc-review-empty"
if has_review_files "$TMPDIR/kc-review-empty"; then verdict=yes; else verdict=no; fi
expect_eq "a folder without them is not" no "$verdict"
if has_review_files ""; then verdict=yes; else verdict=no; fi
expect_eq "no folder is not a review" no "$verdict"

expect_eq "the newest review of the repo and pull request" "$TMPDIR/kc-review-new" "$(find_review_dir acme/shop 12)"
expect_eq "another pull request of the repo" "$TMPDIR/kc-review-other-pr" "$(find_review_dir acme/shop 13)"
expect_eq "no pull request named: the repo's newest" "$TMPDIR/kc-review-other-pr" "$(find_review_dir acme/shop "")"
expect_eq "nothing named: the newest of all" "$TMPDIR/kc-review-other-repo" "$(find_review_dir "" "")"
expect_eq "no saved review for the pull request: nothing" "" "$(find_review_dir acme/shop 99)"
rm -f "$TMPDIR/kc-review-new/changed-files.txt"
expect_eq "a folder missing its files is skipped" "$TMPDIR/kc-review-old" "$(find_review_dir acme/shop 12)"

finish
