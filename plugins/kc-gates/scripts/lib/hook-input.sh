# shellcheck shell=bash
# Reads a Bash hook's payload (PreToolUse or PostToolUse) for the kit's hooks. Sourced, never
# executed.
#
# KC_GUARD_NO_JQ=1 forces the sed fallback (used by the tests).

# Where a `gh` command starts in a segment: `gh` as a whole word, then its subcommand.
readonly GH_COMMAND_START='(^|[^[:alnum:]_.-])gh[[:space:]]+'

# A PR's merge endpoint; a GET on it only asks whether the PR is merged.
readonly PR_MERGE_ENDPOINT='pulls/[0-9]+/merge([^/[:alnum:]]|$)'

# True when the segment merges a PR: `gh pr merge` (not `--disable-auto`, which only cancels a
# queued one), or a `gh api` PUT to a PR's merge endpoint. Read by remind-look-back.sh and
# update-after-merge.sh.
is_merge_segment() {
  local segment=$1
  if printf '%s' "$segment" | grep -Eq "${GH_COMMAND_START}pr[[:space:]]+merge([[:space:]]|$)"; then
    printf '%s' "$segment" | grep -Eq -- '--disable-auto([[:space:]]|$)' && return 1
    return 0
  fi
  printf '%s' "$segment" | grep -Eq "${GH_COMMAND_START}api([[:space:]]|$)" || return 1
  printf '%s' "$segment" | grep -Eq "$PR_MERGE_ENDPOINT" || return 1
  printf '%s' "$segment" | grep -Eq -- "(-X|--method)[[:space:]=]*[\"']?PUT"
}

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
  # JSON strings hold no raw newlines, so joining lines is safe. The capture
  # keeps escapes such as \" and \n; the callers tolerate them.
  printf '%s' "$input" \
    | tr '\n' ' ' \
    | sed -nE 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' \
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
