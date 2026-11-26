#!/usr/bin/env bash
# Tests the guards that judge a command before it runs, for a command that changes what they judge:
# one command that stages then commits (guard-prose-rule.sh), one that commits then pushes
# (guard-lesson-ledger.sh, guard-hand-off.sh), and a session whose loaded kc-gates is older than the
# installed one (guard-lesson-ledger.sh, check-loaded-version.sh --print-stale). Real repos in a temp
# folder. Each hook case runs twice, once with jq and once through the sed fallback.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
require_jq

run_git_in() { local repo=$1; shift; git -C "$repo" -c user.name=t -c user.email=t@example.test "$@"; }
prose_verdict() { expect_hook_verdict "$scripts/guard-prose-rule.sh" "$1" "$2" "$3" "${4:-$repo}"; }
ledger_verdict() { expect_hook_verdict "$scripts/guard-lesson-ledger.sh" "$1" "$2" "$3" "${4:-$repo}"; }

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
prose_verdict deny "blocked: cd, add, commit" "cd $repo && git add -A && git commit -m rule" "$work_dir"
prose_verdict deny "blocked: git commit <path> commits the path as the working tree has it" "git commit CLAUDE.md -m rule"
prose_verdict allow "allowed: git commit <other path> leaves the rule out" "git commit src/total.ts -m x"
prose_verdict allow "allowed: a plain commit with nothing staged, as before" "git commit -m rule"
prose_verdict deny "blocked: a build step runs first, so what is staged is unknown" "./build.sh; git add -A && git commit -m rule"
printf 'test -n 1\n' > "$repo/src/total.test.ts"
prose_verdict allow "allowed: the same chain with a test file in the working tree" "git add -A && git commit -m rule"
reset_repo

echo 'export const more = 2' >> "$repo/src/total.ts"
prose_verdict allow "allowed: a chain that stages no rule" "git add -A && git commit -m code"
prose_verdict deny "blocked: a build step before staging, even with no rule in the working tree now" "./build.sh; git add -A && git commit -m code"
prose_verdict allow "allowed: a build step before a commit with nothing staged by the command" "./build.sh; git commit -m code"
reset_repo

# Replaying git rm on the copy must not delete the working file.
prose_verdict allow "allowed: git rm then commit stages no rule" "git rm -q src/total.ts && git commit -m drop"
expect_eq "the guard left the working file alone" "yes" "$([ -e "$repo/src/total.ts" ] && echo yes || echo no)"
reset_repo

# A rule staged first, then committed in a separate command, is judged on the index as before.
echo '- Prefer early returns.' >> "$repo/CLAUDE.md"
run_git_in "$repo" add CLAUDE.md
prose_verdict deny "blocked: the rule staged earlier, committed on its own" "git commit -m rule"
reset_repo

# A session that runs an older kc-gates than the installed one is refused in a repo with a ledger.
config_dir="$work_dir/config"
cache_dir="$config_dir/plugins/cache/shop/kc-gates"
mkdir -p "$cache_dir/1.0.0" "$cache_dir/1.1.0"
write_installs() { printf '{"plugins":{"kc-gates@shop":[{"scope":"user","installPath":"%s/%s","version":"%s"}]}}\n' "$cache_dir" "$1" "$1" > "$config_dir/plugins/installed_plugins.json"; }
other_repo="$work_dir/other"
git init -q -b main "$other_repo"
printf 'x\n' > "$other_repo/x.txt"
run_git_in "$other_repo" add .
run_git_in "$other_repo" commit -q -m base
export CLAUDE_CONFIG_DIR="$config_dir" CLAUDE_PLUGIN_ROOT="$cache_dir/1.0.0"
write_installs 1.1.0
ledger_verdict deny "blocked: a stale session commits in a ledger repo" "git commit -m x"
expect_contains "the block says to reload" "/reload-plugins" "$last_hook_output"
run_git_in "$repo" checkout -q -b lesson
ledger_verdict deny "blocked: a stale session pushes in a ledger repo" "git push -u origin lesson"
expect_contains "the push block says the session is older" "older kc-gates than the installed 1.1.0" "$last_hook_output"
ledger_verdict allow "allowed: a stale session in a repo with no ledger" "git commit -m x" "$other_repo"
write_installs 1.0.0
ledger_verdict allow "allowed: a current session commits in a ledger repo" "git commit -m x"
export CLAUDE_PLUGIN_ROOT="$work_dir/clone/plugins/kc-gates"
write_installs 1.1.0
ledger_verdict allow "allowed: a copy loaded from a clone is not stale" "git commit -m x"
unset CLAUDE_PLUGIN_ROOT CLAUDE_CONFIG_DIR

# One command that commits then pushes is judged on a HEAD from before the commit, so it is refused.
ledger_verdict deny "blocked: commit then push in a ledger repo" "git commit -m x && git push -u origin lesson"
expect_contains "the block says to commit first" "Commit in one command" "$last_hook_output"
ledger_verdict deny "blocked: the push alone still needs its ledger" "git push -u origin lesson"
expect_not_contains "the plain push is refused for its ledger, not for the chain" "Commit in one command" "$last_hook_output"

# The same for the first push of a branch (guard-hand-off.sh).
remote="$work_dir/remote.git"
git init -q --bare "$remote"
run_git_in "$repo" remote add origin "$remote"
chain_verdict() { expect_hook_verdict "$scripts/guard-hand-off.sh" "$1" "$2" "$3" "$repo"; }
chain_verdict deny "blocked: commit then first push of a branch" "git commit -m x && git push -u origin lesson"
expect_contains "the hand-off block says to commit first" "Commit in one command" "$last_hook_output"
chain_verdict deny "blocked: the first push alone has no receipt" "git push -u origin lesson"
expect_not_contains "the plain first push is refused for its receipt" "Commit in one command" "$last_hook_output"
chain_verdict deny "blocked: commit then open a PR" "git commit -m x && gh pr create --fill"
expect_contains "the PR block says to commit first" "Commit in one command" "$last_hook_output"
chain_verdict allow "allowed: commit then push of a branch the remote has" "git push -u origin main"

finish
