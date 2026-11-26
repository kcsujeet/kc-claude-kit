#!/usr/bin/env bash
# Runs the repo's lint on the files a push would add: those changed from <base> to <head>
# (added, copied, modified or renamed; deleted ones are gone). guard-hand-off.sh calls it before
# a push, so a lint failure is found where the push is, not in CI after it.
#
# How the repo lints:
#   .claude/lint-command   one line, a command that takes file paths as its arguments
#                          (`npx biome check`, `bundle exec rubocop`); run from the repo root
#   (no such file)         `npx biome check` when biome.json is at the repo root, on the changed
#                          files Biome reads (js, ts, jsx, tsx, mjs, cjs, json, jsonc, css)
#   neither                nothing runs
#
# Usage: lint-changed-files.sh <repo-dir> <base> <head>
#        lint-changed-files.sh --configured <repo-dir>   exits 0 when a lint command would run, 1 when not
# Output: the lint command's output, when it fails. Exits 1 when the lint fails, 0 when it passes
# or there is nothing to run.
set -uo pipefail

configured_only=false
if [ "${1:-}" = --configured ] && [ "$#" -eq 2 ]; then configured_only=true; set -- "$2" _ _; fi
[ "$#" -eq 3 ] || { echo "usage: lint-changed-files.sh <repo-dir> <base> <head>" >&2; exit 2; }
repo=$1 base=$2 head=$3
root=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null) || { $configured_only && exit 1; exit 0; }

lint_command=""
filter='.'
if [ -r "$root/.claude/lint-command" ]; then
  lint_command=$(grep -v '^[[:space:]]*\(#\|$\)' "$root/.claude/lint-command" | head -n 1)
elif [ -f "$root/biome.json" ]; then
  lint_command="npx biome check"
  filter='\.(js|jsx|ts|tsx|mjs|cjs|json|jsonc|css)$'
fi
if $configured_only; then [ -n "$lint_command" ]; exit; fi
[ -n "$lint_command" ] || exit 0

files=()
while IFS= read -r changed_file; do
  files+=("$changed_file")
done < <(git -C "$root" diff --name-only --diff-filter=ACMR "$base" "$head" 2>/dev/null | grep -E "$filter")
[ "${#files[@]}" -gt 0 ] || exit 0

cd "$root" || exit 0
bash -c "$lint_command \"\$@\"" lint "${files[@]}" 2>&1
