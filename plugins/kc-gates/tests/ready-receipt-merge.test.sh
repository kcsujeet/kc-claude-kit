#!/usr/bin/env bash
# Tests the merge handling of scripts/ready-receipt.sh and guard-merge.sh (kc-ready-for-review §H5):
# a head that merges the default branch into a commit with a clean receipt is clean with no new pass
# when the merge is what git makes of the two parents on its own (a conflict in a plugin manifest's
# version and in CHANGELOG entries resolved by renumbering is allowed), and not clean when the
# resolution changes any other line, keeps a stale copy of a file the default branch changed, reorders
# the branch's lines, or merges a commit the default branch does not have. A fix commit written with
# --after is still not clean. Real repos in a temp folder; kept apart from ready-receipt.test.sh so
# each runs inside a hook's time limit.
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
# the manifest version (to different numbers, so it conflicts) and added a CHANGELOG entry, and main also changed code.sh and other.sh.
build_repo() {
  rm -rf "${repo:?}" "${KC_READY_DIR:?}"/*
  git init -q -b main "$repo"
  mkdir -p "$repo/plugins/shop/.claude-plugin"
  printf '{\n  "name": "shop",\n  "version": "1.0.0"\n}\n' > "$repo/$manifest"
  printf '# Changelog\n\n## [Unreleased]\n\n- shop 1.0.0: first\n' > "$repo/CHANGELOG.md"
  printf 'echo one\necho two\n' > "$repo/code.sh"
  printf 'echo other\n' > "$repo/other.sh"
  run_git_in "$repo" add -A
  run_git_in "$repo" commit -q -m base
  base_head=$(git -C "$repo" rev-parse HEAD)
  run_git_in "$repo" checkout -q -b lesson
  sed -i.bak 's/1.0.0/1.0.1/' "$repo/$manifest" && rm "$repo/$manifest.bak"
  printf '# Changelog\n\n## [Unreleased]\n\n- shop 1.0.1: lesson\n- shop 1.0.0: first\n' > "$repo/CHANGELOG.md"
  printf 'echo lesson\n' >> "$repo/code.sh"
  run_git_in "$repo" add -A
  run_git_in "$repo" commit -q -m lesson
  clean_head=$(git -C "$repo" rev-parse HEAD)
  write_clean_receipt "$clean_head"
  run_git_in "$repo" checkout -q main
  sed -i.bak 's/1.0.0/1.0.3/' "$repo/$manifest" && rm "$repo/$manifest.bak"
  printf '# Changelog\n\n## [Unreleased]\n\n- shop 1.0.1: other\n- shop 1.0.0: first\n' > "$repo/CHANGELOG.md"
  printf 'echo main\necho one\necho two\n' > "$repo/code.sh"
  printf 'echo other-main\n' > "$repo/other.sh"
  run_git_in "$repo" add -A
  run_git_in "$repo" commit -q -m "main moved"
  run_git_in "$repo" checkout -q lesson
  resolved_code='echo main\necho one\necho two\necho lesson\n'
  resolved_manifest='{\n  "name": "shop",\n  "version": "1.0.2"\n}\n'
}
# Concludes the merge in progress (its manifest and CHANGELOG conflicts, resolved by renumbering the
# lesson's entry to 1.0.2) with the files the resolved_* variables hold, and prints the merge commit.
# $1 is a command run before the commit, for a resolution that goes further.
conclude_merge() {
  printf '%b' "$resolved_manifest" > "$repo/$manifest"
  printf '# Changelog\n\n## [Unreleased]\n\n- shop 1.0.2: lesson\n- shop 1.0.1: other\n- shop 1.0.0: first\n' > "$repo/CHANGELOG.md"
  printf '%b' "$resolved_code" > "$repo/code.sh"
  if [ -n "${1:-}" ]; then eval "$1"; fi
  run_git_in "$repo" add -A
  run_git_in "$repo" commit -q -m "merge"
  git -C "$repo" rev-parse HEAD
}
merge_main() {
  run_git_in "$repo" merge --no-commit --no-ff main > /dev/null 2>&1 || true
  conclude_merge "${1:-}"
}

build_repo
merge_head=$(merge_main)
expect_eq "§H5: a merge of main into a clean head, version and CHANGELOG conflicts renumbered, is clean" clean "$(check_clean "$merge_head")"
(cd "$repo" && bash "$scripts/ready-receipt.sh" write "$merge_head" --after "$clean_head") > "$work_dir/after.out" 2>&1 || true
expect_contains "--after notices the merge and says it counts as clean" "counts as clean" "$(cat "$work_dir/after.out")"

# guard-merge.sh: the clean-head merge is allowed with no receipt of its own, a merge with a stray line is not.
route="headRefOid,author,baseRefName,statusCheckRollup"
printf '{"login":"me"}\n' > "$work_dir/gh/user.json"
route_pull_request_head() {
  printf '{"headRefOid":"%s","author":{"login":"me"},"baseRefName":"main","statusCheckRollup":[{"conclusion":"SUCCESS"}]}\n' "$1" > "$work_dir/gh/pr.json"
  printf 'pr view 7 --json %s\tpr.json\napi user\tuser.json\n' "$route" > "$work_dir/gh/routes.tsv"
}
route_pull_request_head "$merge_head"
rm -f "$KC_READY_DIR/$merge_head"
expect_hook_verdict "$scripts/guard-merge.sh" allow "allowed: gh pr merge of the clean-head merge, no approval" "gh pr merge 7 --squash" "$repo"

build_repo
resolved_code='echo main\necho one\necho two\necho lesson\necho sneaked-in\n'
merge_head=$(merge_main)
expect_eq "a merge whose resolution adds a code line neither parent had is not clean" not-clean "$(check_clean "$merge_head")"
route_pull_request_head "$merge_head"
expect_hook_verdict "$scripts/guard-merge.sh" deny "blocked: gh pr merge of a merge that adds a code line of its own" "gh pr merge 7 --squash" "$repo"

build_repo
merge_head=$(merge_main "printf -- '- a line neither parent had\\n' >> \"$repo/CHANGELOG.md\"")
expect_eq "a merge whose resolution adds a CHANGELOG line neither parent had is not clean" not-clean "$(check_clean "$merge_head")"

build_repo
resolved_manifest='{\n  "name": "shop",\n  "version": "1.0.2",\n  "extra": 1\n}\n'
merge_head=$(merge_main)
expect_eq "a merge whose resolution adds a manifest line that is not the version is not clean" not-clean "$(check_clean "$merge_head")"

build_repo
resolved_manifest='{\n  "version": "1.0.2"\n}\n'
merge_head=$(merge_main)
expect_eq "a merge whose resolution drops a non-version manifest line is not clean" not-clean "$(check_clean "$merge_head")"

build_repo
resolved_manifest='{\n  "name": "shop",\n  "name": "shop",\n  "version": "1.0.2"\n}\n'
merge_head=$(merge_main)
expect_eq "a merge whose resolution duplicates a manifest line is not clean" not-clean "$(check_clean "$merge_head")"

build_repo
merge_head=$(merge_main "grep -v 'first' \"$repo/CHANGELOG.md\" > \"$work_dir/changelog\" && cp \"$work_dir/changelog\" \"$repo/CHANGELOG.md\"")
expect_eq "a merge whose resolution drops a CHANGELOG entry is not clean" not-clean "$(check_clean "$merge_head")"

build_repo
printf 'echo other-lesson\n' > "$repo/other.sh"
run_git_in "$repo" commit -q -am "lesson edits other.sh too"
write_clean_receipt "$(git -C "$repo" rev-parse HEAD)"
run_git_in "$repo" merge --no-commit --no-ff main > /dev/null 2>&1 || true
printf 'echo other-lesson\n' > "$repo/other.sh"
merge_head=$(conclude_merge)
expect_eq "a merge that resolves a conflict in a code file is not clean" not-clean "$(check_clean "$merge_head")"
run_git_in "$repo" reset -q --hard HEAD^1
run_git_in "$repo" merge --no-commit --no-ff main > /dev/null 2>&1 || true
conflicted_tree=$(git -C "$repo" merge-tree --write-tree --no-messages "$(git -C "$repo" rev-parse HEAD)" "$(git -C "$repo" rev-parse main)" | head -n 1) || true
merge_head=$(conclude_merge "git -C \"$repo\" checkout $conflicted_tree -- other.sh")
expect_eq "a merge that commits git's own conflict markers in a code file is not clean" not-clean "$(check_clean "$merge_head")"

build_repo
resolved_code='echo main\necho one\necho two\n'
merge_head=$(merge_main)
expect_eq "a merge whose resolution drops a line the branch added is not clean" not-clean "$(check_clean "$merge_head")"

build_repo
resolved_code='echo lesson\necho two\necho one\necho main\n'
merge_head=$(merge_main)
expect_eq "a merge whose resolution reorders the branch's lines is not clean" not-clean "$(check_clean "$merge_head")"

build_repo
merge_head=$(merge_main "git -C \"$repo\" show \"$clean_head:other.sh\" > \"$repo/other.sh\"")
expect_eq "a merge that keeps the branch's stale copy of a file main changed is not clean" not-clean "$(check_clean "$merge_head")"

build_repo
run_git_in "$repo" checkout -q -b side "$base_head"
printf 'echo side\n' > "$repo/side.sh"
run_git_in "$repo" add -A
run_git_in "$repo" commit -q -m "side"
run_git_in "$repo" checkout -q lesson
run_git_in "$repo" merge -q --no-ff -m "merge side" side
expect_eq "a merge of a branch the default branch does not have is not clean" not-clean "$(check_clean "$(git -C "$repo" rev-parse HEAD)")"

# The parents the other way round: the default branch is the first parent.
build_repo
run_git_in "$repo" checkout -q -b reversed main
run_git_in "$repo" merge --no-commit --no-ff lesson > /dev/null 2>&1 || true
merge_head=$(conclude_merge)
expect_eq "a merge of the clean head into the default branch (parents reversed) is clean" clean "$(check_clean "$merge_head")"

# A second merge of main on top of a clean merge is clean through the first; a long chain is cut off.
build_repo
merge_head=$(merge_main)
chain_clean=
for chain_link in 1 2 3 4 5 6 7 8; do
  run_git_in "$repo" checkout -q main
  printf 'echo main-%s\n' "$chain_link" >> "$repo/other.sh"
  run_git_in "$repo" commit -q -am "main $chain_link"
  run_git_in "$repo" checkout -q lesson
  run_git_in "$repo" merge -q --no-ff -m "merge $chain_link" main
  chain_clean="$chain_clean $(check_clean "$(git -C "$repo" rev-parse HEAD)")"
done
expect_eq "chained merges of main are clean through the cap and not past it" " clean clean clean clean not-clean not-clean not-clean not-clean" "$chain_clean"

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
