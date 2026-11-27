#!/usr/bin/env bash
# shellcheck disable=SC2016 # single-quoted text holds Markdown backticks and awk code, not shell expansions
# Fails when a tracked Markdown file has a prose paragraph line. Things to do or check are checkboxes
# (`- [ ] ...`) and everything else is a bullet. Allowed outside lists: headings, fenced code, tables,
# blockquotes, HTML, front matter, indented lines (a list item's continuation), a bare template
# placeholder line (`{{NAME}}`) and one intro line directly under an H1.
# Left alone: CHANGELOG.md and anything under evals/, fixtures/ or tests/ (test inputs, not instructions).
#
# Usage: check-no-paragraphs.sh [repo-root]   (default: the current directory; CI runs it at the root)
# Prints one line per paragraph line and exits 1 when there is any, 0 otherwise.
set -euo pipefail

root=${1:-.}

problems=$(git -C "$root" ls-files -z '*.md' \
  | { grep -zvE '(^|/)(evals|fixtures|tests)/|^CHANGELOG\.md$' || true; } \
  | (cd "$root" && xargs -0 --no-run-if-empty awk '
      FNR == 1 { in_front_matter = 0; in_fence = 0; after_h1 = 0 }
      FNR == 1 && $0 == "---" { in_front_matter = 1; next }
      in_front_matter { if ($0 == "---") in_front_matter = 0; next }
      /^[ \t]*```/ { in_fence = !in_fence; next }
      in_fence { next }
      /^[ \t]*$/ { next }
      /^#/ { after_h1 = ($0 ~ /^# /); next }
      /^[ \t]*([-*+]|[0-9]+[.)]) / || /^[ \t]*[|>]/ || /^[ \t]*</ || /^[ \t]+[^ \t]/ { after_h1 = 0; next }
      /^\{\{[A-Z_]+\}\}$/ { next }
      after_h1 { after_h1 = 0; next }
      { printf "%s:%d: paragraph line (use a bullet or a checkbox): %s...\n", FILENAME, FNR, substr($0, 1, 60) }') | sort)
if [ -n "$problems" ]; then
  printf '%s\n' "$problems"
  exit 1
fi
