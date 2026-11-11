#!/usr/bin/env bash
# PostToolUse hook for Bash: after a command that approves or merges a pull request, reminds Claude
# that the look-back is due (the working agreement's "Order of work on a task", step 6). After an
# approval: its own misses across the review's rounds become lessons. After a merge: the task is
# handed off, so every piece of feedback it got is listed and given a verdict. Both without being
# asked. The step is placed "once the task is handed off", and nothing else marks that moment for
# the agent's own work.
#
# An approval is `gh pr review --approve` (or `-a`), or a `gh api` write to a PR's reviews whose
# event is APPROVE: given as a field (`-f event=APPROVE`), inline, or in the `--input` file.
#
# A merge is `gh pr merge` (but not `--disable-auto`, which only cancels a queued one), or a
# `gh api` PUT to a PR's `merge`. With `--auto` the merge may only be queued, and the reminder
# says so.
#
# It splits the command as the guards do, quotes or not, so a review body holding `;` or
# `--approve` can cost a reminder or add one. A reminder is harmless either way, and a shell
# parser here would be more code than the reminder is worth. Heredoc bodies are dropped first:
# they are nearly always text being written (a fixture, a changelog line), and a command that
# only writes the words `gh pr merge` merged nothing. The guards keep reading them, since a guard
# that misses a command lets it through.
#
# Output: PostToolUse JSON with the reminder as additionalContext after an approval, nothing
# otherwise. Always exits 0. Hook schema: https://code.claude.com/docs/en/hooks
#
# KC_GUARD_NO_JQ=1 forces the sed fallback (used by the tests).

set -u

# shellcheck source=lib/hook-input.sh
. "$(dirname "$0")/lib/hook-input.sh"

# A PR's reviews, or one pending review's events (how a drafted review is submitted).
readonly PR_REVIEWS_ENDPOINT='pulls/[0-9]+/reviews(/[0-9]+/events)?([^/[:alnum:]]|$)'

# True when the segment approves a PR. A relative --input path is read from <cwd>, a `~/` one
# from $HOME.
is_approval_segment() {
  local segment=$1 cwd=$2 input_file
  if printf '%s' "$segment" | grep -Eq "${GH_COMMAND_START}pr[[:space:]]+review([[:space:]].*)?[[:space:]]["'"'"']?(--approve|-a)["'"'"']?([[:space:]]|$)"; then
    return 0
  fi
  printf '%s' "$segment" | grep -Eq "${GH_COMMAND_START}api([[:space:]]|$)" || return 1
  printf '%s' "$segment" | grep -Eq "$PR_REVIEWS_ENDPOINT" || return 1
  if printf '%s' "$segment" | grep -Eq 'event["'"'"']?[[:space:]]*[=:][[:space:]]*["'"'"']?APPROVE'; then
    return 0
  fi
  input_file=$(printf '%s' "$segment" | sed -nE 's/.*--input[[:space:]=]+["'"'"']?([^[:space:]"'"'"']+).*/\1/p')
  [ -n "$input_file" ] || return 1
  # shellcheck disable=SC2088  # matches the literal `~/` the command held, not a path
  case "$input_file" in /*) ;; "~/"*) input_file="$HOME/${input_file#"~/"}" ;; *) input_file="$cwd/$input_file" ;; esac
  [ -r "$input_file" ] && grep -Eq '"event"[[:space:]]*:[[:space:]]*"APPROVE"' "$input_file"
}

# A PR's merge endpoint; a GET on it only asks whether the PR is merged.
readonly PR_MERGE_ENDPOINT='pulls/[0-9]+/merge([^/[:alnum:]]|$)'

# True when the segment merges a PR.
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

# Prints <command> without its heredoc bodies; the line that opens each heredoc stays. A here-string
# (`<<<`) is not a heredoc.
drop_heredoc_bodies() {
  printf '%s\n' "$1" | awk '
    terminator != "" {
      line = $0
      # Without jq the tabs in the payload arrive still escaped, as a backslash and a t.
      if (strips_tabs) sub(/^(\t|\\t)+/, "", line)
      if (line == terminator) terminator = ""
      next
    }
    {
      print
      if (match($0, /(^|[^<])<<-?[[:space:]]*["\047\\]?[A-Za-z_][A-Za-z0-9_]*/)) {
        opener = substr($0, RSTART, RLENGTH)
        strips_tabs = (opener ~ /<<-/)
        sub(/^.*<<-?[[:space:]]*["\047\\]?/, "", opener)
        terminator = opener
      }
    }'
}

main() {
  local input command cwd segment
  input="$(cat)"
  command="$(extract_field "$input" command)"
  cwd="$(extract_field "$input" cwd)"
  [ -n "$cwd" ] || cwd=$PWD
  while IFS= read -r segment; do
    if is_approval_segment "$segment" "$cwd"; then
      cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"kc-gates: this approved a pull request, so the review's look-back is due once it closes (working agreement, Order of work on a task, step 6). Before calling the review done, list your own misses across its rounds (a finding the author fixed only where it named, a suggestion that caused a later finding, a gap a later round found that an earlier one could have) and write them as lessons, without being asked."}}
EOF
      exit 0
    fi
    if is_merge_segment "$segment"; then
      local merge_lead="this merged a pull request, so its task is handed off and the look-back is due"
      # With --auto the pull request merges only once its requirements are met (`gh pr merge --help`).
      if printf '%s' "$segment" | grep -Eq -- '--auto([[:space:]]|$)'; then
        merge_lead="this set a pull request to merge once its requirements are met (--auto); once it has merged, its task is handed off and the look-back is due"
      fi
      cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"kc-gates: $merge_lead (working agreement, Order of work on a task, step 6). Before saying what comes next, list every piece of feedback the session got (feedback-ledger.sh list over its transcript), give each one a verdict, and write the lessons, without being asked."}}
EOF
      exit 0
    fi
  done <<EOF
$(split_segments "$(drop_heredoc_bodies "$command")")
EOF
  exit 0
}

main
