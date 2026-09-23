#!/usr/bin/env bash
# Installs the plugin's generated rules into a project: copies every
# rules/*.md (found relative to this script, never guessed) into the
# destination, then writes <dest>/.kc-conventions-version from the plugin's
# .claude-plugin/plugin.json so the SessionStart hook can tell a current copy
# from a stale one. Copies, never symlinks: a symlink into the plugin's install
# directory breaks when the plugin updates or is removed.
#
# Usage: install-rules.sh [--dest <dir>] [--dry-run]
#   --dest     where to install (default: .claude/rules in the current directory)
#   --dry-run  print what would change and write nothing
#
# Output: one line per rule, `new: <file>`, `unchanged: <file>` or
# `replaced: <file>` (the installed copy differed and is overwritten; with
# --dry-run, `would replace: <file>`), then `version: <v>` and
# `installed <n> rule(s) into <dest>`.
# Exits 0 on success, 1 when the rules or the plugin version cannot be found,
# 2 on a usage error.
set -euo pipefail

script_name=$(basename "$0")
usage() {
  echo "usage: $script_name [--dest <dir>] [--dry-run]" >&2
  exit 2
}

dest_dir=".claude/rules"
dry_run=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dest)
      [ "$#" -ge 2 ] || usage
      dest_dir=$2
      shift
      ;;
    --dry-run) dry_run=true ;;
    *) usage ;;
  esac
  shift
done
[ -n "$dest_dir" ] || usage

plugin_dir=$(cd "$(dirname "$0")/.." && pwd)
rules_dir="$plugin_dir/rules"
plugin_json="$plugin_dir/.claude-plugin/plugin.json"

rule_count=0
for rule_file in "$rules_dir"/*.md; do
  [ -f "$rule_file" ] && rule_count=$((rule_count + 1))
done
if [ "$rule_count" -eq 0 ]; then
  echo "$script_name: no rules found at $rules_dir/*.md; reinstall the conventions plugin rather than building a path by hand" >&2
  exit 1
fi

plugin_version=""
if [ -f "$plugin_json" ]; then
  plugin_version=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$plugin_json" | head -n 1)
fi
if [ -z "$plugin_version" ]; then
  echo "$script_name: no version found in $plugin_json; refusing to write a guessed stamp" >&2
  exit 1
fi

if [ "$dry_run" = false ]; then
  mkdir -p "$dest_dir"
fi

for rule_file in "$rules_dir"/*.md; do
  rule_name=$(basename "$rule_file")
  installed_file="$dest_dir/$rule_name"
  if [ ! -e "$installed_file" ]; then
    status="new"
  elif cmp -s "$rule_file" "$installed_file"; then
    status="unchanged"
  else
    status="replaced"
  fi
  if [ "$dry_run" = true ]; then
    [ "$status" = replaced ] && status="would replace"
    echo "$status: $rule_name"
    continue
  fi
  if [ "$status" != unchanged ]; then
    # Remove first so a symlink left by an earlier install becomes a real copy.
    rm -f "$installed_file"
    cp "$rule_file" "$installed_file"
  fi
  if ! cmp -s "$rule_file" "$installed_file"; then
    echo "$script_name: copy of $rule_name does not match its source" >&2
    exit 1
  fi
  echo "$status: $rule_name"
done

if [ "$dry_run" = true ]; then
  echo "version: $plugin_version (dry run, nothing written)"
  exit 0
fi

printf '%s\n' "$plugin_version" > "$dest_dir/.kc-conventions-version"
echo "version: $plugin_version"
echo "installed $rule_count rule(s) into $dest_dir"
