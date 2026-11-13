#!/usr/bin/env bash
# PreToolUse guard for Bash. Path-scoped rules and nested CLAUDE.md files load only when the Read
# tool opens a file; a source file printed through the shell loads none, so the code is read
# without its conventions. Refuses cat, head, tail, less, more, bat, nl and sed (not sed -i) on a
# source file, and `git show <rev>:<path>` on one. A pinned commit (a hex id or a shell variable)
# stays allowed, since reviews read files at a head SHA. Quoted text and heredoc bodies are not
# commands. Known gaps: `bash -c "..."`, `$(...)`, `awk`. No escape-hatch token: an agent could add
# it itself. Output: the deny JSON or nothing; always exits 0. Hook schema:
# https://code.claude.com/docs/en/hooks. KC_GUARD_NO_JQ=1 forces the sed fallback (for the tests).

set -u

readonly SOURCE_EXTENSIONS='(ts|tsx|js|jsx|mjs|cjs|rb|py|swift|go|java|kt|php|cs|rs)'
readonly READ_COMMANDS=' cat head tail less more bat nl sed '
# A pinned commit: a hex id with optional ancestry suffixes (1234567~1, abc1234^2).
readonly PINNED_COMMIT='^[0-9a-f]{7,40}([~^][0-9]*)*$'

# Prints the command of the payload (jq, or a sed fallback).
get_bash_command() {
  local input="$1" has_jq=1 is_jq_disabled=0
  command -v jq >/dev/null 2>&1 || has_jq=0
  [ "${KC_GUARD_NO_JQ:-0}" = 1 ] && is_jq_disabled=1
  if [ "$has_jq" = 1 ] && [ "$is_jq_disabled" = 0 ]; then
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

# Drops heredoc bodies (the line holding `<<WORD` stays, the lines up to WORD go), then replaces a
# quoted span that holds whitespace or ; | & with __quoted__, so text that only mentions a command
# is not split into segments.
drop_quoted_text() {
  printf '%s\n' "$1" | awk '
    { lines[++line_count] = $0 }
    END {
      sq = "\047"
      line_index = 1
      while (line_index <= line_count) {
        line = lines[line_index++]
        kept[++kept_count] = line
        start = match(line, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*/)
        if (start > 0 && !(start > 1 && substr(line, start - 1, 1) == "<")) {
          word = substr(line, RSTART, RLENGTH)
          is_dash = (substr(word, 3, 1) == "-")
          sub(/^<<-?[ \t]*["\047]?/, "", word)
          while (line_index <= line_count) {
            body = lines[line_index++]
            if (is_dash) sub(/^\t+/, "", body)
            if (body == word) break
          }
        }
      }
      text = kept[1]
      for (k = 2; k <= kept_count; k++) text = text "\n" kept[k]
      out = ""
      len = length(text)
      i = 1
      while (i <= len) {
        c = substr(text, i, 1)
        if (c != "\"" && c != sq) { out = out c; i++; continue }
        j = i + 1
        closed = 0
        while (j <= len) {
          d = substr(text, j, 1)
          if (c == "\"" && d == "\\") { j += 2; continue }
          if (d == c) { closed = 1; break }
          j++
        }
        if (!closed) { out = out substr(text, i); break }
        span = substr(text, i + 1, j - i - 1)
        if (span ~ /[ \t\n;|&]/) out = out "__quoted__"
        else out = out substr(text, i, j - i + 1)
        i = j + 1
      }
      print out
    }'
}

# One shell segment per line. Splits on newlines, ;, && and |.
split_segments() {
  printf '%s\n' "$1" | sed -e 's/&&/\
/g' -e 's/;/\
/g' -e 's/|/\
/g'
}

# Prints the first source file the segment prints through the shell; returns 1 when it prints none.
get_shell_read_file() {
  local segment="$1" tokens=() args=() subcommand_args=() token prev='' command_name subcommand
  local skip_next=0 in_place=0 is_env=0 path rev
  read -ra tokens <<< "$segment"
  local count=${#tokens[@]} index=0

  # Leading VAR=value assignments, shell keywords and wrappers (env, sudo, time, command, nohup,
  # exec) are not the command; neither is a ( attached to the first word.
  while [ "$index" -lt "$count" ]; do
    token="${tokens[$index]}"
    case "$token" in
      [A-Za-z_]*=* | do | then | else | '{' | '(' | '!' | sudo | time | command | nohup | exec) ;;
      env) is_env=1 ;;
      -*) [ "$is_env" = 1 ] || break ;;
      *) break ;;
    esac
    index=$((index + 1))
  done
  [ "$index" -lt "$count" ] || return 1

  command_name="${tokens[$index]}"
  command_name="${command_name#(}"
  command_name="${command_name//[\'\"]/}"
  command_name="${command_name##*/}"
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
    args+=("${token%)}")
  done

  if [ "$command_name" = git ]; then
    subcommand=''
    for token in "${args[@]+"${args[@]}"}"; do
      if [ -z "$subcommand" ]; then
        if [ "$skip_next" = 1 ]; then skip_next=0; continue; fi
        case "$token" in
          -C | -c) skip_next=1 ;;
          -*) ;;
          *) subcommand="$token" ;;
        esac
      else
        subcommand_args+=("$token")
      fi
    done
    [ "$subcommand" = show ] || return 1
    for token in "${subcommand_args[@]+"${subcommand_args[@]}"}"; do
      if [[ "$token" =~ ^([^:[:space:]]*):(.*\.${SOURCE_EXTENSIONS})$ ]]; then
        rev="${BASH_REMATCH[1]}"
        path="${BASH_REMATCH[2]}"
        [[ "$rev" =~ $PINNED_COMMIT || "$rev" == '$'* ]] && continue
        printf '%s' "$path"
        return 0
      fi
    done
    return 1
  fi

  case "$READ_COMMANDS" in
    *" $command_name "*) ;;
    *) return 1 ;;
  esac
  if [ "$command_name" = sed ]; then
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

get_first_shell_read_file() {
  local segment file
  while IFS= read -r segment; do
    if file="$(get_shell_read_file "$segment")"; then
      printf '%s' "$file"
      return 0
    fi
  done <<EOF
$(split_segments "$(drop_quoted_text "$1")")
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
  command="$(get_bash_command "$input")"
  if [ -z "$command" ]; then
    exit 0
  fi
  if file="$(get_first_shell_read_file "$command")"; then
    print_deny "$file"
  fi
  exit 0
}

main
