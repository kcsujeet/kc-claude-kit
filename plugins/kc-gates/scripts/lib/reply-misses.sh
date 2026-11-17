# shellcheck shell=bash
# The reply rules' shared parts, sourced by the Stop hooks that note a reply's misses
# (check-reply-length.sh, check-reply-sources.sh), the turn-start hook that names them
# (remind-reply-rules.sh). Misses are kept per session in the plugin's data folder. is_question is
# also read by guard-late-answer.sh.

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

# True when the prompt is a question.
is_question() {
  local text
  text=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  case "$text" in *'?') return 0 ;; esac
  printf '%s' "$text" | grep -Eq "^(when|why|what|how|where|who|which|is|are|can|should|will)([^[:alnum:]]|$)|^(do|does|did)[[:space:]]+(you|we|i|they|it|he|she)([^[:alnum:]]|$)"
}

# True when the prompt asks where work stands or what is left: "are we done", "what's next",
# "what's left", "status", "where are we", "is it merged/deployed/tested/approved/released".
asks_status() {
  local text
  text=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  case "$text" in status|status[?.!]*) return 0 ;; esac
  printf '%s' "$text" | grep -Eq "(^|[^[:alnum:]])(are we (done|finished)|what.s (next|left|remaining)|what (is|else is) (next|left)|what now|where are we|(current|any|your|the latest) status|status (of|on|update|check)|is (it|that|this|the (pr|ticket)) (merged|deployed|tested|approved|released|live|done))([^[:alnum:]]|$)"
}
