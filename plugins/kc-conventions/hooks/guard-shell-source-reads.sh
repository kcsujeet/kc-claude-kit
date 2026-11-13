#!/usr/bin/env bash
# PreToolUse guard for Bash: blocks printing a source file's contents through the shell.
#
# Path-scoped rules and nested CLAUDE.md files load only when the Read tool opens a matching file.
# A file printed through the shell loads none of them, so an agent that reads code with `cat`,
# `sed` or `git show` works without its conventions. An instruction to use the Read tool is easy to
# forget; a deny does not depend on remembering it.
#
# A shell read is a segment (split on newlines, ;, &&, || and |) that either
#   - runs cat, head, tail, less, more, bat, nl or sed (sed without -i or --in-place) with an
#     argument ending in a source extension (ts tsx js jsx mjs cjs rb py swift go java kt php cs rs),
#     or
#   - runs `git show` (also `git -C <dir> show`) with a `<rev>:<path>` argument whose path ends in
#     a source extension and whose rev is not a commit id.
# A redirect target (`> file.ts`) is a write, not a read. Searching (grep, rg, git grep), git log,
# git diff, `git show <rev>` without a path, wc, ls, find, sed -i and files with other extensions
# stay allowed. So does `git show <sha>:<path>` at a pinned commit (hex, 7 to 40 characters), which
# a review reads to cite `path:line@sha`; a branch or symbolic ref (origin/main, main, HEAD, a tag)
# is a base to open as a worktree, so it is refused. There is no escape-hatch token: an agent could add it itself.
#
# Output: the PreToolUse deny JSON on a shell read, nothing otherwise. Always exits 0.
# Hook schema: https://code.claude.com/docs/en/hooks
#
# KC_GUARD_NO_JQ=1 forces the sed fallback (used by the tests).

set -u

readonly SOURCE_EXTENSIONS='(ts|tsx|js|jsx|mjs|cjs|rb|py|swift|go|java|kt|php|cs|rs)'
readonly READ_COMMANDS=' cat head tail less more bat nl sed '

# Prints the command of the payload (jq, or a sed fallback).
extract_field() {
  local input="$1"
  if [ "${KC_GUARD_NO_JQ:-0}" != 1 ] && command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null
    return
  fi
  # JSON strings hold no raw newlines, so joining lines is safe. The capture
  # keeps escapes such as \" and \n; the callers tolerate them.
  printf '%s' "$input" \
    | tr '\n' ' ' \
    | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' \
    | sed -e 's/\\n/\
/g' -e 's/\\"/"/g'
}

# One shell segment per line: split on newlines, ;, &&, || and |.
split_segments() {
  printf '%s\n' "$1" | sed -e 's/&&/\
/g' -e 's/||/\
/g' -e 's/;/\
/g' -e 's/|/\
/g'
}

# Prints the first source file the segment prints through the shell; returns 1 when it prints none.
shell_read_file() {
  local segment="$1" tokens=() args=() token prev='' word subcommand skip_next=0 in_place=0 path rev
  read -ra tokens <<< "$segment"
  local count=${#tokens[@]} index=0

  # Leading VAR=value assignments and shell keywords are not the command.
  while [ "$index" -lt "$count" ]; do
    token="${tokens[$index]}"
    case "$token" in
      [A-Za-z_]*=* | do | then | else | '{' | '(' | '!') index=$((index + 1)) ;;
      *) break ;;
    esac
  done
  [ "$index" -lt "$count" ] || return 1

  word="${tokens[$index]}"
  word="${word//[\'\"]/}"
  word="${word##*/}"
  index=$((index + 1))

  # Arguments with quotes stripped; a redirect target is a write, so it is left out.
  for ((; index < count; index++)); do
    token="${tokens[$index]//[\'\"]/}"
    case "$prev" in
      '>' | '>>' | [0-9]'>' | [0-9]'>>' | '&>') prev="$token"; continue ;;
    esac
    prev="$token"
    case "$token" in
      '>'* | [0-9]'>'* | '&>'*) continue ;;
    esac
    args+=("$token")
  done

  if [ "$word" = git ]; then
    subcommand=''
    local rest=()
    for token in "${args[@]+"${args[@]}"}"; do
      if [ -z "$subcommand" ]; then
        if [ "$skip_next" = 1 ]; then skip_next=0; continue; fi
        case "$token" in
          -C | -c) skip_next=1 ;;
          -*) ;;
          *) subcommand="$token" ;;
        esac
      else
        rest+=("$token")
      fi
    done
    [ "$subcommand" = show ] || return 1
    for token in "${rest[@]+"${rest[@]}"}"; do
      if [[ "$token" =~ ^([^:[:space:]]*):(.*\.${SOURCE_EXTENSIONS})$ ]]; then
        rev="${BASH_REMATCH[1]}"
        path="${BASH_REMATCH[2]}"
        [[ "$rev" =~ ^[0-9a-f]{7,40}$ ]] && continue
        printf '%s' "$path"
        return 0
      fi
    done
    return 1
  fi

  case "$READ_COMMANDS" in
    *" $word "*) ;;
    *) return 1 ;;
  esac
  if [ "$word" = sed ]; then
    for token in "${args[@]+"${args[@]}"}"; do
      case "$token" in
        --in-place* ) in_place=1 ;;
        --*) ;;
        -*i*) in_place=1 ;;
      esac
    done
    [ "$in_place" = 0 ] || return 1
  fi
  for token in "${args[@]+"${args[@]}"}"; do
    if [[ "$token" =~ \.${SOURCE_EXTENSIONS}$ ]]; then
      printf '%s' "$token"
      return 0
    fi
  done
  return 1
}

first_shell_read() {
  local segment file
  while IFS= read -r segment; do
    if file="$(shell_read_file "$segment")"; then
      printf '%s' "$file"
      return 0
    fi
  done <<EOF
$(split_segments "$1")
EOF
  return 1
}

print_deny() {
  local file="$1"
  file="${file//\\/\\\\}"
  file="${file//\"/\\\"}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked by the kc-conventions plugin: this prints %s through the shell, which loads none of the path-scoped rules or nested CLAUDE.md files the Read tool loads for it, so the code would be read without its conventions. Open it with the Read tool instead (offset and limit for a range). For another branch, add a git worktree at that ref and Read the file there; a pinned commit (git show <sha>:<path>) stays allowed. Searching (grep, git grep, git log) and diffs stay allowed."}}\n' "$file"
}

main() {
  local input command file
  input="$(cat)"
  command="$(extract_field "$input")"
  if [ -z "$command" ]; then
    exit 0
  fi
  if file="$(first_shell_read "$command")"; then
    print_deny "$file"
  fi
  exit 0
}

main
