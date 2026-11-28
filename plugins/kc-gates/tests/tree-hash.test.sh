#!/usr/bin/env bash
# Tests scripts/tree-hash.sh: the hash is of the content, so it matches the commit once the work is
# committed, moves when a tracked file, an untracked file or a deletion changes it, ignores ignored
# files, survives an amend that leaves the tree alone, and never touches the repo's own index.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
hash_tool="$(dirname "$tests_dir")/scripts/tree-hash.sh"

repo="$work_dir/repo"
git init -q -b main "$repo"
printf '*.log\n' > "$repo/.gitignore"
printf 'one\n' > "$repo/a.txt"
printf 'keep\n' > "$repo/b.txt"
run_git_in "$repo" add -A
run_git_in "$repo" commit -q -m base
tree_of() { (cd "$repo" && bash "$hash_tool" "$@"); }

clean=$(tree_of)
expect_eq "a clean working tree hashes to HEAD's tree" "$(git -C "$repo" rev-parse 'HEAD^{tree}')" "$clean"
expect_eq "a revision argument prints that commit's tree" "$clean" "$(tree_of HEAD)"

printf 'two\n' >> "$repo/a.txt"
edited=$(tree_of)
expect_eq "an edit to a tracked file moves the hash" different "$([ "$edited" != "$clean" ] && echo different || echo same)"
expect_eq "the hash is stable while nothing changes" "$edited" "$(tree_of)"

printf 'new\n' > "$repo/c.txt"
untracked=$(tree_of)
expect_eq "an untracked file moves the hash" different "$([ "$untracked" != "$edited" ] && echo different || echo same)"

printf 'noise\n' > "$repo/debug.log"
expect_eq "an ignored file does not move the hash" "$untracked" "$(tree_of)"

rm "$repo/b.txt"
deleted=$(tree_of)
expect_eq "a deleted file moves the hash" different "$([ "$deleted" != "$untracked" ] && echo different || echo same)"

expect_eq "it leaves the repo's index alone: nothing is staged" "" "$(git -C "$repo" diff --cached --name-only)"
expect_contains "and the edits are still unstaged" "a.txt" "$(git -C "$repo" diff --name-only)"

# The content committed has the hash it had before the commit, and an amend of the message keeps it.
run_git_in "$repo" add -A
run_git_in "$repo" commit -q -m work
expect_eq "the hash before the commit is the commit's tree" "$deleted" "$(tree_of HEAD)"
before_amend=$(git -C "$repo" rev-parse HEAD)
run_git_in "$repo" commit -q --amend -m "work, reworded"
expect_eq "an amend that leaves the content alone gives a new commit" different "$([ "$(git -C "$repo" rev-parse HEAD)" != "$before_amend" ] && echo different || echo same)"
expect_eq "and the same tree hash" "$deleted" "$(tree_of HEAD)"
expect_eq "and the same working-tree hash" "$deleted" "$(tree_of)"

unknown_status=ok; (cd "$repo" && bash "$hash_tool" nosuchrev > /dev/null 2>&1) && unknown_status=fail
record "an unknown revision is refused" "$unknown_status"
outside_status=ok; (cd "$work_dir" && bash "$hash_tool" > /dev/null 2>&1) && outside_status=fail
record "outside a git work tree it is refused" "$outside_status"

finish
