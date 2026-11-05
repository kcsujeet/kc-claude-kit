#!/usr/bin/env bash
# Lints the kit's rules as data, so prose that drifts fails CI instead of a review months later.
# Run from the repo root (CI does, on every PR). Checks the tracked Markdown and shell files,
# leaving out evals/ fixtures and CHANGELOG.md, whose history may name what no longer exists:
#
#   1. A checklist box id (`- [ ] §T1`) is used once per file. A reference file's sub-boxes may
#      repeat their parent's id (references/ files are skipped).
#   2. A rule's detail heading (`### §T1.`) has a box in its plugin, with that id or a lettered
#      sub-id (`§RL3a` for `§RL3`): a rule with no box gets skipped by the gates.
#   3. Every `§` reference resolves to a box or heading id, or to a lettered sub-id of one.
#   4. Every script named in backticks (`select-gates.sh`) exists in the repo.
#
# Prints one line per problem and exits 1 when there is any, 0 otherwise.
set -euo pipefail

id_pattern='§[A-Z]{1,2}[0-9]+[a-z]?'
problems=0
report() {
  echo "$1"
  problems=$((problems + 1))
}

markdown_files=$(git ls-files '*.md' | grep -vE '(^|/)evals/|^CHANGELOG\.md$' || true)
shell_files=$(git ls-files '*.sh' | grep -vE '(^|/)evals/' || true)

box_ids_in() {
  grep -ohE "^[[:space:]]*- \[ \] $id_pattern" "$@" 2>/dev/null | grep -oE "$id_pattern" || true
}
heading_ids_in() {
  grep -ohE "^(#{2,4} |\*\*)$id_pattern\." "$@" 2>/dev/null | grep -oE "$id_pattern" || true
}

# 1. Duplicate box ids within one file.
while IFS= read -r file; do
  [ -n "$file" ] || continue
  case "$file" in */references/*) continue ;; esac
  for duplicate in $(box_ids_in "$file" | sort | uniq -d); do
    report "$file: box id $duplicate is used for more than one box"
  done
done <<< "$markdown_files"

# 2. Detail headings with no box in their plugin.
for plugin_dir in $(printf '%s\n' "$markdown_files" | grep -oE '^plugins/[^/]+' | sort -u); do
  plugin_markdown=$(printf '%s\n' "$markdown_files" | grep "^$plugin_dir/" | grep -v '/rules/' || true)
  [ -n "$plugin_markdown" ] || continue
  # shellcheck disable=SC2086  # one path per word; tracked paths have no spaces
  plugin_boxes=$(box_ids_in $plugin_markdown | sort -u)
  # shellcheck disable=SC2086
  for heading_id in $(heading_ids_in $plugin_markdown | sort -u); do
    if ! printf '%s\n' "$plugin_boxes" | grep -qxE "${heading_id}[a-z]?"; then
      report "$plugin_dir: rule $heading_id has a detail heading but no checklist box"
    fi
  done
done

# 3. References that resolve to nothing.
# shellcheck disable=SC2086
defined_ids=$( { box_ids_in $markdown_files; heading_ids_in $markdown_files; } | sort -u)
# shellcheck disable=SC2086,SC2013  # one path per word; ids hold no spaces
for reference in $(grep -ohE "$id_pattern" $markdown_files $shell_files 2>/dev/null | sort -u); do
  base=${reference%[a-z]}
  if printf '%s\n' "$defined_ids" | grep -qxE "(${reference}|${base})|${reference}[a-z]"; then
    continue
  fi
  first_use=$(grep -lE "${reference}([^0-9a-z]|$)" $markdown_files $shell_files 2>/dev/null | head -n 1)
  report "$first_use: $reference refers to no rule"
done

# 4. Scripts named in backticks that don't exist.
script_names=$(git ls-files '*.sh' | sed 's#.*/##' | sort -u)
# shellcheck disable=SC2086,SC2013,SC2016  # the backtick is literal Markdown
for named_script in $(grep -ohE '`[^`]*\.sh' $markdown_files 2>/dev/null | grep -oE '[A-Za-z0-9_.-]+\.sh$' | sort -u); do
  if ! printf '%s\n' "$script_names" | grep -qxF "$named_script"; then
    first_use=$(grep -lF "$named_script" $markdown_files | head -n 1)
    report "$first_use: names $named_script, which is not in the repo"
  fi
done

if [ "$problems" -gt 0 ]; then
  echo "$problems problem(s)" >&2
  exit 1
fi
echo "rules lint: clean"
