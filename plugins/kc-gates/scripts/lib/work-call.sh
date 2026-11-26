#!/usr/bin/env bash
# shellcheck shell=bash
# What counts as work, for the hooks that act once per turn on the first work call
# (remind-better-line.sh). Sourced, never executed; the caller sources lib/reply-misses.sh first
# (EDIT_CALLS, list_stripped_commands).

# First words of commands that normally only read. The list is short on purpose: a read it lacks
# (sed, find, sort, curl, git -C) counts as work and gets the reminder once. A command in it is
# still work when it holds a redirect to a file, a lone `&`, `$(` or a backtick (is_read_only_command).
readonly READ_ONLY_WORDS='(ls|cat|head|tail|grep|egrep|fgrep|rg|wc|echo|printf|pwd|cd|jq|stat|file|which|type|date|uniq|diff|cmp|test|\[|true|false|sleep|tree|du|df|basename|dirname|realpath|readlink|nl|cut|tr|column|sha256sum|shasum|md5|md5sum|git (status|log|diff|show|rev-parse|rev-list|ls-files|ls-tree|blame|describe|config --get|worktree list|cat-file|grep|merge-base|shortlog)|gh (pr|issue|run|repo|release) (view|list|checks|diff|status))'
# A REPL script that calls Agent, Edit, Write, MultiEdit, NotebookEdit or Bash (through its global or
# `tools.`), or edit() or write(). MCP tools are not counted, in a REPL or called directly.
readonly REPL_WORK_CALLS='(^|[^[:alnum:]_.])(tools\.)?(Agent|Edit|Write|MultiEdit|NotebookEdit|Bash)\(|(^|[^[:alnum:]_.])(edit|write)\('
# Quoted text a read-only command may carry: a single-quoted string, or a double-quoted one with no backtick or backslash.
# shellcheck disable=SC2016 # a sed program, not a shell expansion
readonly QUOTED_TEXT='s/'"'"'[^'"'"']*'"'"'|"[^"`\\]*"//g'
# The shell a REPL script runs: a `$\`...\`` template, or `$("...")` with an optional timeout.
# shellcheck disable=SC2016 # the pattern holds JavaScript backticks and `$(`, not shell expansions
readonly REPL_SHELL_CALLS='\$`[^`]*`|\$\(["'"'"'][^"'"'"']*["'"'"'](, *[0-9]+)?\)'

# True when every command in the text (see list_stripped_commands) starts with a read-only word and
# writes no file (> or >> to anything but /dev/null or a stream, or --output), and starts no background
# job (`&`) or nested command.
is_read_only_command() {
  local command_without_quoted_text command_without_safe_operators segment
  printf '%s' "$1" | grep -Eq '\$\(|`' && return 1
  # Quoted text is data: drop it. A quote or backslash left over is one the shell may pair differently, so it is work.
  command_without_quoted_text=$(printf '%s' "$1" | sed -E "$QUOTED_TEXT")
  printf '%s' "$command_without_quoted_text" | grep -Eq "['\"\\\\]" && return 1
  command_without_safe_operators=$(printf '%s' "$command_without_quoted_text" | sed -E 's#[0-9]*>&[0-9]##g; s#[0-9]*>>?[[:space:]]*/dev/null##g; s#&&# #g')
  printf '%s' "$command_without_safe_operators" | grep -Eq '>|&|--output' && return 1
  while IFS= read -r segment; do
    printf '%s' "$segment" | grep -Eq "^$READ_ONLY_WORDS([[:space:]]|\$)" || return 1
  done < <(printf '%s\n' "$command_without_quoted_text" | list_stripped_commands)
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


