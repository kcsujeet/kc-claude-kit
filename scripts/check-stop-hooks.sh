#!/usr/bin/env bash
# Fails when a plugin registers an end-of-turn hook (Stop or SubagentStop) that is not listed in
# .claude/stop-hooks-allowed.txt, or a listed one whose script reminds or blocks.
#
# An end-of-turn hook runs after the person has read the reply, so a reminder or a block there only
# adds noise ("Stop hook reported a problem") and a box-ticking line, and never changes the work.
# Put the check on the action it prevents instead: a PreToolUse hook that denies it, or a
# UserPromptSubmit or PostToolUse hook whose additionalContext reaches Claude before it acts. Keep an
# end-of-turn hook only for work that has to happen at the end of a turn and neither reminds nor
# blocks (recording state silently for the next turn).
#
# Allowlist, one line per hook: `<plugin> <event> <command name> <reason>`, the command name being
# the last path part of the hook's command (quotes stripped), the reason at least six words saying
# why it must run at the end of the turn and that it neither reminds nor blocks. A listed script
# inside its plugin is also read: a block decision, exit 2, additionalContext, systemMessage or a
# permission decision in it fails the check.
#
# Usage: check-stop-hooks.sh [repo-root]   (default: the current directory; CI runs it at the root)
# Prints one line per problem and exits 1 when there is any, 0 otherwise.
set -euo pipefail

root=${1:-.}
allowed_file=$root/.claude/stop-hooks-allowed.txt
min_reason_words=6
reminds_or_blocks='"decision": *"block"|decision: *"block"|exit 2|additionalContext|systemMessage|permissionDecision'
problems=0

note_problem() { echo "$1"; problems=$((problems + 1)); }

command -v jq >/dev/null 2>&1 || { echo "check-stop-hooks.sh needs jq" >&2; exit 1; }

# Prints the allowlist line for <plugin> <event> <command name>, or nothing.
get_allowed_line() {
  [ -f "$allowed_file" ] || return 0
  awk -v key="$1 $2 $3" 'index($0, key " ") == 1 { print; exit }' "$allowed_file"
}

for hooks_file in "$root"/plugins/*/hooks/hooks.json; do
  [ -f "$hooks_file" ] || continue
  plugin_dir=$(dirname "$(dirname "$hooks_file")")
  plugin=$(basename "$plugin_dir")
  while IFS=$'\t' read -r event command; do
    [ -n "$event" ] || continue
    name=${command%\"}
    name=${name##*/}
    allowed_line=$(get_allowed_line "$plugin" "$event" "$name")
    if [ -z "$allowed_line" ]; then
      note_problem "$plugin: $event hook '$name' is not in .claude/stop-hooks-allowed.txt. An end-of-turn hook runs after the person read the reply, so a reminder or block there never improves the work. Move it to the action it prevents (PreToolUse on that action, or UserPromptSubmit or PostToolUse additionalContext before Claude acts), or list it with the reason it must run at the end of the turn and neither reminds nor blocks."
      continue
    fi
    reason=${allowed_line#"$plugin $event $name "}
    # shellcheck disable=SC2086 # word count of the reason
    set -- $reason
    if [ "$#" -lt "$min_reason_words" ]; then
      note_problem "$plugin: $event hook '$name' is listed with a reason of fewer than $min_reason_words words; say why it must run at the end of the turn and that it neither reminds nor blocks."
    fi
    # shellcheck disable=SC2016 # the literal variable name as hooks.json writes it
    case "$command" in
      *'${CLAUDE_PLUGIN_ROOT}'/*)
        script=${command#*'${CLAUDE_PLUGIN_ROOT}'/}
        script="$plugin_dir/${script%\"}"
        if [ -f "$script" ] && grep -Eq "$reminds_or_blocks" "$script"; then
          note_problem "$plugin: $event hook '$name' is listed but its script reminds or blocks (matches: $reminds_or_blocks). An end-of-turn hook may only record state."
        fi
        ;;
    esac
  done < <(jq -r '.hooks | to_entries[] | select(.key == "Stop" or .key == "SubagentStop") | .key as $event | .value[].hooks[] | [$event, (.command // .prompt // .type)] | @tsv' "$hooks_file")
done

[ "$problems" -eq 0 ] || exit 1
echo "ok: every Stop and SubagentStop hook is listed, records only, and neither reminds nor blocks"
