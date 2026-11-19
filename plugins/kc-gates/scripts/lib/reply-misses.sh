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

# True when the prompt asks to fix something reported: a fix or debug verb, or a word that reports a
# problem ("the export is broken", "checkout crashes"); or a noun for one (an error, QA or review
# feedback) with a verb that acts on it or reports it ("address the QA feedback", "it throws an
# error"). The noun alone is a feature request ("add error handling", "add a QA checklist").
asks_fix() {
  local prompt_text
  prompt_text=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  printf '%s' "$prompt_text" | grep -Eq "(^|[^[:alnum:]])(fix(es|ed|ing)?|debug(ging)?|bugs?|broken|regress(ed|ion)?|crash(es|ed)?|fail(s|ed|ing)|not working|doesn.t work)([^[:alnum:]]|$)" && return 0
  printf '%s' "$prompt_text" | grep -Eq "(^|[^[:alnum:]])(errors?|failures?|qa|feedbacks?|findings?|review comments?)([^[:alnum:]]|$)" \
    && printf '%s' "$prompt_text" | grep -Eq "(^|[^[:alnum:]])(address|handle|resolve|respond to|look at|go through|work through|act on|throws?|threw|returns?|returned|gets?|got|seeing|hits?)([^[:alnum:]]|$)"
}

# A cause word and a fix word anywhere in the reply, in any order.
proposes_cause_and_fix() {
  printf '%s' "$1" | grep -Eiq "(^|[^[:alnum:]])cause[sd]?([^[:alnum:]]|$)" \
    && printf '%s' "$1" | grep -Eiq "(^|[^[:alnum:]])fix(es|ed)?([^[:alnum:]]|$)"
}

# True when a reply names how the problem was reproduced: a "Reproduced:" or "Not reproduced:"
# line, any Markdown emphasis around the label allowed.
names_reproduction() {
  printf '%s\n' "$1" | grep -Eiq "(^|[^[:alnum:]])(not )?reproduced[*_]*:"
}

# True when the prompt is only a question: it ends with `?` and asks for no change (no imperative
# such as fix, build, add or "do it" anywhere in it). "Can you fix this?" is a request, "why does
# this fail?" is a question. A "do/does/did" before a subject is a question word, not an order.
is_only_question() {
  local text
  text=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  case "$text" in *'?') ;; *) return 1 ;; esac
  text=$(printf '%s' "$text" | sed -E 's/(^|[^[:alnum:]])(do|does|did)[[:space:]]+(you|we|i|they|it|he|she)([^[:alnum:]]|$)/ /g')
  ! printf '%s' "$text" | grep -Eq "(^|[^[:alnum:]])(fix|build|change|add|remove|make|update|write|implement|create|delete|run|try|edit|rename|revert|apply|commit|push|do (it|this|that))([^[:alnum:]]|$)"
}
