#!/usr/bin/env bash
# Tests scripts/guard-loop-stop.sh: a `git commit` or `gh pr create` whose changed lines were
# written by an already-handed-off commit (a kc-ready-for-review receipt, or a pull request merged
# in the last 7 days) is denied unless the command carries KC_REWORK_APPROVED=1 and the user typed "approve rework". Real repos in a temp
# folder, receipts written by hand into KC_READY_DIR, the stub gh in lib/ answering the merged-PR
# lookups. Each case runs twice, once with jq and once through the sed fallback.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
require_jq
export KC_READY_DIR="$work_dir/receipts"
mkdir -p "$KC_READY_DIR" "$work_dir/gh"
use_gh_fixtures "$work_dir/gh"
: > "$work_dir/gh/routes.tsv"

run_git_in() { local repo=$1; shift; git -C "$repo" -c user.name=t -c user.email=t@example.test "$@"; }
write_lines() { local file=$1 prefix=$2 i; for i in 1 2 3 4 5 6; do echo "$prefix$i"; done > "$file"; }
# Replaces line $3 of file $2 in repo $1.
edit_line() { sed "$3s/.*/changed/" "$1/$2" > "$work_dir/edit.tmp" && mv "$work_dir/edit.tmp" "$1/$2"; }
# Leaves the repo clean at HEAD.
reset_repo() { git -C "$1" reset -q --hard HEAD; }

# A repo on main with a remote: commit A writes f.txt and q.sql (receipted), commit B writes g.txt and a first line of q.sql (no receipt).
make_repo() {
  git init -q -b main "$1"
  git init -q --bare "$1.git"
  git -C "$1" remote add origin "$1.git"
  write_lines "$1/f.txt" a
  printf -- 'select 1;\nselect 2;\nselect 3;\nselect 4;\nselect 5;\n' > "$1/q.sql"
  run_git_in "$1" add f.txt q.sql
  run_git_in "$1" commit -q -m "fix f"
  write_lines "$1/g.txt" b
  printf -- '-- c1\n' | cat - "$1/q.sql" > "$1/q.sql.new" && mv "$1/q.sql.new" "$1/q.sql"
  run_git_in "$1" add g.txt q.sql
  run_git_in "$1" commit -q -m "add g"
  git -C "$1" push -q origin main
}
repo="$work_dir/repo"
make_repo "$repo"
fixed_commit_sha=$(git -C "$repo" rev-parse HEAD~1)
printf 'rounds=1\n' > "$KC_READY_DIR/$fixed_commit_sha"

check_verdict() { expect_hook_verdict "$scripts/guard-loop-stop.sh" "$@"; }

# A commit.
# A removed line that starts with `-- ` (SQL, Lua) is a removed line, not a file header: the hunks after
# it are still blamed.
sed -e '1d' -e '6s/.*/changed/' "$repo/q.sql" > "$work_dir/q.sql" && mv "$work_dir/q.sql" "$repo/q.sql"
run_git_in "$repo" add q.sql
check_verdict deny "blocked: a removed '-- ' line does not hide a later changed line of the same file" "git commit -m 'sql'" "$repo"
reset_repo "$repo"

edit_line "$repo" f.txt 2
run_git_in "$repo" add f.txt
check_verdict deny "blocked: a commit that edits lines a receipted commit wrote" "git commit -m 'again'" "$repo"
expect_contains "the message names the loop-stop rule" "the loop-stop rule says stop and question the approach; ask the user" "$last_hook_output"
expect_contains "the message names the earlier fix by sha and subject" "${fixed_commit_sha:0:9} fix f (f.txt:2)" "$last_hook_output"
expect_token_needs_typed_words "$scripts/guard-loop-stop.sh" KC_REWORK_APPROVED=1 "approve rework" "git commit -m 'again'" "$repo"
check_verdict deny "blocked: cd into the repo first" "cd $repo && git commit -m 'again'" "$work_dir"
check_verdict deny "blocked: git -C <repo> commit" "git -C $repo commit -m 'again'" "$work_dir"
check_verdict allow "allowed: a command that is not a commit" "git status" "$repo"
reset_repo "$repo"

edit_line "$repo" g.txt 2
run_git_in "$repo" add g.txt
check_verdict allow "allowed: a commit that edits lines of a commit with no receipt" "git commit -m 'tweak g'" "$repo"
reset_repo "$repo"

echo extra >> "$repo/f.txt"
run_git_in "$repo" add f.txt
check_verdict allow "allowed: a commit that only adds lines to a receipted file" "git commit -m 'extend f'" "$repo"
reset_repo "$repo"

echo new > "$repo/new.txt"
run_git_in "$repo" add new.txt
check_verdict allow "allowed: a commit that adds a new file" "git commit -m 'new file'" "$repo"
reset_repo "$repo"
rm -f "$repo/new.txt"

edit_line "$repo" f.txt 3
check_verdict allow "allowed: an unstaged edit of receipted lines, plain commit" "git commit -m 'nothing staged'" "$repo"
check_verdict deny "blocked: git commit -a reads the unstaged edit" "git commit -a -m 'all'" "$repo"
check_verdict deny "blocked: git commit -am reads the unstaged edit" "git commit -am all" "$repo"
reset_repo "$repo"

# A pull request: the branch's diff from its merge-base, blamed at the merge-base.
git -C "$repo" checkout -q -b feature
edit_line "$repo" f.txt 4
run_git_in "$repo" commit -q -am "feature edits f"
check_verdict deny "blocked: gh pr create for a branch that edits receipted lines" "gh pr create --fill" "$repo"
check_verdict deny "blocked: gh pr create --base main" "gh pr create --base main --fill" "$repo"
expect_token_needs_typed_words "$scripts/guard-loop-stop.sh" KC_REWORK_APPROVED=1 "approve rework" "gh pr create --fill" "$repo"
git -C "$repo" checkout -q -b feature-g main
edit_line "$repo" g.txt 4
run_git_in "$repo" commit -q -am "feature edits g"
check_verdict allow "allowed: gh pr create for a branch that edits other lines" "gh pr create --fill" "$repo"
check_verdict allow "allowed: gh pr view is not a PR create" "gh pr view 3" "$repo"
git -C "$repo" checkout -q main

# A commit that reached the default branch through a pull request merged in the last 7 days.
now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
thirty_days_seconds=$((30 * 24 * 60 * 60))
old_iso=$(jq -rn --argjson age "$thirty_days_seconds" 'now - $age | todate')
make_merged_repo() {
  make_repo "$1"
  write_lines "$1/m.txt" m
  run_git_in "$1" add m.txt
  run_git_in "$1" commit -q -m "squash merged fix (#7)"
  git -C "$1" push -q origin main
  run_git_in "$1" checkout -q -b follow-up
  edit_line "$1" m.txt 2
  run_git_in "$1" add m.txt
}
merged_repo="$work_dir/merged-repo"
make_merged_repo "$merged_repo"
merged_commit_sha=$(git -C "$merged_repo" rev-parse HEAD)
write_route() { # <merged_at or none>
  printf 'api repos/{owner}/{repo}/commits/%s/pulls\tpulls.json\n' "$merged_commit_sha" > "$work_dir/gh/routes.tsv"
  if [ "$1" = none ]; then echo '[]' > "$work_dir/gh/pulls.json"; else printf '[{"number":7,"merged_at":"%s"}]\n' "$1" > "$work_dir/gh/pulls.json"; fi
}
write_route "$now_iso"
check_verdict deny "blocked: a commit that edits lines a PR merged this week wrote" "git commit -m 'fix the fix'" "$merged_repo"
expect_contains "the message names the merged commit" "${merged_commit_sha:0:9} squash merged fix (#7) (m.txt:2)" "$last_hook_output"
write_route "$old_iso"
check_verdict allow "allowed: the PR merged more than 7 days ago" "git commit -m 'fix the fix'" "$merged_repo"
write_route none
check_verdict allow "allowed: a commit on main that no PR merged" "git commit -m 'fix the fix'" "$merged_repo"
: > "$work_dir/gh/routes.tsv"
check_verdict allow "allowed: the PR lookup fails" "git commit -m 'fix the fix'" "$merged_repo"
write_route "$now_iso"
old_repo="$work_dir/old-repo"
make_repo "$old_repo"
write_lines "$old_repo/m.txt" m
run_git_in "$old_repo" add m.txt
GIT_COMMITTER_DATE="2020-01-01T00:00:00Z" run_git_in "$old_repo" commit -q -m "old merged fix (#1)"
git -C "$old_repo" push -q origin main
merged_commit_sha=$(git -C "$old_repo" rev-parse HEAD)
write_route "$now_iso"
edit_line "$old_repo" m.txt 2
run_git_in "$old_repo" add m.txt
check_verdict allow "allowed: the blamed commit is more than 7 days old" "git commit -m 'fix the fix'" "$old_repo"

# A version bump: every release raises the version line a handed-off commit wrote.
version_repo="$work_dir/version-repo"
make_repo "$version_repo"
printf '{\n  "name": "shop",\n  "version": "1.0.0"\n}\n' > "$version_repo/p.json"
printf 'name = "shop"\nversion = "1.0.0"\n' > "$version_repo/p.toml"
run_git_in "$version_repo" add p.json p.toml
run_git_in "$version_repo" commit -q -m "release p"
git -C "$version_repo" push -q origin main
printf 'rounds=1\n' > "$KC_READY_DIR/$(git -C "$version_repo" rev-parse HEAD)"
bump_version() { sed 's/1\.0\.0/1.0.1/' "$version_repo/$1" > "$work_dir/bump.tmp" && mv "$work_dir/bump.tmp" "$version_repo/$1"; }
bump_version p.json
bump_version p.toml
run_git_in "$version_repo" add p.json p.toml
check_verdict allow "allowed: a commit that only raises versions a receipted commit wrote" "git commit -m 'bump'" "$version_repo"
reset_repo "$version_repo"
edit_line "$version_repo" p.json 2
bump_version p.json
run_git_in "$version_repo" add p.json
check_verdict deny "blocked: a version bump beside another changed line of the same hunk" "git commit -m 'rename'" "$version_repo"
reset_repo "$version_repo"
git -C "$version_repo" checkout -q -b bump main
bump_version p.json
run_git_in "$version_repo" commit -q -am "bump p"
check_verdict allow "allowed: gh pr create for a branch that only raises a version" "gh pr create --fill" "$version_repo"
edit_line "$version_repo" p.toml 1
run_git_in "$version_repo" commit -q -am "bump p and rename"
check_verdict deny "blocked: gh pr create for a branch that also edits receipted lines" "gh pr create --fill" "$version_repo"

# Merging the default branch in: its staged diff is the default branch's own work.
merge_repo="$work_dir/merge-repo"
make_repo "$merge_repo"
printf 'rounds=1\n' > "$KC_READY_DIR/$(git -C "$merge_repo" rev-parse HEAD~1)"
run_git_in "$merge_repo" checkout -q -b feature
echo feature > "$merge_repo/feature.txt"
run_git_in "$merge_repo" add feature.txt
run_git_in "$merge_repo" commit -q -m "feature work"
run_git_in "$merge_repo" checkout -q main
edit_line "$merge_repo" f.txt 2
run_git_in "$merge_repo" commit -q -am "main edits the receipted fix"
git -C "$merge_repo" push -q origin main
run_git_in "$merge_repo" checkout -q -b other feature
edit_line "$merge_repo" f.txt 3
run_git_in "$merge_repo" commit -q -am "other edits the receipted fix"
run_git_in "$merge_repo" checkout -q feature
run_git_in "$merge_repo" merge -q --no-commit --no-ff origin/main >/dev/null
check_verdict allow "allowed: concluding a merge of the default branch" "git commit --no-edit" "$merge_repo"
run_git_in "$merge_repo" merge --abort
run_git_in "$merge_repo" merge -q --no-commit --no-ff other >/dev/null
check_verdict deny "blocked: concluding a merge of a branch that is not the default one" "git commit --no-edit" "$merge_repo"
run_git_in "$merge_repo" merge --abort
run_git_in "$merge_repo" merge -q --no-commit --no-ff origin/main >/dev/null
edit_line "$merge_repo" f.txt 4
check_verdict allow "allowed: a default-branch merge with an unstaged edit left out" "git commit --no-edit" "$merge_repo"
check_verdict deny "blocked: git commit -a during a default-branch merge adds the edit" "git commit -a --no-edit" "$merge_repo"
check_verdict allow "allowed: -uall is the untracked-files option, not -a" "git commit -uall --no-edit" "$merge_repo"
run_git_in "$merge_repo" checkout -- f.txt
run_git_in "$merge_repo" merge --abort

finish
