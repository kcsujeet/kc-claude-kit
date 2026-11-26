#!/usr/bin/env bash
# Stop hook: blocks a turn that presented work with no "Better:" line. Work handed over because it
# works is not yet work handed over because nothing better was found: measure what was just done and
# look for a better way before saying done.
#
# It applies when the turn (everything after the person's last typed message) made a tool call that
# is not a pure read: an edit, a write, an agent dispatch, or a Bash or REPL command that is not
# plainly read-only (is_read_only_command). A turn of reads, or with no tool calls, passes.
#
# The final reply then needs a line starting "Better:" that carries evidence, either
#   Better: <change> with a number (a digit), or
#   Better: none, then what was tried or measured (a digit, or the word "tried").
# A bare "Better: none" or "Better: looks fine" blocks. On the second try (stop_hook_active) it passes.
#
# Input: the Stop payload on stdin. Output: the block JSON, or nothing. Never blocks what it can't
# read: no jq, no transcript or no reply exits 0. Hook schema: https://code.claude.com/docs/en/hooks
set -u

# shellcheck source=lib/reply-misses.sh
. "$(dirname "$0")/lib/reply-misses.sh"

# First words of commands that normally only read. The list is short on purpose: a read it lacks
# (sed, find, sort, curl, git -C) counts as work and asks for a Better: line once. A command in it is
# still work when it holds a redirect to a file, `$(` or a backtick (is_read_only_command).
readonly READ_ONLY_WORDS='(ls|cat|head|tail|grep|egrep|fgrep|rg|wc|echo|printf|pwd|cd|jq|stat|file|which|type|date|uniq|diff|cmp|test|\[|true|false|sleep|tree|du|df|basename|dirname|realpath|readlink|nl|cut|tr|column|sha256sum|shasum|md5|md5sum|git (status|log|diff|show|rev-parse|rev-list|ls-files|ls-tree|blame|describe|config --get|worktree list|cat-file|grep|merge-base|shortlog)|gh (pr|issue|run|repo|release) (view|list|checks|diff|status))'
# A REPL script that calls Agent, Edit, Write, MultiEdit, NotebookEdit or Bash (through its global or
# `tools.`), or edit() or write(). MCP tools are not counted, in a REPL or called directly.
readonly REPL_WORK_CALLS='(^|[^[:alnum:]_.])(tools\.)?(Agent|Edit|Write|MultiEdit|NotebookEdit|Bash)\(|(^|[^[:alnum:]_.])(edit|write)\('
# The shell a REPL script runs: a `$\`...\`` template, or `$("...")` with an optional timeout.
# shellcheck disable=SC2016 # the pattern holds JavaScript backticks and `$(`, not shell expansions
readonly REPL_SHELL_CALLS='\$`[^`]*`|\$\(["'"'"'][^"'"'"']*["'"'"'](, *[0-9]+)?\)'

payload=$(cat)
reply=$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty' 2>/dev/null)
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
stop_hook_active=$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ -n "$reply" ] || exit 0
[ "$stop_hook_active" = true ] && exit 0

# True when every command in the text (see list_stripped_commands) starts with a read-only word and
# writes no file (> or >> to anything but /dev/null or a stream, or --output) or runs a nested command.
is_read_only_command() {
  local command_text=$1 command_without_safe_redirects segment
  command_without_safe_redirects=$(printf '%s' "$command_text" | sed -E 's#[0-9]*>&[0-9]##g; s#[0-9]*>>?[[:space:]]*/dev/null##g')
  printf '%s' "$command_without_safe_redirects" | grep -Eq '>|--output|\$\(|`' && return 1
  while IFS= read -r segment; do
    printf '%s' "$segment" | grep -Eq "^$READ_ONLY_WORDS([[:space:]]|\$)" || return 1
  done < <(printf '%s\n' "$command_text" | list_stripped_commands)
  return 0
}

# True when the tool call (name, then its input) is more than a read.
is_work_call() {
  local tool_name=$1 tool_input=$2 shell_text
  printf '%s\t' "$tool_name" | grep -Eq "$EDIT_CALLS" && return 0
  case "$tool_name" in
    Agent) return 0 ;;
    Bash) ! is_read_only_command "$tool_input"; return ;;
    REPL)
      printf '%s' "$tool_input" | grep -Eq "$REPL_WORK_CALLS" && return 0
      shell_text=$(printf '%s' "$tool_input" | grep -oE "$REPL_SHELL_CALLS" | sed -E 's/^\$[`(]["'"'"']?//; s/["'"'"']?(, *[0-9]+)?[`)]$//')
      ! is_read_only_command "$shell_text"; return ;;
  esac
  return 1
}

did_work=false
while IFS=$'\t' read -r tool_name tool_input; do
  case "$tool_name" in Read | Grep | Glob) continue ;; esac # a read: skipped without a fork, a long turn has thousands
  if is_work_call "$tool_name" "$tool_input"; then did_work=true; break; fi
done < <(jq -L "$(dirname "$0")/lib" -rs 'include "typed-message"; turn_entries[] | get_tool_call_lines' "$transcript" 2>/dev/null)
[ "$did_work" = true ] || exit 0

# A "Better:" line (any Markdown emphasis around the label) with a number or the word tried in it.
better_text=$(printf '%s\n' "$reply" | sed -nE 's/^[[:space:]>*_-]*[Bb]etter[*_]*:[*_]*[[:space:]]*(.*)$/\1/p')
if printf '%s\n' "$better_text" | grep -Eiq '[0-9]|(^|[^[:alnum:]])tried([^[:alnum:]]|$)'; then
  exit 0
fi

printf '%s' "Blocked by the kc-gates plugin: work was done with no evidence of a better way. Run kc-conventions:kc-raise-the-bar: measure what you just did (time, runs, steps, size), look for a better way even if it works, deleting before adding, apply it or say what you tried. Then add: Better: <change, with numbers> or Better: none, tried <X>, <n> runs." \
  | jq -Rsc '{decision: "block", reason: .}'
exit 0
