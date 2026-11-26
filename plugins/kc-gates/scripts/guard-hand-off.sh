#!/usr/bin/env bash
# PreToolUse guard for Bash: blocks publishing a branch, or handing a PR to
# review, before kc-ready-for-review has passed its head commit. The pass runs
# on the committed local branch, before its first push and before the PR exists.
#
# Blocked until the commit has a receipt:
#   - the first push of a branch: a `git push` whose target branch is not on
#     the remote yet (`git ls-remote --exit-code --heads`), for the commit
#     being pushed. Read forms: `git push`, `git push -u origin <branch>`,
#     `git push origin <branch>`, `git push --set-upstream origin HEAD`,
#     `git push origin HEAD:<branch>`; any other form checks HEAD and the
#     current branch. Never blocked: a push to a branch the remote has (fix
#     rounds, rebases), to its default branch, `--delete`, tags, `--all`,
#     `--mirror`, `--dry-run`, a push outside a git repo (no commit to check), or one where
#     ls-remote fails (network: allowed, with a note on stderr).
#   - `gh pr create`, draft or not: the pass receipt precedes the PR.
#   - a hand-off: `gh pr ready` (not --undo), `gh pr edit` with
#     --add-reviewer, or a `gh api` write to a PR's requested_reviewers.
# A boolean flag counts as gh reads it: bare or set true, the last one
# winning, so `--draft=false` is not a draft. The guard finds the commit
# (gh pr view for an existing PR; for a new one the --head branch on GitHub,
# or HEAD of the directory the command runs in, following any `cd` before it)
# and passes only when ready-receipt.sh has a pass or --after receipt for it
# (one for the checklist alone doesn't count). A command containing the
# literal KC_READY_SKIP=1 passes: the skill adds it only when the user has
# said to skip the pass for that PR.
#
# The change from the default branch to that commit is classed first
# (change-class.sh): prose_small (a few prose lines, nothing else) needs no
# pass receipt, only the checklist below; code_small (small, and no risk: line from
# pass-size.sh, so no sensitive or public path, deletion or migration) needs none either;
# full, and any change with a risk line, is checked as above.
#
# When the repo has .claude/hand-off-checklist.md at that commit, the commit
# also needs checklist verdicts (ready-receipt.sh write <sha> --verdicts
# <graded checklist>) with every box PASS, or N/A with a reason; a missing or
# FAIL box blocks, named one line each. A commit this clone doesn't have, with
# no verdicts recorded, can't be read and is not blocked on its checklist.
#
# `drafts: true` in a hand-off checklist's front matter is no longer needed
# and is ignored: a pass receipt always precedes the PR.
#
# Commands are read word by word, so a PR is named the way gh documents it,
# right after the subcommand (`gh pr edit 12 --add-reviewer ana`); with no
# number there, gh's own default, the current branch's PR, is checked.
#
# Before any such push (a branch the remote has or doesn't), the repo's lint runs on the files the
# push adds (lint-changed-files.sh: `.claude/lint-command`, else `npx biome check` when biome.json
# is at the repo root, else nothing) and a failure blocks the push with the lint output.
#
# Output: the PreToolUse deny JSON on a blocked command, nothing otherwise.
# Always exits 0. Hook schema: https://code.claude.com/docs/en/hooks

set -u

scripts_dir=$(dirname "$0")
# shellcheck source=lib/hook-input.sh
. "$scripts_dir/lib/hook-input.sh"

readonly SKIP_TOKEN='KC_READY_SKIP=1'
readonly WRITE_METHOD='(-X|--method)[[:space:]=]*(POST|PATCH|PUT|DELETE)'
readonly FIELD_FLAG='(^|[[:space:]])(-f|-F|--field|--raw-field|--input)([[:space:]=]|[^[:space:]-]|$)'
readonly REVIEWERS_ENDPOINT='repos/([^/[:space:]]+/[^/[:space:]]+)/pulls/([0-9]+)/requested_reviewers'

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

# Succeeds when the last of the given boolean flags in the remaining words
# turns it on: bare, or `=` a value gh's flag parser reads as true.
is_flag_on() {
  local short=$1 long=$2 word on=false
  shift 2
  for word in "$@"; do
    case "$word" in
      "$short" | "$long") on=true ;;
      "$short"=* | "$long"=*)
        case "${word#*=}" in
          1 | t | T | true | TRUE | True) on=true ;;
          *) on=false ;;
        esac
        ;;
    esac
  done
  $on
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
    "pr ready") ! is_flag_on --undo --undo "${words[@]}" ;;
    "pr create") return 0 ;;
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

# $1 is the reason.
print_deny_reason() {
  local skip_hint=" Only when the user has said in their latest message to skip it for this PR, prefix the command with KC_READY_SKIP=1; never add it on your own."
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Blocked by the kc-gates plugin: %s%s"}}\n' "$1" "$skip_hint"
}

print_deny() {
  print_deny_reason "$1 Run /kc-gates:kc-ready-for-review on the committed branch before its first push: one pass of review and QA, ending in a receipt for the commit the PR will show."
}

# Denies when the commit's hand-off checklist has unmet boxes (see the header).
# $1 is the commit, $2 the directory it is read in. Prints the deny JSON and
# returns 1 when it blocks.
check_checklist() {
  local sha=$1 dir=$2 unmet root lines
  root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || root=""
  if unmet=$(bash "$scripts_dir/ready-receipt.sh" check "$sha" --checklist ${root:+--repo "$root"} 2>/dev/null); then
    return 0
  fi
  lines=$(printf '%s' "$unmet" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk '{ printf "%s%s", (NR > 1 ? "\\n" : ""), "- " $0 }')
  print_deny_reason "commit $sha has a review receipt but its hand-off checklist is not met:\\n$lines\\nGrade every box PASS, or N/A: reason (copy the box lines, replacing [ ] with [PASS], [FAIL] or [N/A: reason]), fix a FAIL, then record it: bash $scripts_dir/ready-receipt.sh write $sha --verdicts <graded-checklist-file>."
  return 1
}

# Denies a push whose changed files fail the repo's lint (lint-changed-files.sh). The push base is
# the remote's copy of the branch, else the merge-base with the remote's default branch; with
# neither known locally nothing is linted. Prints the deny JSON and returns 1 when it blocks.
check_lint() {
  local dir=$1 remote=$2 dst=$3 default=$4 sha=$5 base="" lint_output escaped
  for ref in "refs/remotes/$remote/$dst" "refs/remotes/$remote/$default"; do
    base=$(git -C "$dir" merge-base "$ref" "$sha" 2>/dev/null) && break
    base=""
  done
  [ -n "$base" ] || return 0
  lint_output=$(bash "$scripts_dir/lint-changed-files.sh" "$dir" "$base" "$sha") && return 0
  escaped=$(printf '%s\n' "$lint_output" | head -n 40 | LC_ALL=C tr -d '\000-\010\013-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/ /g' | awk '{ printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }')
  print_deny_reason "the lint fails on the files this push adds (the repo's .claude/lint-command, or biome check). Fix it before pushing:\\n$escaped"
  return 1
}

# Denies a `git push` that publishes a branch the remote doesn't have yet, from
# a commit with no pass or --after receipt. $1 is the directory, the rest the
# words after `git`. Prints the deny JSON and returns 1 when it blocks.
check_push() {
  local dir=$1 word skip=false remote="" refs=() positional=() spec src dst sha cur default status change_class
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -C)
        case "${2:-}" in
          "") ;;
          /*) dir=$2 ;;
          *) dir="$dir/$2" ;;
        esac
        shift
        ;;
      -c) shift ;;
      -*) ;;
      *) break ;;
    esac
    shift
  done
  [ "${1:-}" = push ] || return 0
  shift
  for word in "$@"; do
    if $skip; then skip=false; continue; fi
    case "$word" in
      -d | --delete | --tags | --mirror | --all | -n | --dry-run) return 0 ;;
      -o | --push-option | --receive-pack | --exec | --repo) skip=true ;;
      -*) ;;
      *) positional+=("$word") ;;
    esac
  done
  cur=$(git -C "$dir" symbolic-ref --short -q HEAD 2>/dev/null) || cur=""
  remote=${positional[0]:-}
  if [ -z "$remote" ]; then
    remote=$(git -C "$dir" config "branch.$cur.pushRemote" 2>/dev/null) \
      || remote=$(git -C "$dir" config "branch.$cur.remote" 2>/dev/null) || remote=origin
  fi
  refs=("${positional[@]:1}")
  if [ "${#refs[@]}" -eq 0 ]; then
    [ -n "$cur" ] || return 0
    refs=("$cur")
  fi
  default=$(git -C "$dir" symbolic-ref --short -q "refs/remotes/$remote/HEAD" 2>/dev/null) || default=""
  default=${default#"$remote"/}
  for spec in "${refs[@]}"; do
    spec=${spec#+}
    case "$spec" in :*) continue ;; esac
    src=${spec%%:*}
    dst=${spec#*:}
    [ "$dst" = HEAD ] && dst=$cur
    case "$dst" in
      refs/tags/*) continue ;;
      refs/heads/*) dst=${dst#refs/heads/} ;;
    esac
    [ -n "$dst" ] || continue
    if [ -n "$default" ]; then
      [ "$dst" = "$default" ] && continue
    else
      case "$dst" in main | master) continue ;; esac
    fi
    if git -C "$dir" rev-parse -q --verify "refs/tags/$src" >/dev/null 2>&1 \
      && ! git -C "$dir" rev-parse -q --verify "refs/heads/$src" >/dev/null 2>&1; then
      continue
    fi
    sha=$(git -C "$dir" rev-parse -q --verify "$src^{commit}" 2>/dev/null) \
      || sha=$(git -C "$dir" rev-parse -q --verify HEAD 2>/dev/null) || continue
    status=0
    GIT_TERMINAL_PROMPT=0 git -C "$dir" ls-remote --exit-code --heads "$remote" "refs/heads/$dst" >/dev/null 2>&1 || status=$?
    # This command commits before it pushes, so the lint (a lint config) and the receipt (a new branch)
    # below would read the old commit.
    if $CHAIN_MOVED_HEAD && { [ "$status" = 2 ] || bash "$scripts_dir/lint-changed-files.sh" --configured "$dir"; }; then
      print_deny_reason "$MOVED_HEAD_REASON"
      return 1
    fi
    check_lint "$dir" "$remote" "$dst" "${default:-main}" "$sha" || return 1
    case "$status" in
      0) continue ;;
      2) ;;
      *)
        echo "kc-gates: could not reach remote '$remote' to see whether '$dst' exists; not checking for a review receipt." >&2
        continue
        ;;
    esac
    change_class=$(read_change_class "$dir" --head "$sha")
    if ! is_small_class "$change_class" && ! bash "$scripts_dir/ready-receipt.sh" check "$sha" --pass >/dev/null 2>&1; then
      print_deny_reason "this is the first push of branch '$dst', and its commit $sha has no kc-ready-for-review receipt. Run /kc-gates:kc-ready-for-review on the committed branch before its first push (and before the PR): one pass of review and QA, ending in a receipt for that commit."
      return 1
    fi
    check_checklist "$sha" "$dir" || return 1
  done
  return 0
}

main() {
  local input command dir segment rest target head words change_class
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
    note_chain_segment "$segment" "$dir"
    rest=$(git_words "$segment")
    if [ -n "$rest" ]; then
      read -ra words <<< "$rest"
      check_push "$dir" "${words[@]}" || exit 0
      continue
    fi
    rest=$(gh_words "$segment")
    if [ -z "$rest" ]; then
      continue
    fi
    if ! is_hand_off "$rest"; then
      continue
    fi
    if $CHAIN_MOVED_HEAD; then
      print_deny_reason "$MOVED_HEAD_REASON"
      exit 0
    fi
    head=$(resolve_head "$rest" "$dir")
    if [ -z "$head" ]; then
      print_deny "this command opens or hands over a PR, but the guard could not find the PR's head commit (run it from the repo, or name the PR number and --repo), so it cannot check for a review receipt."
      exit 0
    fi
    change_class=$(read_change_class "$dir" --head "$head")
    if ! is_small_class "$change_class" && ! bash "$scripts_dir/ready-receipt.sh" check "$head" --pass >/dev/null 2>&1; then
      print_deny "this command opens or hands over a PR, and its head commit $head has no kc-ready-for-review receipt."
      exit 0
    fi
    check_checklist "$head" "$dir" || exit 0
  done <<EOF
$(split_segments "$command")
EOF
  exit 0
}

main
