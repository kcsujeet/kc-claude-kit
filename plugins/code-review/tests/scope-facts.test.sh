#!/usr/bin/env bash
# Tests scripts/scope-facts.sh against the stub gh in lib/, answering from
# fixtures/scope-facts/: a PR stacked on another open PR with two linked
# issues and a multi-line description, and a PR with no other open PRs, no
# linked issue and an empty description.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scope_facts="$(dirname "$tests_dir")/scripts/scope-facts.sh"
fixtures="$tests_dir/fixtures/scope-facts"
require_jq
use_gh_fixtures "$fixtures"

out="$work_dir/out"
bash "$scope_facts" 12 --out-dir "$out" > "$work_dir/actual-12.txt"
sed "s|{out}|$out|g" "$fixtures/expected-12.txt" > "$work_dir/expected-12.txt"
expect_file "stacked PR: author, base, counts, other open PRs, linked issues" \
  "$work_dir/expected-12.txt" "$work_dir/actual-12.txt"
expect_eq "stacked PR: issue body written verbatim" "The list has no header.

Constraint: no public API change." "$(cat "$out/issue-7.md")"
expect_eq "stacked PR: second issue body written" "Must work offline." "$(cat "$out/issue-9.md")"
expect_eq "stacked PR: description written verbatim" "Adds the widget list header.

Closes #7, closes #9." "$(cat "$out/pr-body.md")"
if grep -Eqv '^(pr view|pr list|issue view) ' "$KC_GH_LOG"; then
  record "stacked PR: only read calls reached gh" fail "$(cat "$KC_GH_LOG")"
else
  record "stacked PR: only read calls reached gh" ok
fi

mkdir -p "$work_dir/tmp"
TMPDIR="$work_dir/tmp" bash "$scope_facts" 12 > /dev/null
expect_eq "default out dir: \$TMPDIR/kc-review-<head sha>" "Must work offline." \
  "$(cat "$work_dir/tmp/kc-review-2222222222222222222222222222222222222222/issue-9.md")"

bash "$scope_facts" 13 --out-dir "$work_dir/out-13" > "$work_dir/actual-13.txt"
sed "s|{out13}|$work_dir/out-13|g" "$fixtures/expected-13.txt" > "$work_dir/expected-13.txt"
expect_file "lonely PR: (none) in both lists" "$work_dir/expected-13.txt" "$work_dir/actual-13.txt"
expect_eq "lonely PR: an empty description is an empty file" "" "$(cat "$work_dir/out-13/pr-body.md")"
if find "$work_dir/out-13" -name 'issue-*' | grep -q .; then
  record "lonely PR: no issue files" fail "$(ls "$work_dir/out-13")"
else
  record "lonely PR: no issue files" ok
fi

set +e
bash "$scope_facts" > /dev/null 2>&1
no_args_status=$?
bash "$scope_facts" twelve > /dev/null 2>&1
bad_pr_status=$?
bash "$scope_facts" 99 > /dev/null 2>&1
gh_failure_status=$?
set -e
expect_eq "usage: no arguments exits 2" 2 "$no_args_status"
expect_eq "usage: a non-numeric PR exits 2" 2 "$bad_pr_status"
expect_eq "gh failure: exits 1" 1 "$gh_failure_status"

finish
