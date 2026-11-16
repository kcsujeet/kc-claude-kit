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
#   5. Every relative Markdown link `](path)` and backticked `docs/....md` path in README.md,
#      CLAUDE.md, docs/*.md and plugins/**/*.md resolves to a file (anchors after `#` are ignored,
#      http and mailto links and `<placeholder>` targets skipped; plugin text may name docs paths
#      of the repos that install it, so the backticked form is checked outside plugins/ only).
#   6. A citation of the working agreement's step ("working agreement's step 6", "Order of work on
#      a task, step 6") names a step in that rule's "Order of work on a task" numbered list.
#
# Prints one line per problem and exits 1 when there is any, 0 otherwise.
set -euo pipefail

id_pattern='§[A-Z]{1,2}[0-9]+[a-z]?'
problems=0
report() {
  echo "$1"
  problems=$((problems + 1))
}

work_file=$(mktemp)
trap 'rm -f "$work_file"' EXIT

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

# 5. Links and docs paths that resolve to no file.
link_files=$(printf '%s\n' "$markdown_files" | grep -E '^(README\.md|CLAUDE\.md|docs/[^/]+\.md|plugins/.*\.md)$' || true)
while IFS= read -r file; do
  [ -n "$file" ] || continue
  base_dir=$(dirname "$file")
  # shellcheck disable=SC2016  # the backtick is literal Markdown
  { grep -oE '\]\([^) ]+\)' "$file" | sed -E 's/^\]\((.*)\)$/link \1/' || true
    # Plugin text names docs in the repos that install it, so only the repo's own Markdown is held to this.
    case "$file" in plugins/*) ;; *) grep -oE '`docs/[A-Za-z0-9_./-]+\.md[^`]*`' "$file" | sed -E 's/^`(.*)`$/docs \1/' || true ;; esac; } |
    while read -r kind target; do
      case "$target" in http://* | https://* | mailto:* | '#'* | *'<'*) continue ;; esac
      target=${target%%#*}
      [ -n "$target" ] || continue
      if [ "$kind" = docs ]; then
        resolved=$target
      else
        case "$target" in /*) resolved=${target#/} ;; *) resolved="$base_dir/$target" ;; esac
      fi
      [ -e "$resolved" ] || echo "$file: links to $target, which is not in the repo"
    done
done <<< "$link_files" > "$work_file"
while IFS= read -r line; do
  [ -n "$line" ] && report "$line"
done < "$work_file"

# 6. Citations of the working agreement's steps that name a step it does not have.
agreement=plugins/kc-conventions/rules/kc-working-agreement.md
if [ -f "$agreement" ]; then
  last_step=$(awk '/^## Order of work on a task/ { inside = 1; next } /^## / { inside = 0 } inside && /^[0-9]+\. / { n = $1 + 0; if (n > last) last = n } END { print last + 0 }' "$agreement")
  # shellcheck disable=SC2086,SC2013
  for citation in $(grep -ohE "(Order of work on a task\"?[^A-Za-z0-9]{1,4}|working agreement('s)? )step [0-9]+" $markdown_files 2>/dev/null | grep -oE 'step [0-9]+$' | sort -u | tr ' ' '_'); do
    step_number=${citation#step_}
    if [ "$step_number" -lt 1 ] || [ "$step_number" -gt "$last_step" ]; then
      first_use=$(grep -lE "(Order of work on a task\"?[^A-Za-z0-9]{1,4}|working agreement('s)? )step ${step_number}([^0-9]|$)" $markdown_files | head -n 1)
      report "$first_use: cites the working agreement's step $step_number, but its Order of work on a task has $last_step steps"
    fi
  done
fi

if [ "$problems" -gt 0 ]; then
  echo "$problems problem(s)" >&2
  exit 1
fi
echo "rules lint: clean"
