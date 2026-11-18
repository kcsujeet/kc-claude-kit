#!/usr/bin/env bash
# Tests scripts/guard-prose-rule.sh: a `git commit` that adds net lines to an instruction file and
# changes no check file is denied unless the command carries KC_PROSE_APPROVED=1. Real repos in a
# temp folder. Each case runs twice, once with jq and once through the sed fallback.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
require_jq

git_in() { local repo=$1; shift; git -C "$repo" -c user.name=t -c user.email=t@example.test "$@"; }
repo="$work_dir/repo"
git init -q -b main "$repo"
mkdir -p "$repo/src" "$repo/plugin/skills/shop" "$repo/.claude/rules" "$repo/docs"
printf '# Rules\n\n- Name things by role.\n- Keep functions short.\n' > "$repo/CLAUDE.md"
printf 'export const total = 1\n' > "$repo/src/total.ts"
printf 'notes\n' > "$repo/docs/notes.md"
git_in "$repo" add .
git_in "$repo" commit -q -m base
reset_repo() { git -C "$repo" reset -q --hard HEAD; git -C "$repo" clean -qfd; mkdir -p "$repo/plugin/skills/shop" "$repo/.claude/rules"; }

build_payload() {
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"test"},"tool_use_id":"t"}' "$2" "$1"
}
check() {
  local expectation=$1 label=$2 command=$3 cwd=${4:-$repo} mode output verdict
  for mode in jq sed; do
    if [ "$mode" = sed ]; then
      output=$(build_payload "$command" "$cwd" | KC_GUARD_NO_JQ=1 bash "$scripts/guard-prose-rule.sh" 2>/dev/null)
    else
      output=$(build_payload "$command" "$cwd" | bash "$scripts/guard-prose-rule.sh" 2>/dev/null)
      last_output=$output
    fi
    if [ -z "$output" ]; then verdict=allow
    elif printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then verdict=deny
    else verdict="unexpected output: $output"; fi
    expect_eq "[$mode] $label" "$expectation" "$verdict"
  done
}

echo '- Prefer early returns.' >> "$repo/CLAUDE.md"
git_in "$repo" add CLAUDE.md
check deny "blocked: a CLAUDE.md rule with no check" "git commit -m 'rule'"
expect_contains "the message names the missing check" "a new rule needs a check that blocks the mistake in the same commit (script, hook, test or CI); prose alone is not accepted" "$last_output"
check allow "allowed: the same commit with KC_PROSE_APPROVED=1" "KC_PROSE_APPROVED=1 git commit -m 'rule'"
check deny "blocked: git -C <repo> commit" "git -C $repo commit -m 'rule'" "$work_dir"
check deny "blocked: cd into the repo, then commit" "cd $repo && git commit -m 'rule'" "$work_dir"
check allow "allowed: a command that is not a commit" "git status"
printf 'test -n 1\n' > "$repo/src/total.test.ts"
git_in "$repo" add src/total.test.ts
check allow "allowed: the same commit with a test file" "git commit -m 'rule and test'"
reset_repo

echo '- Prefer early returns.' >> "$repo/CLAUDE.md"
printf '#!/bin/sh\n' > "$repo/scripts-check.sh"
git_in "$repo" add .
check allow "allowed: the rule with a script file" "git commit -m 'rule and script'"
reset_repo

echo '- Prefer early returns.' >> "$repo/CLAUDE.md"
mkdir -p "$repo/.github/workflows"
printf 'name: ci\n' > "$repo/.github/workflows/ci.yml"
git_in "$repo" add .
check allow "allowed: the rule with a CI workflow" "git commit -m 'rule and ci'"
reset_repo

printf '# Shop\n\nSteps.\n' > "$repo/plugin/skills/shop/SKILL.md"
git_in "$repo" add .
check deny "blocked: a new SKILL.md with no check" "git commit -m 'skill'"
reset_repo

printf -- '- A rule.\n' > "$repo/.claude/rules/naming.md"
git_in "$repo" add .
check deny "blocked: a new .claude/rules file with no check" "git commit -m 'rules'"
reset_repo

printf '# Rules\n\n- Name things by role.\n' > "$repo/CLAUDE.md"
git_in "$repo" add CLAUDE.md
check allow "allowed: a deletion-only edit of an instruction file" "git commit -m 'drop a rule'"
reset_repo

sed 's/Keep functions short\./Keep functions small./' "$repo/CLAUDE.md" > "$work_dir/reword" && mv "$work_dir/reword" "$repo/CLAUDE.md"
git_in "$repo" add CLAUDE.md
check allow "allowed: a reworded line, no net new rule" "git commit -m 'reword'"
reset_repo

echo 'more notes' >> "$repo/docs/notes.md"
echo 'export const more = 2' >> "$repo/src/total.ts"
git_in "$repo" add .
check allow "allowed: added lines in files that are not instruction files" "git commit -m 'notes'"
reset_repo

echo '- Prefer early returns.' >> "$repo/CLAUDE.md"
check allow "allowed: an unstaged rule, plain commit" "git commit -m 'nothing staged'"
check deny "blocked: git commit -a reads the unstaged rule" "git commit -a -m 'all'"
check deny "blocked: git commit -am reads the unstaged rule" "git commit -am all"
reset_repo

finish
