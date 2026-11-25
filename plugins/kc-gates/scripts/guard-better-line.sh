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
#   Better: <change> with a number (a digit, or before -> after), or
#   Better: none, then what was tried or measured (a digit, or the word "tried").
# A bare "Better: none" or "Better: looks fine" blocks. On the second try (stop_hook_active) it passes.
#
# Input: the Stop payload on stdin. Output: the block JSON, or nothing. Never blocks what it can't
# read: no jq, no transcript or no reply exits 0. Hook schema: https://code.claude.com/docs/en/hooks
set -u

# shellcheck source=lib/reply-misses.sh
. "$(dirname "$0")/lib/reply-misses.sh"

# First words of commands that only look: no file, network write or state change.
readonly READ_ONLY_WORDS='(ls|cat|head|tail|grep|egrep|fgrep|rg|find|wc|echo|printf|pwd|cd|jq|stat|file|which|type|date|sort|uniq|diff|cmp|test|\[|true|false|sleep|tree|du|df|env|basename|dirname|realpath|readlink|nl|cut|tr|awk|column|sha256sum|shasum|md5|md5sum|git (status|log|diff|show|branch|rev-parse|rev-list|ls-files|ls-tree|blame|describe|remote|fetch|config --get|worktree list|cat-file|grep|merge-base|shortlog)|gh (pr|issue|run|repo|release) (view|list|checks|diff|status)|gh api)'

payload=$(cat)
reply=$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty' 2>/dev/null)
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
stop_hook_active=$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ -n "$reply" ] || exit 0
[ "$stop_hook_active" = true ] && exit 0

# True when every command in the text (see list_stripped_commands) is plainly read-only: it starts
# with a read-only word and writes no file (> or >> to anything but /dev/null or a stream).
is_read_only_command() {
  local text=$1 segment
  printf '%s' "$text" | sed -E 's#[0-9]*>&[0-9]##g; s#[0-9]*>>?[[:space:]]*/dev/null##g' | grep -q '>' && return 1
  while IFS= read -r segment; do
    printf '%s' "$segment" | grep -Eq "^$READ_ONLY_WORDS([[:space:]]|\$)" || return 1
  done < <(printf '%s\n' "$text" | list_stripped_commands)
  return 0
}

# True when the tool call (name, then its target) is more than a read.
is_work_call() {
  local tool_name=$1 target=$2 shell_text
  case "$tool_name" in
    Edit | Write | MultiEdit | NotebookEdit | Agent) return 0 ;;
    Bash) is_read_only_command "$target" && return 1 || return 0 ;;
    REPL)
      printf '%s' "$target" | grep -Eq '(^|[^[:alnum:]_.])(edit|write)\(|tools\.(Agent|Edit|Write|NotebookEdit|Bash)\(' && return 0
      # shellcheck disable=SC2016 # the pattern holds JavaScript backticks, not a shell expansion
      shell_text=$(printf '%s' "$target" | grep -oE '\$`[^`]*`' | sed -E 's/^\$`//; s/`$//')
      is_read_only_command "$shell_text" && return 1
      return 0 ;;
  esac
  return 1
}

did_work=false
while IFS=$'\t' read -r tool_name target; do
  if is_work_call "$tool_name" "$target"; then did_work=true; break; fi
done < <(jq -L "$(dirname "$0")/lib" -rs 'include "typed-message"; turn_entries[] | get_tool_call_lines' "$transcript" 2>/dev/null)
[ "$did_work" = true ] || exit 0

# A "Better:" line (any Markdown emphasis around the label) with a number or the word tried in it.
better_text=$(printf '%s\n' "$reply" | sed -nE 's/^[[:space:]>*_-]*[Bb]etter[*_]*:[*_]*[[:space:]]*(.*)$/\1/p')
if printf '%s\n' "$better_text" | grep -Eiq '[0-9]|->|→|(^|[^[:alnum:]])tried([^[:alnum:]]|$)'; then
  exit 0
fi

printf '%s' "Blocked by the kc-gates plugin: work was done with no evidence of a better way. Run kc-conventions:kc-raise-the-bar: measure what you just did (time, runs, steps, size), look for a better way even if it works, deleting before adding, apply it or say what you tried. Then add: Better: <change, with numbers> or Better: none, tried <X>, <n> runs." \
  | jq -Rsc '{decision: "block", reason: .}'
exit 0
