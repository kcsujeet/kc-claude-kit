#!/usr/bin/env bash
# PostToolUse hook for Bash: after a command that approves a pull request, reminds Claude that the
# review's look-back is due (the working agreement's "Order of work on a task", step 6): its own
# misses across the review's rounds become lessons, without being asked.
#
# An approval is `gh pr review --approve` (or `-a`), or a `gh api` write to a PR's reviews whose
# event is APPROVE: given as a field (`-f event=APPROVE`), inline, or in the `--input` file.
#
# Output: PostToolUse JSON with the reminder as additionalContext after an approval, nothing
# otherwise. Always exits 0. Hook schema: https://code.claude.com/docs/en/hooks
#
# KC_GUARD_NO_JQ=1 forces the sed fallback (used by the tests).

set -u

# shellcheck source=lib/hook-input.sh
. "$(dirname "$0")/lib/hook-input.sh"

readonly GH_WORD='(^|[^[:alnum:]_.-])gh[[:space:]]+'
readonly REVIEWS_ENDPOINT='pulls/[0-9]+/reviews([^/[:alnum:]]|$)'

# True when the segment approves a PR. A relative --input path is read from <cwd>.
is_approval_segment() {
  local segment=$1 cwd=$2 input_file
  if printf '%s' "$segment" | grep -Eq "${GH_WORD}pr[[:space:]]+review([[:space:]].*)?[[:space:]](--approve|-a)([[:space:]]|$)"; then
    return 0
  fi
  printf '%s' "$segment" | grep -Eq "${GH_WORD}api([[:space:]]|$)" || return 1
  printf '%s' "$segment" | grep -Eq "$REVIEWS_ENDPOINT" || return 1
  if printf '%s' "$segment" | grep -Eq 'event["'"'"']?[[:space:]]*[=:][[:space:]]*["'"'"']?APPROVE'; then
    return 0
  fi
  input_file=$(printf '%s' "$segment" | sed -nE 's/.*--input[[:space:]=]+["'"'"']?([^[:space:]"'"'"']+).*/\1/p')
  [ -n "$input_file" ] || return 1
  case "$input_file" in /*) ;; *) input_file="$cwd/$input_file" ;; esac
  [ -r "$input_file" ] && grep -Eq '"event"[[:space:]]*:[[:space:]]*"APPROVE"' "$input_file"
}

main() {
  local input command cwd segment
  input="$(cat)"
  command="$(extract_field "$input" command)"
  [ -n "$command" ] || exit 0
  cwd="$(extract_field "$input" cwd)"
  [ -n "$cwd" ] || cwd=$PWD
  while IFS= read -r segment; do
    if is_approval_segment "$segment" "$cwd"; then
      cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"kc-gates: this approved a pull request, so the review's look-back is due once it closes (working agreement, Order of work on a task, step 6). Before calling the review done, list your own misses across its rounds (a finding the author fixed only where it named, a suggestion that caused a later finding, a gap a later round found that an earlier one could have) and write them as lessons, without being asked."}}
EOF
      exit 0
    fi
  done <<EOF
$(split_segments "$command")
EOF
  exit 0
}

main
