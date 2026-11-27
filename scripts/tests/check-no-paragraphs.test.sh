#!/usr/bin/env bash
# Tests scripts/check-no-paragraphs.sh in a throwaway git repo: a prose paragraph line fails with its
# file and line; bullets, checkboxes, numbered items, headings, tables, quotes, fenced code, front matter,
# the one intro line under an H1, a template placeholder line, an indented continuation, CHANGELOG.md
# and files under evals/ or fixtures/ pass.
# shellcheck disable=SC2016 # single-quoted text holds Markdown backticks, not shell expansions
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/check-no-paragraphs.sh"
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT
git -C "$repo" init -q
passes=0
failures=0

pass() { echo "ok   $1"; passes=$((passes + 1)); }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

last_output=""
# expect_verdict <pass|fail> <label>: stages every file, then runs the check.
expect_verdict() {
  local expectation=$1 label=$2 actual=pass
  git -C "$repo" add -A
  last_output=$(bash "$script" "$repo" 2>&1) || actual=fail
  if [ "$actual" = "$expectation" ]; then pass "$label"; else fail "$label (expected $expectation, got $actual: $last_output)"; fi
}

printf -- '---\nname: x\ndescription: prose here is front matter\n---\n# Title\n\nOne intro line.\n\n## Rules\n\n- [ ] Check it\n- A fact\n  continued here\n1. Step\n\n| a | b |\n|---|---|\n\n> quoted prose\n\n```\nprose in a fence\n```\n\n{{PLACEHOLDER}}\n' > "$repo/ok.md"
expect_verdict pass "bullets, checkboxes, headings, tables, quotes, fences, front matter, one intro line and a placeholder pass"

printf '# Title\n\n## Rules\n\nA paragraph line.\n' > "$repo/bad.md"
expect_verdict fail "a paragraph line fails"
case "$last_output" in *"bad.md:5"*) pass "the message names the file and line" ;; *) fail "no file:line in: $last_output" ;; esac

printf '# Title\n\nIntro one.\n\nIntro two.\n' > "$repo/bad.md"
expect_verdict fail "a second paragraph under an H1 fails"

printf '# Title\n\n- [ ] Fine\nlazy continuation line\n' > "$repo/bad.md"
expect_verdict fail "an unindented continuation line fails"

printf '# Title\n\nprose\n' > "$repo/CHANGELOG.md"
printf '# T\n\n## S\n\nprose\n' > "$repo/bad.md"
rm "$repo/bad.md"
mkdir -p "$repo/plugins/p/evals/c" "$repo/plugins/p/tests/fixtures"
printf '# T\n\n## S\n\nprose\n' > "$repo/plugins/p/evals/c/prompt.md"
printf '# T\n\n## S\n\nprose\n' > "$repo/plugins/p/tests/fixtures/plan.md"
expect_verdict pass "CHANGELOG.md and evals/ and fixtures/ files are left alone"

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
