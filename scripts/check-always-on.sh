#!/usr/bin/env bash
# Measures what the kit puts in every session's context, in bytes (~tokens = bytes / 4, an
# estimate): always-on rule files (plugins/*/rules/*.md with no `paths:` frontmatter), every
# skill's and agent's frontmatter description, and the text SessionStart and UserPromptSubmit
# hooks print. Hook scripts are run with a minimal payload, an empty HOME and a PATH without
# `gh` or `claude`, so nothing reaches the network; update-marketplace.sh and async hooks are
# skipped.
#
# Usage: check-always-on.sh [--root <dir>] [--budget-rules <bytes>] [--budget-descriptions <bytes>]
#        [--max-description <bytes>] [--budget-hooks <bytes>]
# Without budget flags it only reports. With them it exits 1, naming each budget exceeded and by
# how much. Run it before and after a change that adds always-on text, and give both numbers.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
budget_rules=""
budget_descriptions=""
max_description=""
budget_hooks=""

while [ $# -gt 0 ]; do
  case "$1" in
    --root) root=$(cd "$2" && pwd); shift 2 ;;
    --budget-rules) budget_rules=$2; shift 2 ;;
    --budget-descriptions) budget_descriptions=$2; shift 2 ;;
    --max-description) max_description=$2; shift 2 ;;
    --budget-hooks) budget_hooks=$2; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

bytes_of() { wc -c < "$1" | tr -d ' '; }
tokens_of() { echo $(($1 / 4)); }

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

# Prints the frontmatter description of a file, quotes removed, continuation lines joined.
description_of() {
  awk '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    /^description:/ {
      sub(/^description:[[:space:]]*/, ""); value = $0; capture = 1; next
    }
    capture && /^[[:space:]]+/ { sub(/^[[:space:]]+/, ""); value = value (value == "" ? "" : " ") $0; next }
    { capture = 0 }
    END {
      if (value ~ /^[>|][-+]?$/) value = ""
      if (value ~ /^".*"$/ || value ~ /^'"'"'.*'"'"'$/) value = substr(value, 2, length(value) - 2)
      printf "%s", value
    }
  ' "$1"
}

# True when the file has a `paths:` key inside its frontmatter.
has_paths() {
  awk 'NR == 1 && $0 != "---" { exit 1 } NR > 1 && $0 == "---" { exit found ? 0 : 1 } /^paths:/ { found = 1 } END { if (NR < 2) exit 1 }' "$1"
}

problems=""
note_problem() { problems="${problems}${1}"$'\n'; }

# --- always-on rule files ---------------------------------------------------------------
rules_total=0
rules_count=0
rules_lines=""
for file in "$root"/plugins/*/rules/*.md; do
  [ -f "$file" ] || continue
  if has_paths "$file"; then continue; fi
  size=$(bytes_of "$file")
  rules_total=$((rules_total + size))
  rules_count=$((rules_count + 1))
  rules_lines="${rules_lines}  ${size}  ${file#"$root"/}"$'\n'
done
echo "Always-on rule files: $rules_count file(s), $rules_total bytes (~$(tokens_of "$rules_total") tokens, estimate)"
printf '%s' "$rules_lines"

# --- skill and agent descriptions -------------------------------------------------------
desc_total=0
desc_count=0
: > "$scratch/descriptions"
for file in "$root"/plugins/*/skills/*/SKILL.md "$root"/plugins/*/agents/*.md; do
  [ -f "$file" ] || continue
  size=$(description_of "$file" | wc -c | tr -d ' ')
  desc_total=$((desc_total + size))
  desc_count=$((desc_count + 1))
  echo "$size ${file#"$root"/}" >> "$scratch/descriptions"
done
echo
echo "Skill and agent descriptions: $desc_count, $desc_total bytes (~$(tokens_of "$desc_total") tokens, estimate)"
echo "  longest five:"
sort -rn "$scratch/descriptions" | head -n 5 | sed 's/^/    /'

# --- hook-printed text ------------------------------------------------------------------
home_dir="$scratch/home"
work_dir="$scratch/work"
bin_dir="$scratch/bin"
mkdir -p "$home_dir" "$work_dir" "$bin_dir"
for tool in bash sh cat grep egrep sed awk jq git date mkdir rm cut tr sort uniq head tail wc dirname \
  basename env find ls mktemp cp mv sleep uname id stat shasum md5 readlink tee xargs diff printf test \
  expr realpath touch chmod ps hostname whoami tty od cmp python3 perl; do
  path=$(command -v "$tool" 2>/dev/null || true)
  case "$path" in /*) ln -sf "$path" "$bin_dir/$tool" ;; esac
done
payload="{\"cwd\":\"$work_dir\",\"session_id\":\"budget\",\"prompt\":\"hi\"}"

hooks_total=0
echo
echo "Hook-printed text (SessionStart and UserPromptSubmit, minimal payload):"
for hooks_file in "$root"/plugins/*/hooks/hooks.json; do
  [ -f "$hooks_file" ] || continue
  plugin_dir=$(dirname "$(dirname "$hooks_file")")
  for event in SessionStart UserPromptSubmit; do
    commands=$(jq -r --arg event "$event" '
      (.hooks[$event] // [])[].hooks[]
      | select(.type == "command" and ((.async // false) | not))
      | .command' "$hooks_file" 2>/dev/null || true)
    [ -n "$commands" ] || continue
    while IFS= read -r command; do
      [ -n "$command" ] || continue
      case "$command" in *update-marketplace.sh*) continue ;; esac
      size=$(
        cd "$work_dir" &&
          printf '%s' "$payload" |
          env -i PATH="$bin_dir" HOME="$home_dir" CLAUDE_CONFIG_DIR="$home_dir" \
            CLAUDE_PLUGIN_ROOT="$plugin_dir" CLAUDE_PROJECT_DIR="$work_dir" \
            "$bin_dir/bash" -c "$command" 2>/dev/null | wc -c | tr -d ' '
      ) || size=0
      hooks_total=$((hooks_total + size))
      name=${command##*/}
      name=${name%\"}
      echo "  ${size}  $(basename "$plugin_dir")/${name} ($event)"
    done <<< "$commands"
  done
done
echo "  total: $hooks_total bytes (~$(tokens_of "$hooks_total") tokens, estimate)"

# --- budgets ----------------------------------------------------------------------------
over() { # <label> <actual> <budget>
  if [ -n "$3" ] && [ "$2" -gt "$3" ]; then
    note_problem "over budget: $1 is $2 bytes, budget $3, over by $(($2 - $3))"
  fi
}
over "always-on rules" "$rules_total" "$budget_rules"
over "descriptions" "$desc_total" "$budget_descriptions"
over "hook-printed text" "$hooks_total" "$budget_hooks"
if [ -n "$max_description" ]; then
  while read -r size path; do
    if [ "$size" -gt "$max_description" ]; then
      note_problem "over budget: description of $path is $size bytes, maximum $max_description, over by $((size - max_description))"
    fi
  done < "$scratch/descriptions"
fi

if [ -n "$problems" ]; then
  echo
  printf '%s' "$problems"
  exit 1
fi
