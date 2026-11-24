#!/usr/bin/env bash
# Tests scripts/change-class.sh on real repositories in a temp folder: a few prose lines alone are
# prose_small (version bumps and listed regenerated files beside them allowed), a small change with a
# script or code is code_small, and a risk path, a deletion, an empty change or no repository is full.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
change_class="$(dirname "$tests_dir")/scripts/change-class.sh"

repo="$work_dir/repo"
run_git() { git -C "$repo" -c user.name=t -c user.email=t@example.test "$@"; }
git init -q -b main "$repo"
git init -q --bare "$repo.git"
git -C "$repo" remote add origin "$repo.git"
mkdir -p "$repo/docs" "$repo/tests"
printf 'Orders ship in one box.\nRefunds go to the card.\n' > "$repo/docs/rules.md"
printf '{\n  "name": "shop",\n  "version": "1.0.0"\n}\n' > "$repo/package.json"
printf 'Fixture for the order test.\n' > "$repo/tests/case.md"
printf 'echo order\n' > "$repo/order.sh"
run_git add -A
run_git commit -q -m base
git -C "$repo" push -q origin main

# class_of <branch> <file>...: commits one added line to each file on a new branch from main (a path
# ending in - deletes the file), prints the class of the branch.
class_of() {
  local branch=$1 changed_file
  shift
  run_git checkout -q -b "$branch" main
  for changed_file in "$@"; do
    case "$changed_file" in
      *-) run_git rm -q "${changed_file%-}" ;;
      *) mkdir -p "$(dirname "$repo/$changed_file")"; printf 'Refunds go back to the card used.\n' >> "$repo/$changed_file"; run_git add "$changed_file" ;;
    esac
  done
  run_git commit -q -m "$branch"
  bash "$change_class" --dir "$repo" | sed -n 's/^CLASS=//p'
}
bump_version() { sed 's/1\.0\.0/1.0.1/' "$repo/package.json" > "$work_dir/p.tmp" && mv "$work_dir/p.tmp" "$repo/package.json"; }

expect_eq "a few prose lines: prose_small" prose_small "$(class_of wording docs/rules.md)"
run_git checkout -q -b bump main
bump_version
printf 'One more rule.\n' >> "$repo/docs/rules.md"
run_git commit -q -am bump
expect_eq "prose plus a version bump: prose_small" prose_small "$(bash "$change_class" --dir "$repo" | sed -n 's/^CLASS=//p')"
expect_eq "prose plus one script: code_small" code_small "$(class_of with-script docs/rules.md order.sh)"
expect_eq "prose in a test folder is a check, not prose: code_small" code_small "$(class_of test-fixture tests/case.md)"
expect_eq "a regenerated file the repo does not list: code_small" code_small "$(class_of built docs/rules.md site/rules.json)"
mkdir -p "$repo/.claude"
printf '# regenerated from docs/\n^site/\n' > "$repo/.claude/generated-paths.txt"
expect_eq "a regenerated file the repo lists in .claude/generated-paths.txt: prose_small" prose_small "$(bash "$change_class" --dir "$repo" | sed -n 's/^CLASS=//p')"
rm "$repo/.claude/generated-paths.txt"
expect_eq "a small change on a risk path: full" full "$(class_of risky docs/auth-rules.md order.sh)"
expect_eq "a deleted prose file: full" full "$(class_of delete docs/rules.md-)"

run_git checkout -q -b long main
for line in $(seq 1 31); do printf 'Rule %s.\n' "$line" >> "$repo/docs/rules.md"; done
run_git commit -q -am long
expect_eq "31 prose lines: code_small" code_small "$(bash "$change_class" --dir "$repo" | sed -n 's/^CLASS=//p')"
expect_eq "KC_PROSE_SMALL_LINES raises the limit" prose_small "$(KC_PROSE_SMALL_LINES=40 bash "$change_class" --dir "$repo" | sed -n 's/^CLASS=//p')"

run_git checkout -q main
expect_eq "an empty change: full" full "$(bash "$change_class" --dir "$repo" | sed -n 's/^CLASS=//p')"
printf 'Staged rule.\n' >> "$repo/docs/rules.md"
run_git add docs/rules.md
expect_eq "--staged reads the index: prose_small" prose_small "$(bash "$change_class" --dir "$repo" --staged | sed -n 's/^CLASS=//p')"
printf 'echo unstaged\n' >> "$repo/order.sh"
expect_eq "--staged leaves an unstaged script out" prose_small "$(bash "$change_class" --dir "$repo" --staged | sed -n 's/^CLASS=//p')"
expect_eq "--all reads the unstaged script: code_small" code_small "$(bash "$change_class" --dir "$repo" --all | sed -n 's/^CLASS=//p')"
report=$(bash "$change_class" --dir "$repo" --all)
expect_contains "the report carries pass-size.sh's lines" "SIZE=small" "$report"
expect_contains "the report says why" "reason: pass-size.sh says small with no risk line (other: order.sh)" "$report"

mkdir -p "$work_dir/not-a-repo"
expect_eq "no repository: full" full "$(bash "$change_class" --dir "$work_dir/not-a-repo" | sed -n 's/^CLASS=//p')"
status=0
bash "$change_class" --bogus >/dev/null 2>&1 || status=$?
expect_eq "an unknown option is a usage error" 2 "$status"

finish
