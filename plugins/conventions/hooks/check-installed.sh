#!/usr/bin/env bash
# Says nothing when the conventions are installed and current, so the normal case
# costs no context. Anything printed here lands in the model's context at session
# start. Bash 3.2 compatible, and reads JSON without jq.
set -u

# Not a project directory: stay quiet.
[ -d .git ] || exit 0

rules_dir=""
if [ -f .claude/rules/working-agreement.md ]; then
  rules_dir=".claude/rules"
elif [ -f "$HOME/.claude/rules/working-agreement.md" ]; then
  rules_dir="$HOME/.claude/rules"
fi

if [ -z "$rules_dir" ]; then
  echo "The portable coding conventions are not installed in this project. Run /conventions:init to copy them into .claude/rules/, or say so if this project should not have them."
  exit 0
fi

plugin_root=${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
plugin_json="$plugin_root/.claude-plugin/plugin.json"
[ -f "$plugin_json" ] || exit 0
plugin_version=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$plugin_json" | head -n 1)
# Without a readable plugin version there is nothing to compare against.
[ -n "$plugin_version" ] || exit 0

stamp_file="$rules_dir/.kc-conventions-version"
installed_version=""
[ -f "$stamp_file" ] && installed_version=$(head -n 1 "$stamp_file" | tr -d '[:space:]')

[ "$installed_version" = "$plugin_version" ] && exit 0

if [ -z "$installed_version" ]; then
  echo "The portable coding conventions in $rules_dir carry no version stamp, so they may predate conventions plugin $plugin_version. Run /conventions:init to refresh them."
else
  echo "The portable coding conventions in $rules_dir are from conventions plugin $installed_version, but $plugin_version is installed. Run /conventions:init to refresh them."
fi
