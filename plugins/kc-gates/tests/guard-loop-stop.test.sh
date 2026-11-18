#!/usr/bin/env bash
# Tests scripts/guard-loop-stop.sh: a `git commit` or `gh pr create` whose changed lines were
# written by an already-handed-off commit (a kc-ready-for-review receipt, or a pull request merged
# in the last 7 days) is denied unless the command carries KC_LOOP_APPROVED=1. Real repos in a temp
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

git_in() { local repo=$1; shift; git -C "$repo" -c user.name=t -c user.email=t@example.test "$@"; }
write_lines() { local file=$1 prefix=$2 i; for i in 1 2 3 4 5 6; do echo "$prefix$i"; done > "$file"; }
# Replaces line $3 of file $2 in repo $1.
edit_line() { sed "$3s/.*/changed/" "$1/$2" > "$work_dir/edit.tmp" && mv "$work_dir/edit.tmp" "$1/$2"; }
# Leaves the repo clean at HEAD.
reset_repo() { git -C "$1" reset -q --hard HEAD; }

# A repo on main with a remote: commit A writes f.txt (receipted), commit B writes g.txt (no receipt).
make_repo() {
  git init -q -b main "$1"
  git init -q --bare "$1.git"
  git -C "$1" remote add origin "$1.git"
  write_lines "$1/f.txt" a
  git_in "$1" add f.txt
  git_in "$1" commit -q -m "fix f"
  write_lines "$1/g.txt" b
  git_in "$1" add g.txt
  git_in "$1" commit -q -m "add g"
  git -C "$1" push -q origin main
}
repo="$work_dir/repo"
make_repo "$repo"
sha_f=$(git -C "$repo" rev-parse HEAD~1)
printf 'rounds=1\n' > "$KC_READY_DIR/$sha_f"

build_payload() {
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"test"},"tool_use_id":"t"}' "$2" "$1"
}

# expect <deny|allow> <label> <command> <cwd>; sets $last_output to the jq-mode output.
check() {
  local expectation=$1 label=$2 command=$3 cwd=$4 mode output verdict
  for mode in jq sed; do
    if [ "$mode" = sed ]; then
      output=$(build_payload "$command" "$cwd" | KC_GUARD_NO_JQ=1 bash "$scripts/guard-loop-stop.sh" 2>/dev/null)
    else
      output=$(build_payload "$command" "$cwd" | bash "$scripts/guard-loop-stop.sh" 2>/dev/null)
      last_output=$output
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

# A commit.
edit_line "$repo" f.txt 2
git_in "$repo" add f.txt
check deny "blocked: a commit that edits lines a receipted commit wrote" "git commit -m 'again'" "$repo"
expect_contains "the message names the loop-stop rule" "the loop-stop rule says stop and question the approach; ask the user" "$last_output"
expect_contains "the message names the earlier fix by sha and subject" "${sha_f:0:9} fix f (f.txt:2)" "$last_output"
check allow "allowed: the same commit with KC_LOOP_APPROVED=1" "KC_LOOP_APPROVED=1 git commit -m 'again'" "$repo"
check deny "blocked: cd into the repo first" "cd $repo && git commit -m 'again'" "$work_dir"
check deny "blocked: git -C <repo> commit" "git -C $repo commit -m 'again'" "$work_dir"
check allow "allowed: a command that is not a commit" "git status" "$repo"
reset_repo "$repo"

edit_line "$repo" g.txt 2
git_in "$repo" add g.txt
check allow "allowed: a commit that edits lines of a commit with no receipt" "git commit -m 'tweak g'" "$repo"
reset_repo "$repo"

echo extra >> "$repo/f.txt"
git_in "$repo" add f.txt
check allow "allowed: a commit that only adds lines to a receipted file" "git commit -m 'extend f'" "$repo"
reset_repo "$repo"

echo new > "$repo/new.txt"
git_in "$repo" add new.txt
check allow "allowed: a commit that adds a new file" "git commit -m 'new file'" "$repo"
reset_repo "$repo"
rm -f "$repo/new.txt"

edit_line "$repo" f.txt 3
check allow "allowed: an unstaged edit of receipted lines, plain commit" "git commit -m 'nothing staged'" "$repo"
check deny "blocked: git commit -a reads the unstaged edit" "git commit -a -m 'all'" "$repo"
check deny "blocked: git commit -am reads the unstaged edit" "git commit -am all" "$repo"
reset_repo "$repo"

# A pull request: the branch's diff from its merge-base, blamed at the merge-base.
git -C "$repo" checkout -q -b feature
edit_line "$repo" f.txt 4
git_in "$repo" commit -q -am "feature edits f"
check deny "blocked: gh pr create for a branch that edits receipted lines" "gh pr create --fill" "$repo"
check deny "blocked: gh pr create --base main" "gh pr create --base main --fill" "$repo"
check allow "allowed: gh pr create with KC_LOOP_APPROVED=1" "KC_LOOP_APPROVED=1 gh pr create --fill" "$repo"
git -C "$repo" checkout -q -b feature-g main
edit_line "$repo" g.txt 4
git_in "$repo" commit -q -am "feature edits g"
check allow "allowed: gh pr create for a branch that edits other lines" "gh pr create --fill" "$repo"
check allow "allowed: gh pr view is not a PR create" "gh pr view 3" "$repo"
git -C "$repo" checkout -q main

# A commit that reached the default branch through a pull request merged in the last 7 days.
now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
old_iso=$(jq -rn 'now - 2592000 | todate')
make_merged_repo() {
  make_repo "$1"
  write_lines "$1/m.txt" m
  git_in "$1" add m.txt
  git_in "$1" commit -q -m "squash merged fix (#7)"
  git -C "$1" push -q origin main
  git_in "$1" checkout -q -b follow-up
  edit_line "$1" m.txt 2
  git_in "$1" add m.txt
}
merged_repo="$work_dir/merged-repo"
make_merged_repo "$merged_repo"
sha_m=$(git -C "$merged_repo" rev-parse HEAD)
write_route() { # <merged_at or none>
  printf 'api repos/{owner}/{repo}/commits/%s/pulls\tpulls.json\n' "$sha_m" > "$work_dir/gh/routes.tsv"
  if [ "$1" = none ]; then echo '[]' > "$work_dir/gh/pulls.json"; else printf '[{"number":7,"merged_at":"%s"}]\n' "$1" > "$work_dir/gh/pulls.json"; fi
}
write_route "$now_iso"
check deny "blocked: a commit that edits lines a PR merged this week wrote" "git commit -m 'fix the fix'" "$merged_repo"
expect_contains "the message names the merged commit" "${sha_m:0:9} squash merged fix (#7) (m.txt:2)" "$last_output"
check allow "allowed: the same commit with KC_LOOP_APPROVED=1" "KC_LOOP_APPROVED=1 git commit -m 'fix the fix'" "$merged_repo"
write_route "$old_iso"
check allow "allowed: the PR merged more than 7 days ago" "git commit -m 'fix the fix'" "$merged_repo"
write_route none
check allow "allowed: a commit on main that no PR merged" "git commit -m 'fix the fix'" "$merged_repo"
: > "$work_dir/gh/routes.tsv"
check allow "allowed: the PR lookup fails" "git commit -m 'fix the fix'" "$merged_repo"
write_route "$now_iso"
old_repo="$work_dir/old-repo"
make_repo "$old_repo"
write_lines "$old_repo/m.txt" m
git_in "$old_repo" add m.txt
GIT_COMMITTER_DATE="2020-01-01T00:00:00Z" git_in "$old_repo" commit -q -m "old merged fix (#1)"
git -C "$old_repo" push -q origin main
sha_m=$(git -C "$old_repo" rev-parse HEAD)
write_route "$now_iso"
edit_line "$old_repo" m.txt 2
git_in "$old_repo" add m.txt
check allow "allowed: the blamed commit is more than 7 days old" "git commit -m 'fix the fix'" "$old_repo"

finish
