#!/usr/bin/env bash
# Tests the merge handling of scripts/guard-prose-rule.sh: while a merge is concluded, rule lines the
# merge only carries in from the default branch are not counted, and lines the branch itself adds
# still block. Real repos in a temp folder. Each case runs twice, once with jq and once through the
# sed fallback. Kept apart from guard-prose-rule.test.sh so it runs inside a hook's time limit.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
require_jq

run_git_in() { local repo=$1; shift; git -C "$repo" -c user.name=t -c user.email=t@example.test "$@"; }
check_verdict() { expect_hook_verdict "$scripts/guard-prose-rule.sh" "$1" "$2" "$3" "${4:-$repo}"; }

merge_repo="$work_dir/merge-repo"
git init -q -b main "$merge_repo"
printf '# Rules\n\n- Name things by role.\n' > "$merge_repo/CLAUDE.md"
run_git_in "$merge_repo" add .
run_git_in "$merge_repo" commit -q -m base
run_git_in "$merge_repo" checkout -q -b lesson
printf 'x\n' > "$merge_repo/lesson.txt"
run_git_in "$merge_repo" add .
run_git_in "$merge_repo" commit -q -m lesson
run_git_in "$merge_repo" checkout -q main
echo '- A rule main already reviewed.' >> "$merge_repo/CLAUDE.md"
run_git_in "$merge_repo" commit -q -am "main rule"
run_git_in "$merge_repo" checkout -q lesson
run_git_in "$merge_repo" merge -q --no-commit --no-ff main > /dev/null
check_verdict allow "allowed: a merge of the base branch bringing a reviewed rule line" "git commit --no-edit" "$merge_repo"
run_git_in "$merge_repo" merge --abort
run_git_in "$merge_repo" checkout -q -b prose main
echo '- A prose-only rule from the branch.' >> "$merge_repo/CLAUDE.md"
run_git_in "$merge_repo" commit -q -am "branch prose"
run_git_in "$merge_repo" checkout -q main
run_git_in "$merge_repo" merge -q --no-commit --no-ff prose > /dev/null
check_verdict deny "blocked: a merge whose branch side adds a prose-only rule" "git commit --no-edit" "$merge_repo"
run_git_in "$merge_repo" merge --abort
run_git_in "$merge_repo" checkout -q -b quoted main
mkdir -p "$merge_repo/rules"
printf -- '- A rule.\n' > "$merge_repo/rules/a'\$(touch\${IFS}INJECTED)'b.md"
run_git_in "$merge_repo" add -A
run_git_in "$merge_repo" commit -q -m "odd path"
run_git_in "$merge_repo" checkout -q main
run_git_in "$merge_repo" merge -q --no-commit --no-ff quoted > /dev/null
check_verdict deny "blocked: a merge adding a rule under a quote-and-substitution path, with no command run" "git commit --no-edit" "$merge_repo"
expect_eq "the path was never run as a command" "" "$(find "$work_dir" "$PWD" -maxdepth 3 -name INJECTED 2>/dev/null)"
run_git_in "$merge_repo" merge --abort
# Outside a merge the filter does not run, so a line the default branch has stays blocked.
run_git_in "$merge_repo" checkout -q lesson
echo '- A rule main already reviewed.' >> "$merge_repo/CLAUDE.md"
run_git_in "$merge_repo" add CLAUDE.md
check_verdict deny "blocked: a normal commit adding a line the default branch already has" "git commit -m 'rule'" "$merge_repo"

# The merged commit is one the default branch has, but the default branch's file has since dropped the line.
dup_repo="$work_dir/dup-repo"
git init -q -b main "$dup_repo"
mkdir -p "$dup_repo/rules"
printf '# A\n\n- one\n\n# B\n\n- two\n' > "$dup_repo/AGENTS.md"
run_git_in "$dup_repo" add .
run_git_in "$dup_repo" commit -q -m base
run_git_in "$dup_repo" branch lesson
run_git_in "$dup_repo" checkout -q -b old
printf '\n- Old\n' >> "$dup_repo/AGENTS.md"
run_git_in "$dup_repo" commit -q -am "old"
run_git_in "$dup_repo" checkout -q -b other main
printf '# A\n\n- one\n- Dup\n\n# B\n\n- two\n\n- Dup\n' > "$dup_repo/AGENTS.md"
printf -- '- Dup\n' > "$dup_repo/rules/x.md"
run_git_in "$dup_repo" add .
run_git_in "$dup_repo" commit -q -m "other adds dup lines"
run_git_in "$dup_repo" checkout -q main
printf '# A\n\n- one\n- Dup\n\n# B\n\n- two\n' > "$dup_repo/AGENTS.md"
run_git_in "$dup_repo" commit -q -am "main has dup"
run_git_in "$dup_repo" merge -q --no-edit old > /dev/null
printf '# A\n\n- one\n- Dup\n\n# B\n\n- two\n' > "$dup_repo/AGENTS.md"
run_git_in "$dup_repo" commit -q -am "main drops old"
run_git_in "$dup_repo" checkout -q lesson
run_git_in "$dup_repo" merge -q --no-commit --no-ff old > /dev/null
check_verdict allow "allowed: a merge of a commit the default branch has, its line since dropped there" "git commit --no-edit" "$dup_repo"
run_git_in "$dup_repo" merge --abort
run_git_in "$dup_repo" checkout -q main
run_git_in "$dup_repo" merge -q --no-commit --no-ff other > /dev/null
check_verdict deny "blocked: a line known in one file does not excuse the same line in another file" "git commit --no-edit" "$dup_repo"
run_git_in "$dup_repo" merge --abort

# An added line shaped like a file header must not shift which reviewed file a later path reads.
hdr_repo="$work_dir/hdr-repo"
git init -q -b main "$hdr_repo"
mkdir -p "$hdr_repo/rules"
printf '# A\n' > "$hdr_repo/AGENTS.md"
printf '# Y\n' > "$hdr_repo/rules/y.md"
run_git_in "$hdr_repo" add .
run_git_in "$hdr_repo" commit -q -m base
run_git_in "$hdr_repo" branch lesson
printf '# A\n++ b/rules/z.md\n' > "$hdr_repo/AGENTS.md"
printf '# Y\n- Y rule\n' > "$hdr_repo/rules/y.md"
run_git_in "$hdr_repo" commit -q -am "main adds a header-shaped line and a rule"
run_git_in "$hdr_repo" checkout -q lesson
run_git_in "$hdr_repo" merge -q --no-commit --no-ff main > /dev/null
check_verdict allow "allowed: a carried-in header-shaped line does not misnumber the next file" "git commit --no-edit" "$hdr_repo"
run_git_in "$hdr_repo" merge --abort

finish
