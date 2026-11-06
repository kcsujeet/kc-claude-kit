# shellcheck shell=bash
# Reads a Bash hook's payload (PreToolUse or PostToolUse) for the kit's hooks. Sourced, never
# executed.
#
# KC_GUARD_NO_JQ=1 forces the sed fallback (used by the tests).

# Where a `gh` command starts in a segment: `gh` as a whole word, then its subcommand.
# shellcheck disable=SC2034  # read by guard-github-post.sh and remind-look-back.sh
readonly GH_COMMAND_START='(^|[^[:alnum:]_.-])gh[[:space:]]+'

# Prints a top-level or tool_input string field of the payload: `command`
# comes from tool_input, `cwd` from the top level.
extract_field() {
  local input="$1" field="$2" path
  case "$field" in
    command) path='.tool_input.command' ;;
    *) path=".$field" ;;
  esac
  if [ "${KC_GUARD_NO_JQ:-0}" != 1 ] && command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r "$path // empty" 2>/dev/null
    return
  fi
  # JSON strings hold no raw newlines, so joining lines is safe. The capture is
  # the field's JSON text, escapes and all, which perl's core JSON module decodes
  # (`\\` and `\"` included, so a quoted body's escapes survive).
  printf '%s' "$input" \
    | tr '\n' ' ' \
    | sed -nE 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' \
    | perl -MJSON::PP -0777 -ne 'chomp; my $value = eval { JSON::PP->new->allow_nonref->decode(qq("$_")) }; print $value if defined $value'
}

# One shell segment per line: split on newlines, ;, &&, || and |, outside quotes. Inside a quoted
# string (a commit message, a review body, `\"` escapes included) those characters are blanked
# first, so "LGTM; ship it" stays in its command's segment.
split_segments() {
  printf '%s\n' "$1" | perl -0777 -pe 's{("(?:[^"\\]|\\.)*"|\x27[^\x27]*\x27)}{ (my $quoted = $1) =~ s/[;|&\n]/ /g; $quoted }ge' | sed -e 's/&&/\
/g' -e 's/||/\
/g' -e 's/;/\
/g' -e 's/|/\
/g'
}
