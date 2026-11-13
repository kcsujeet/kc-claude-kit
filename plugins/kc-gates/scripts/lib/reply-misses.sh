# shellcheck shell=bash
# The reply rules' shared parts, sourced by the Stop hooks that note a reply's misses
# (check-reply-length.sh, check-reply-sources.sh) and the turn-start hook that names them
# (remind-reply-rules.sh). Misses are kept per session in the plugin's data folder.

# shellcheck disable=SC2034  # read by the scripts that source this file
readonly REPLY_MAX_WORDS=180

# Prints session <id>'s misses file; fails, printing nothing, without a data folder or an id.
reply_misses_file() {
  [ -n "${CLAUDE_PLUGIN_DATA:-}" ] && [ -n "${1:-}" ] || return 1
  printf '%s\n' "$CLAUDE_PLUGIN_DATA/reply-misses/$1"
}

# Appends each argument after <id> as one line of session <id>'s misses file.
append_reply_misses() {
  local misses_file
  misses_file=$(reply_misses_file "$1") || return 0
  shift
  mkdir -p "$(dirname "$misses_file")" && printf '%s\n' "$@" >> "$misses_file"
}
