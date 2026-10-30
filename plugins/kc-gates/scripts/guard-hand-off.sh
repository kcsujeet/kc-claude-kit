#!/usr/bin/env bash
# PreToolUse guard for Bash: blocks handing a PR to review before
# kc-ready-for-review has passed its head commit.
#
# A hand-off is `gh pr ready` (not --undo), `gh pr create` without
# -d/--draft, `gh pr edit` with --add-reviewer, or a `gh api` write to a PR's
# requested_reviewers. The guard finds the PR's head commit (gh pr view for
# an existing PR; for a new one the --head branch on GitHub, or HEAD of the
# directory the command runs in, following any `cd` before it) and passes
# only when ready-receipt.sh has a receipt for it. A command containing the
# literal KC_READY_SKIP=1 passes: the skill adds it only when the user has
# said to skip the pass for that PR.
#
# Commands are read word by word, so a PR is named the way gh documents it,
# right after the subcommand (`gh pr edit 12 --add-reviewer ana`); with no
# number there, gh's own default, the current branch's PR, is checked.
#
# Output: the PreToolUse deny JSON on a blocked hand-off, nothing otherwise.
# Always exits 0. Hook schema: https://code.claude.com/docs/en/hooks

set -u

scripts_dir=$(dirname "$0")
# shellcheck source=lib/hook-input.sh
. "$scripts_dir/lib/hook-input.sh"

readonly SKIP_TOKEN='KC_READY_SKIP=1'
readonly WRITE_METHOD='(-X|--method)[[:space:]=]*(POST|PATCH|PUT|DELETE)'
readonly FIELD_FLAG='(^|[[:space:]])(-f|-F|--field|--raw-field|--input)([[:space:]=]|[^[:space:]-]|$)'
readonly REVIEWERS_ENDPOINT='repos/([^/[:space:]]+/[^/[:space:]]+)/pulls/([0-9]+)/requested_reviewers'

# The words after `gh` in a segment, quotes dropped; empty when it runs no gh.
gh_words() {
  printf '%s' "$1" \
    | tr -d "\"'" \
    | sed -nE 's/^(.*[^[:alnum:]_.-])?gh[[:space:]]+(.*)$/\2/p'
}

has_word() {
  local needle=$1 word
  shift
  for word in "$@"; do
    case "$word" in
      "$needle" | "$needle"=*) return 0 ;;
    esac
  done
  return 1
}

# Prints the value of the first of the given flags (`--flag value` or
# `--flag=value`) in the remaining words.
flag_value() {
  local short=$1 long=$2 word take=false
  shift 2
  for word in "$@"; do
    if $take; then
      printf '%s' "$word"
      return
    fi
    case "$word" in
      "$long"=*) printf '%s' "${word#*=}"; return ;;
      "$short" | "$long") take=true ;;
    esac
  done
}

is_hand_off() {
  local rest=$1 words
  read -ra words <<< "$rest"
  [ "${#words[@]}" -ge 2 ] || return 1
  case "${words[0]} ${words[1]}" in
    "pr ready") ! has_word --undo "${words[@]}" ;;
    "pr create") ! has_word -d "${words[@]}" && ! has_word --draft "${words[@]}" ;;
    "pr edit") has_word --add-reviewer "${words[@]}" ;;
    api*)
      printf '%s' "$rest" | grep -Eq "$REVIEWERS_ENDPOINT" || return 1
      printf '%s' "$rest" | grep -Eiq "$WRITE_METHOD" || printf '%s' "$rest" | grep -Eq "$FIELD_FLAG"
      ;;
    *) return 1 ;;
  esac
}

# Prints the head commit of the PR the hand-off names, or nothing.
resolve_head() {
  local rest=$1 dir=$2 words repo selector head repo_args=()
  read -ra words <<< "$rest"
  repo=$(flag_value -R --repo "${words[@]}")
  if [ -n "$repo" ]; then repo_args=(--repo "$repo"); fi
  case "${words[0]} ${words[1]}" in
    "pr ready" | "pr edit")
      selector=${words[2]:-}
      case "$selector" in -*) selector="" ;; esac
      (cd "$dir" && gh pr view ${selector:+"$selector"} ${repo_args[@]+"${repo_args[@]}"} --json headRefOid --jq .headRefOid) 2>/dev/null
      ;;
    "pr create")
      head=$(flag_value -H --head "${words[@]}")
      if [ -z "$head" ]; then
        git -C "$dir" rev-parse HEAD 2>/dev/null
      elif [ -n "$repo" ]; then
        (cd "$dir" && gh api "repos/$repo/commits/$head" --jq .sha) 2>/dev/null
      else
        (cd "$dir" && gh api "repos/{owner}/{repo}/commits/$head" --jq .sha) 2>/dev/null
      fi
      ;;
    api*)
      repo=$(printf '%s' "$rest" | sed -nE "s#.*$REVIEWERS_ENDPOINT.*#\\1#p")
      selector=$(printf '%s' "$rest" | sed -nE "s#.*$REVIEWERS_ENDPOINT.*#\\2#p")
      (cd "$dir" && gh pr view "$selector" --repo "$repo" --json headRefOid --jq .headRefOid) 2>/dev/null
      ;;
  esac
}

print_deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked by the kc-gates plugin: %s Run /kc-gates:kc-ready-for-review first: one pass of review and QA, at most two rounds, ending in a receipt for the commit the PR will show. Only when the user has said in their latest message to skip that pass for this PR, prefix the command with KC_READY_SKIP=1; never add it on your own."}}\n' "$1"
}

main() {
  local input command dir segment rest target head
  input="$(cat)"
  command="$(extract_field "$input" command)"
  if [ -z "$command" ]; then
    exit 0
  fi
  case "$command" in
    *"$SKIP_TOKEN"*) exit 0 ;;
  esac
  dir="$(extract_field "$input" cwd)"
  dir=${dir:-$PWD}
  while IFS= read -r segment; do
    target=$(printf '%s' "$segment" | sed -nE 's/^[[:space:]]*cd[[:space:]]+([^[:space:]]+)[[:space:]]*$/\1/p' | tr -d "\"'")
    if [ -n "$target" ]; then
      case "$target" in
        "~"*) target="$HOME${target#"~"}" ;;
        /*) ;;
        *) target="$dir/$target" ;;
      esac
      dir=$target
      continue
    fi
    rest=$(gh_words "$segment")
    if [ -z "$rest" ] || ! is_hand_off "$rest"; then
      continue
    fi
    head=$(resolve_head "$rest" "$dir")
    if [ -z "$head" ]; then
      print_deny "this command hands a PR to review, but the guard could not find the PR's head commit (run it from the repo, or name the PR number and --repo), so it cannot check for a review receipt."
      exit 0
    fi
    if ! bash "$scripts_dir/ready-receipt.sh" check "$head" >/dev/null 2>&1; then
      print_deny "this command hands a PR to review, and its head commit $head has no kc-ready-for-review receipt."
      exit 0
    fi
  done <<EOF
$(split_segments "$command")
EOF
  exit 0
}

main
