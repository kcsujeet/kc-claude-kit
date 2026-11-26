#!/usr/bin/env bash
# Tests guard-prose-rule.sh in the fewest cases that prove a chained add and commit is judged on what it
# will commit: refused with a rule in the working tree, allowed with none, refused after a build step.
# Small on purpose: the ledger check runs it inside a hook's time limit; the full cases are in
# guard-chained-commit.test.sh.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
require_jq

repo="$work_dir/repo"
git init -q -b main "$repo"
printf '# Rules\n\n- Name things by role.\n' > "$repo/CLAUDE.md"
printf 'export const total = 1\n' > "$repo/total.ts"
run_git_in "$repo" add .
run_git_in "$repo" commit -q -m base
prose_verdict() { expect_hook_verdict "$scripts/guard-prose-rule.sh" "$1" "$2" "$3" "$repo"; }

echo 'export const more = 2' >> "$repo/total.ts"
prose_verdict allow "allowed: a chain that stages no rule" "git add -A && git commit -m code"
prose_verdict deny "blocked: a build step before staging" "./build.sh; git add -A && git commit -m code"
echo '- Prefer early returns.' >> "$repo/CLAUDE.md"
prose_verdict deny "blocked: git add -A && git commit with an unstaged rule" "git add -A && git commit -m rule"

finish
