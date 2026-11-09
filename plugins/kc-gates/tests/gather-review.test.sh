#!/usr/bin/env bash
# Tests scripts/gather-review.sh. Branch mode runs against scratch git repos
# with no remote (so the base falls back to main, then master); PR mode runs
# against the stub gh in lib/, answering from fixtures/gather-review/.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
gather="$(dirname "$tests_dir")/scripts/gather-review.sh"
fixtures="$tests_dir/fixtures/gather-review"
require_jq

# Creates a repo at <dir> on branch <default>, with one commit there and one on
# a `feature` branch that edits a.txt and adds b.txt; leaves `feature` checked out.
make_repo() {
  local repo_dir=$1 default_branch=$2
  mkdir -p "$repo_dir"
  git -C "$repo_dir" init -q
  git -C "$repo_dir" symbolic-ref HEAD "refs/heads/$default_branch"
  git -C "$repo_dir" config user.email test@example.com
  git -C "$repo_dir" config user.name Test
  printf 'one\n' > "$repo_dir/a.txt"
  git -C "$repo_dir" add a.txt
  git -C "$repo_dir" commit -q -m base
  git -C "$repo_dir" checkout -q -b feature
  printf 'one\ntwo\n' > "$repo_dir/a.txt"
  printf 'new\n' > "$repo_dir/b.txt"
  git -C "$repo_dir" add a.txt b.txt
  git -C "$repo_dir" commit -q -m feature
}

# --- branch mode, falling back to main ---------------------------------------
repo="$work_dir/repo-main"
make_repo "$repo" main
# A user who sets diff.noprefix still gets a/ and b/ paths in the saved diff.
git -C "$repo" config diff.noprefix true
head_sha=$(git -C "$repo" rev-parse HEAD)
out="$work_dir/out-main"
branch_output=$(cd "$repo" && bash "$gather" --branch --out-dir "$out")
expect_eq "branch: meta.env printed, base falls back to main" "HEAD_SHA=$head_sha
BASE=main
TITLE=feature
DIFF_FILE=$out/review.diff
CHANGED_FILES=$out/changed-files.txt" "$branch_output"
expect_eq "branch: stdout is meta.env" "$branch_output" "$(cat "$out/meta.env")"
expect_eq "branch: changed files" "a.txt
b.txt" "$(cat "$out/changed-files.txt")"
expect_contains "branch: diff keeps b/ prefixes despite diff.noprefix" "+++ b/b.txt" "$(cat "$out/review.diff")"
expect_contains "branch: diff carries the added line" "+two" "$(cat "$out/review.diff")"

# Default out dir under TMPDIR, named by the head SHA.
mkdir -p "$work_dir/tmp"
default_output=$(cd "$repo" && TMPDIR="$work_dir/tmp/" bash "$gather" --branch)
expect_contains "branch: default out dir is \$TMPDIR/kc-review-<sha>" \
  "DIFF_FILE=$work_dir/tmp/kc-review-$head_sha/review.diff" "$default_output"

# An explicit base wins over the fallback.
base_sha=$(git -C "$repo" rev-parse main)
explicit_output=$(cd "$repo" && bash "$gather" --branch "$base_sha" --out-dir "$work_dir/out-explicit")
expect_contains "branch: explicit base is used" "BASE=$base_sha" "$explicit_output"

# --- branch mode, falling back to master -------------------------------------
repo_master="$work_dir/repo-master"
make_repo "$repo_master" master
master_output=$(cd "$repo_master" && bash "$gather" --branch --out-dir "$work_dir/out-master")
expect_contains "branch: base falls back to master when main is absent" "BASE=master" "$master_output"

# --- PR mode, against the stub gh --------------------------------------------
use_gh_fixtures "$fixtures"
pr_out="$work_dir/out-pr"
pr_output=$(cd "$repo" && bash "$gather" 12 --out-dir "$pr_out")
expect_eq "pr: meta.env with PR, URL, a quoted title, and FETCH when HEAD differs" "HEAD_SHA=1111111111111111111111111111111111111111
BASE=main
TITLE='Add widget list'\\''s header with a stray newline'
PR=12
URL=https://github.com/acme/widgets/pull/12
DIFF_FILE=$pr_out/review.diff
CHANGED_FILES=$pr_out/changed-files.txt
FETCH='git fetch origin pull/12/head:pr-12'" "$pr_output"
# shellcheck source=/dev/null # written by the run above
sourced_title=$(TITLE="" && . "$pr_out/meta.env" && printf '%s' "$TITLE")
expect_eq "pr: meta.env sources back to the original title" "Add widget list's header with a stray newline" "$sourced_title"
expect_file "pr: review.diff is gh pr diff's output" "$fixtures/pr.diff" "$pr_out/review.diff"
expect_eq "pr: changed files from gh pr view" "src/widgets/list.ts
src/widgets/header.tsx" "$(cat "$pr_out/changed-files.txt")"
expect_eq "pr: only read calls reached gh" "pr view 12 --json headRefOid,baseRefName,title,files,url
pr diff 12 --color never" "$(cat "$KC_GH_LOG")"

# When the local HEAD is the PR head, no FETCH line.
matching_fixtures="$work_dir/fixtures-matching"
cp -R "$fixtures" "$matching_fixtures"
sed "s/1111111111111111111111111111111111111111/$head_sha/" "$fixtures/pr-view.json" > "$matching_fixtures/pr-view.json"
use_gh_fixtures "$matching_fixtures"
matching_output=$(cd "$repo" && bash "$gather" 12 --out-dir "$work_dir/out-pr-matching")
case "$matching_output" in
  *FETCH=*) record "pr: no FETCH when the local HEAD is the PR head" fail "$matching_output" ;;
  *) record "pr: no FETCH when the local HEAD is the PR head" ok ;;
esac

# --- a re-review: --since saves only what changed from the head reviewed last time ---------
since_output=$(cd "$repo" && bash "$gather" 12 --since "$base_sha" --out-dir "$work_dir/out-since")
expect_contains "since: meta.env names the commit it started from" "SINCE=$base_sha" "$since_output"
expect_eq "since: the changed files are the delta's, not the whole PR's" "a.txt
b.txt" "$(cat "$work_dir/out-since/changed-files.txt")"
expect_contains "since: the diff is the delta" "+two" "$(cat "$work_dir/out-since/review.diff")"
expect_eq "since: the whole PR's diff is not saved" "" "$(grep -F 'src/widgets' "$work_dir/out-since/review.diff" || true)"

side_sha=$(git -C "$repo" commit-tree -m side "$(git -C "$repo" rev-parse 'main^{tree}')")
rebased_output=$(cd "$repo" && bash "$gather" 12 --since "$side_sha" --out-dir "$work_dir/out-rebased")
expect_contains "since: a commit outside the head's history falls back to the whole diff" "the branch was rebased" "$rebased_output"
expect_contains "since: the fallback saves the whole PR" "src/widgets/list.ts" "$(cat "$work_dir/out-rebased/changed-files.txt")"
case "$rebased_output" in
  *SINCE=*) record "since: no SINCE line on a fallback" fail "$rebased_output" ;;
  *) record "since: no SINCE line on a fallback" ok ;;
esac

missing_output=$(cd "$repo" && bash "$gather" 12 --since 2222222222222222222222222222222222222222 --out-dir "$work_dir/out-missing")
expect_contains "since: a commit the clone lacks falls back" "is not in this clone" "$missing_output"

use_gh_fixtures "$fixtures"
unfetched_output=$(cd "$repo" && bash "$gather" 12 --since "$base_sha" --out-dir "$work_dir/out-unfetched")
expect_contains "since: an unfetched PR head falls back and says to fetch" "run the FETCH command" "$unfetched_output"
use_gh_fixtures "$matching_fixtures"

# --- usage errors -------------------------------------------------------------
check_status() {
  local label=$1 expected=$2 status
  shift 2
  set +e
  (cd "$repo" && bash "$gather" "$@") >/dev/null 2>&1
  status=$?
  set -e
  expect_eq "$label" "$expected" "$status"
}
check_status "usage: no arguments exits 2" 2
check_status "usage: a non-numeric PR exits 2" 2 abc
check_status "usage: a PR and --branch together exit 2" 2 12 --branch
check_status "usage: an unknown base exits 2" 2 --branch no-such-branch
check_status "usage: --out-dir without a value exits 2" 2 --branch --out-dir
check_status "usage: --since with --branch exits 2" 2 --branch --since abc
check_status "usage: --since without a value exits 2" 2 12 --since

finish
