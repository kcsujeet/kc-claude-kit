#!/usr/bin/env bash
# shellcheck disable=SC2016 # single-quoted text holds Markdown backticks and awk code, not shell expansions
# Fails when a checklist box in a SKILL.md `## Review checklist` section is longer than 220
# characters. A box is one line: `- [ ] §ID <rule> (<one example>)`. Longer wording goes in the skill's
# references/detail.md under `### §ID`, which the gate reads in full.
#
# Usage: check-box-length.sh [repo-root]   (default: the current directory; CI runs it at the root)
# Prints one line per box that is too long and exits 1 when there is any, 0 otherwise.
set -euo pipefail

root=${1:-.}
max_chars=220

problems=$(find "$root/plugins" -path '*/skills/*/SKILL.md' -type f -print0 \
  | xargs -0 --no-run-if-empty awk -v max="$max_chars" '
      FNR == 1 { in_checklist = 0 }
      /^## / { in_checklist = ($0 == "## Review checklist") }
      in_checklist && /^- \[[ xX]\]/ && length($0) > max {
        printf "%s:%d: box is %d characters (max %d): %s...\n", FILENAME, FNR, length($0), max, substr($0, 1, 60)
      }' | sort)
if [ -n "$problems" ]; then
  printf '%s\n' "$problems"
  echo "Move the extra wording to the skill's references/detail.md under \"### §ID\" and keep the box to one line."
  exit 1
fi
