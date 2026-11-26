#!/usr/bin/env bash
# Tests the guards of a commit for one command that changes what they judge: staging then committing
# (guard-prose-rule.sh, guard-loop-stop.sh). Real repos in a temp folder. Each hook case runs twice,
# once with jq and once through the sed fallback. The guards of a publish are in
# guard-chained-publish.test.sh, so each file runs inside a hook's time limit.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
require_jq

prose_verdict() { expect_hook_verdict "$scripts/guard-prose-rule.sh" "$1" "$2" "$3" "${4:-$repo}"; }

repo="$work_dir/repo"
git init -q -b main "$repo"
mkdir -p "$repo/src" "$repo/.claude"
printf '# Rules\n\n- Name things by role.\n' > "$repo/CLAUDE.md"
printf 'export const total = 1\n' > "$repo/src/total.ts"
printf '#!/bin/sh\n' > "$repo/build.sh"
printf -- '---\nledger: true\n---\n\n# Hand-off\n' > "$repo/.claude/hand-off-checklist.md"
run_git_in "$repo" add .
run_git_in "$repo" commit -q -m base
reset_repo() { git -C "$repo" reset -q --hard HEAD; git -C "$repo" clean -qfd; }

# One command that stages then commits is judged on what it will commit, not on today's index.
echo '- Prefer early returns.' >> "$repo/CLAUDE.md"
prose_verdict deny "blocked: git add -A && git commit with an unstaged rule" "git add -A && git commit -m rule"
prose_verdict deny "blocked: git add <path>; git commit" "git add CLAUDE.md; git commit -m rule"
prose_verdict deny "blocked: git add <other path> then commit -a reads the unstaged rule" "git add src/total.ts && git commit -a -m rule"
prose_verdict deny "blocked: a read-only git command before staging is not another command" "git status; git add -A && git commit -m rule"
prose_verdict deny "blocked: cd, add, commit" "cd $repo && git add -A && git commit -m rule" "$work_dir"
prose_verdict deny "blocked: git commit <path> commits the path as the working tree has it" "git commit CLAUDE.md -m rule"
prose_verdict allow "allowed: git commit <other path> leaves the rule out" "git commit src/total.ts -m x"
prose_verdict deny "blocked: an add of one path, then a commit of another path that holds the rule" "git add src/total.ts && git commit CLAUDE.md -m rule"
prose_verdict allow "allowed: a plain commit with nothing staged, as before" "git commit -m rule"
prose_verdict deny "blocked: a build step runs first, so what is staged is unknown" "./build.sh; git add -A && git commit -m rule"
prose_verdict deny "blocked: a command between two stagings can change what the second stages" "git add -A && echo '- More.' >> CLAUDE.md && git add -A && git commit -m rule"
prose_verdict deny "blocked: git rm changes the working tree, so the commit is unknown" "git rm -q src/total.ts && git commit -m drop"
expect_eq "the guard left the working file alone" "yes" "$([ -e "$repo/src/total.ts" ] && echo yes || echo no)"
printf 'test -n 1\n' > "$repo/src/total.test.ts"
prose_verdict allow "allowed: the same chain with a test file in the working tree" "git add -A && git commit -m rule"
prose_verdict allow "allowed: a command after the staging cannot change what is staged" "git add -A && ./build.sh && git commit -m rule"
reset_repo

echo 'export const more = 2' >> "$repo/src/total.ts"
prose_verdict allow "allowed: a chain that stages no rule" "git add -A && git commit -m code"
prose_verdict deny "blocked: a build step before staging, even with no rule in the working tree now" "./build.sh; git add -A && git commit -m code"
prose_verdict allow "allowed: a build step before a commit that stages nothing" "./build.sh; git commit -m code"
prose_verdict deny "blocked: a build step before commit -a, which reads the working tree" "./build.sh; git commit -am code"
prose_verdict deny "blocked: a build step before a commit of paths" "./build.sh; git commit src/total.ts -m code"
reset_repo

# An added path git rejects is replayed as add -A.
echo '- Prefer early returns.' >> "$repo/CLAUDE.md"
prose_verdict deny "blocked: a replayed add of a missing path falls back to add -A" "git add no-such-file && git commit -m rule"
reset_repo

# A rule staged first, then committed in a separate command, is judged on the index as before.
echo '- Prefer early returns.' >> "$repo/CLAUDE.md"
run_git_in "$repo" add CLAUDE.md
prose_verdict deny "blocked: the rule staged earlier, committed on its own" "git commit -m rule"
reset_repo

# Other commands that stage or rewrite files make the commit unjudgeable, and a path staged by the chain is judged.
run_git_in "$repo" checkout -q -b feature
echo '- Prefer early returns.' >> "$repo/CLAUDE.md"
run_git_in "$repo" commit -q -am "feature rule"
run_git_in "$repo" checkout -q main
prose_verdict deny "blocked: checkout <rev> -- <path> stages a rule before the commit" "git checkout feature -- CLAUDE.md && git commit -m rule"
prose_verdict deny "blocked: merge --squash stages a rule before the commit" "git merge --squash feature && git commit -m rule"
prose_verdict deny "blocked: cherry-pick -n stages a rule before the commit" "git cherry-pick -n feature && git commit -m rule"
mkdir -p "$repo/rules"
printf -- '- A new rule file.\n' > "$repo/rules/new.md"
prose_verdict deny "blocked: a new untracked rule file added and committed by path in one command" "git add rules/new.md && git commit rules/new.md -m rule"
reset_repo

# A repository with no commit yet: the copied index has nothing to read.
unborn_repo="$work_dir/unborn"
git init -q -b main "$unborn_repo"
printf -- '- A rule.\n' > "$unborn_repo/CLAUDE.md"
prose_verdict deny "blocked: a first commit that stages a rule in the same command" "git add -A && git commit -m first" "$unborn_repo"
if git init -q --object-format=sha256 -b main "$work_dir/sha256" > /dev/null 2>&1; then
  printf -- '- A rule.\n' > "$work_dir/sha256/CLAUDE.md"
  prose_verdict deny "blocked: a first commit in a sha256 repository" "git add -A && git commit -m first" "$work_dir/sha256"
fi

finish
