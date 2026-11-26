#!/usr/bin/env bash
# Tests the merge handling of scripts/ready-receipt.sh and guard-merge.sh (kc-ready-for-review §H5): a head that merges the
# default branch into a commit with a clean receipt is clean with no new pass when the merge adds
# nothing the default branch did not have (a conflict in a plugin manifest's version and in
# CHANGELOG entries resolved by renumbering is allowed), and not clean when the resolution changes
# any other line of the branch side. A fix commit written with --after is still not clean. Real
# repos in a temp folder; kept apart from ready-receipt.test.sh so each runs inside a hook's time limit.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
require_jq
export KC_READY_DIR="$work_dir/receipts"
mkdir -p "$KC_READY_DIR" "$work_dir/gh"
use_gh_fixtures "$work_dir/gh"

repo="$work_dir/repo"
manifest=plugins/shop/.claude-plugin/plugin.json
check_clean() { (cd "$repo" && bash "$scripts/ready-receipt.sh" check "$1" --clean > /dev/null 2>&1) && echo clean || echo not-clean; }
write_clean_receipt() { printf 'sha=%s\nrounds=2\nopen=0\nclean=yes\n' "$1" > "$KC_READY_DIR/$1"; }
# Builds a repo whose lesson branch is at a clean head, and whose main has moved: both sides bumped
# the manifest version and added a CHANGELOG entry, and main also changed code.sh.
build_repo() {
  rm -rf "${repo:?}" "${KC_READY_DIR:?}"/*
  git init -q -b main "$repo"
  mkdir -p "$repo/plugins/shop/.claude-plugin"
  printf '{\n  "name": "shop",\n  "version": "1.0.0"\n}\n' > "$repo/$manifest"
  printf '# Changelog\n\n## [Unreleased]\n\n- shop 1.0.0: first\n' > "$repo/CHANGELOG.md"
  printf 'echo one\necho two\n' > "$repo/code.sh"
  run_git_in "$repo" add -A
  run_git_in "$repo" commit -q -m base
  run_git_in "$repo" checkout -q -b lesson
  sed -i.bak 's/1.0.0/1.0.1/' "$repo/$manifest" && rm "$repo/$manifest.bak"
  printf '# Changelog\n\n## [Unreleased]\n\n- shop 1.0.1: lesson\n- shop 1.0.0: first\n' > "$repo/CHANGELOG.md"
  printf 'echo lesson\n' >> "$repo/code.sh"
  run_git_in "$repo" add -A
  run_git_in "$repo" commit -q -m lesson
  clean_head=$(git -C "$repo" rev-parse HEAD)
  write_clean_receipt "$clean_head"
  run_git_in "$repo" checkout -q main
  sed -i.bak 's/1.0.0/1.0.1/' "$repo/$manifest" && rm "$repo/$manifest.bak"
  printf '# Changelog\n\n## [Unreleased]\n\n- shop 1.0.1: other\n- shop 1.0.0: first\n' > "$repo/CHANGELOG.md"
  printf 'echo main\necho one\necho two\n' > "$repo/code.sh"
  run_git_in "$repo" add -A
  run_git_in "$repo" commit -q -m "main moved"
  run_git_in "$repo" checkout -q lesson
}
# Merges main into the lesson branch; the manifest and CHANGELOG conflicts are resolved by renumbering
# the lesson's entry to 1.0.2. $1, when given, is an extra line appended to the file $2 by the resolution.
merge_main() {
  run_git_in "$repo" merge --no-commit --no-ff main > /dev/null 2>&1 || true
  printf '{\n  "name": "shop",\n  "version": "1.0.2"\n}\n' > "$repo/$manifest"
  printf '# Changelog\n\n## [Unreleased]\n\n- shop 1.0.2: lesson\n- shop 1.0.1: other\n- shop 1.0.0: first\n' > "$repo/CHANGELOG.md"
  printf 'echo main\necho one\necho two\necho lesson\n' > "$repo/code.sh"
  if [ -n "${1:-}" ]; then printf '%s\n' "$1" >> "$repo/$2"; fi
  run_git_in "$repo" add -A
  run_git_in "$repo" commit -q -m "merge main"
  git -C "$repo" rev-parse HEAD
}

build_repo
merge_head=$(merge_main)
expect_eq "a merge of main into a clean head, version and CHANGELOG conflicts renumbered, is clean" clean "$(check_clean "$merge_head")"
(cd "$repo" && bash "$scripts/ready-receipt.sh" write "$merge_head" --after "$clean_head") > "$work_dir/after.out" 2>&1 || true
expect_contains "--after notices the merge and says it counts as clean" "counts as clean" "$(cat "$work_dir/after.out")"

route="headRefOid,author,baseRefName,statusCheckRollup"
printf '{"login":"me"}\n' > "$work_dir/gh/user.json"
printf '{"headRefOid":"%s","author":{"login":"me"},"baseRefName":"main","statusCheckRollup":[{"conclusion":"SUCCESS"}]}\n' "$merge_head" > "$work_dir/gh/pr.json"
printf 'pr view 7 --json %s\tpr.json\napi user\tuser.json\n' "$route" > "$work_dir/gh/routes.tsv"
rm -f "$KC_READY_DIR/$merge_head"
expect_hook_verdict "$scripts/guard-merge.sh" allow "allowed: gh pr merge of the clean-head merge, no approval" "gh pr merge 7 --squash" "$repo"

build_repo
merge_head=$(merge_main "echo sneaked-in" code.sh)
expect_eq "a merge whose resolution adds a code line neither parent had is not clean" not-clean "$(check_clean "$merge_head")"

build_repo
merge_head=$(merge_main "- a rule neither parent had" CHANGELOG.md)
expect_eq "a merge whose resolution adds a CHANGELOG line neither parent had is not clean" not-clean "$(check_clean "$merge_head")"

build_repo
run_git_in "$repo" merge --no-commit --no-ff main > /dev/null 2>&1 || true
printf '{\n  "name": "shop",\n  "version": "1.0.2"\n}\n' > "$repo/$manifest"
printf '# Changelog\n\n## [Unreleased]\n\n- shop 1.0.2: lesson\n- shop 1.0.1: other\n- shop 1.0.0: first\n' > "$repo/CHANGELOG.md"
printf 'echo main\necho one\necho two\n' > "$repo/code.sh"
run_git_in "$repo" add -A
run_git_in "$repo" commit -q -m "merge main, dropping the branch's code line"
expect_eq "a merge whose resolution drops a line the branch added is not clean" not-clean "$(check_clean "$(git -C "$repo" rev-parse HEAD)")"

build_repo
printf 'echo fix\n' >> "$repo/code.sh"
run_git_in "$repo" commit -q -am "fix"
fix_head=$(git -C "$repo" rev-parse HEAD)
(cd "$repo" && bash "$scripts/ready-receipt.sh" write "$fix_head" --after "$clean_head") > /dev/null 2>&1
expect_eq "--after on a non-merge fix commit is still not clean" not-clean "$(check_clean "$fix_head")"

build_repo
rm -f "$KC_READY_DIR/$clean_head"
merge_head=$(merge_main)
expect_eq "a merge into a head with no clean receipt is not clean" not-clean "$(check_clean "$merge_head")"

finish
