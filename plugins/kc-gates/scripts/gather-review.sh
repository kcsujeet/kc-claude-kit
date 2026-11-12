#!/usr/bin/env bash
# Step 1 of kc-code-review: saves the diff under review, its changed-file list and
# its metadata to one directory, so every gate reads the same files.
#
# Usage: gather-review.sh (<pr-number> [--since <sha> | --whole] | --branch [<base>]) [--out-dir <dir>]
#
#   <pr-number>      PR mode: `gh pr view <n> --json headRefOid,baseRefName,
#                    title,files,url` and `gh pr diff <n>`, for the repository
#                    of the current directory.
#   --since <sha>    PR mode, for a re-review: save only what changed from <sha>,
#                    the head reviewed last time, to the PR's head, so the
#                    gates read the new commits and not the whole PR again.
#                    Without it, the script looks for the last review the
#                    signed-in gh user submitted on the PR and uses the commit
#                    that review read, so a re-review is a delta without anyone
#                    remembering to ask; a first review finds none and saves
#                    the whole diff. --whole turns the lookup off.
#                    Needs both commits in the local clone and <sha> in the
#                    head's history; otherwise (not fetched yet, or the author
#                    rebased) it saves the whole diff and adds SINCE_SKIPPED=
#                    with the reason. When used, meta.env has SINCE=<sha>.
#   --branch [base]  Branch mode: `git diff <base>...HEAD` in the current repo.
#                    The base is <base> when given, else origin/HEAD, else
#                    main, else master.
#   --out-dir <dir>  Where to write (default: ${TMPDIR:-/tmp}/kc-review-<sha>).
#
# Writes <out-dir>/review.diff, <out-dir>/changed-files.txt (one path per line)
# and <out-dir>/meta.env, then prints meta.env. meta.env holds HEAD_SHA, BASE,
# TITLE, DIFF_FILE and CHANGED_FILES, plus PR and URL in PR mode. Values with
# characters outside [A-Za-z0-9_./:@+,-] are single-quoted, so the file can be
# sourced. In PR mode, when the local HEAD is not the PR's head commit, it adds
# FETCH=, the command that fetches it; it never runs the fetch itself. In branch
# mode, when the base is a local branch whose upstream has commits it lacks, it
# adds BASE_STALE=<base> is behind <upstream> by <n> commit(s): gather again with
# --branch <upstream>, since the diff then holds work that is already merged;
# it never fetches and never changes the base.
#
# Exits 0 on success, 1 when gh, git or the base lookup fails, 2 on a usage
# error.
set -euo pipefail

script_name=$(basename "$0")
usage() {
  echo "usage: $script_name (<pr-number> [--since <sha> | --whole] | --branch [<base>]) [--out-dir <dir>]" >&2
  exit 2
}
fail() {
  echo "$script_name: $1" >&2
  exit 1
}

# Prints KEY=value, single-quoting the value when it holds anything a shell
# would split or expand.
print_env_line() {
  local env_key=$1 env_value=$2
  case "$env_value" in
    *[!A-Za-z0-9_./:@+,-]*)
      env_value="'$(printf '%s' "$env_value" | sed "s/'/'\\\\''/g")'"
      ;;
  esac
  printf '%s=%s\n' "$env_key" "$env_value"
}

# Prints why the base is stale, or nothing: the base is a local branch whose
# upstream has commits it lacks. Always returns 0.
describe_stale_base() {
  local base=$1 upstream behind
  if ! upstream=$(git rev-parse --abbrev-ref "$base@{upstream}" 2>/dev/null); then
    return 0
  fi
  behind=$(git rev-list --count "$base..$upstream" 2>/dev/null || echo 0)
  [ "$behind" -gt 0 ] || return 0
  echo "$base is behind $upstream by $behind commit(s): gather again with --branch $upstream"
}

pr_number=""
branch_mode=false
base_arg=""
out_dir=""
since_sha=""
since_skipped=""
base_stale=""
whole_diff=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --branch)
      branch_mode=true
      if [ "$#" -ge 2 ] && [ "${2#-}" = "$2" ]; then
        base_arg=$2
        shift
      fi
      ;;
    --since)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then usage; fi
      since_sha=$2
      shift
      ;;
    --whole) whole_diff=true ;;
    --out-dir)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then usage; fi
      out_dir=$2
      shift
      ;;
    *)
      case "$1" in '' | *[!0-9]*) usage ;; esac
      [ -z "$pr_number" ] || usage
      pr_number=$1
      ;;
  esac
  shift
done
if [ "$branch_mode" = true ] && [ -n "$pr_number" ]; then usage; fi
if [ "$branch_mode" = false ] && [ -z "$pr_number" ]; then usage; fi
if [ "$branch_mode" = true ] && { [ -n "$since_sha" ] || [ "$whole_diff" = true ]; }; then usage; fi
if [ "$whole_diff" = true ] && [ -n "$since_sha" ]; then usage; fi

tmp_root=${TMPDIR:-/tmp}
tmp_root=${tmp_root%/}
diff_tmp=$(mktemp "$tmp_root/kc-review-diff.XXXXXX")
files_tmp=$(mktemp "$tmp_root/kc-review-files.XXXXXX")
trap 'rm -f "$diff_tmp" "$files_tmp"' EXIT

pr_url=""
fetch_command=""
if [ "$branch_mode" = true ]; then
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not inside a git work tree"
  if [ -n "$base_arg" ]; then
    git rev-parse --verify --quiet "$base_arg^{commit}" >/dev/null || {
      echo "$script_name: base not found: $base_arg" >&2
      exit 2
    }
    review_base=$base_arg
  elif origin_head=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null); then
    review_base=$origin_head
  elif git rev-parse --verify --quiet refs/heads/main >/dev/null; then
    review_base=main
  elif git rev-parse --verify --quiet refs/heads/master >/dev/null; then
    review_base=master
  else
    fail "no base branch: pass one after --branch (no origin/HEAD, main or master)"
  fi
  # A local base behind its upstream makes the diff carry already-merged work.
  base_stale=$(describe_stale_base "$review_base")
  head_sha=$(git rev-parse HEAD)
  review_title=$(git rev-parse --abbrev-ref HEAD)
  # Explicit prefixes and no external diff tool, whatever the user's git config
  # says, so the sweeps always read `a/` and `b/` paths.
  git diff --no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/ "$review_base...HEAD" > "$diff_tmp"
  git diff --no-ext-diff --name-only "$review_base...HEAD" > "$files_tmp"
else
  # headRefOid, baseRefName, url and title (one line each), then one path per
  # changed file. Field names: https://cli.github.com/manual/gh_pr_view
  pr_view=$(gh pr view "$pr_number" --json headRefOid,baseRefName,title,files,url \
    --jq '.headRefOid, .baseRefName, .url, (.title | gsub("[\r\n\t]+"; " ")), (.files[].path)') \
    || fail "gh pr view $pr_number failed"
  head_sha=$(printf '%s\n' "$pr_view" | sed -n 1p)
  review_base=$(printf '%s\n' "$pr_view" | sed -n 2p)
  pr_url=$(printf '%s\n' "$pr_view" | sed -n 3p)
  review_title=$(printf '%s\n' "$pr_view" | sed -n 4p)
  printf '%s\n' "$pr_view" | sed -n '5,$p' > "$files_tmp"
  printf '%s' "$head_sha" | grep -Eq '^[0-9a-f]{40}$' || fail "gh returned no head SHA for PR $pr_number"
  gh pr diff "$pr_number" --color never > "$diff_tmp" || fail "gh pr diff $pr_number failed"
  local_head=$(git rev-parse HEAD 2>/dev/null || true)
  if [ "$local_head" != "$head_sha" ]; then
    fetch_command="git fetch origin pull/$pr_number/head:pr-$pr_number"
  fi
  if [ -z "$since_sha" ] && [ "$whole_diff" = false ]; then
    # The commit the signed-in user's last review of this PR read, when there is
    # one and the head has moved since. No login or no review: a first review.
    reviewer=$(gh api user --jq .login 2>/dev/null || true)
    if [ -n "$reviewer" ]; then
      since_sha=$(gh pr view "$pr_number" --json reviews \
        --jq "[.reviews[] | select(.author.login == \"$reviewer\") | .commit.oid] | last // empty" 2>/dev/null || true)
      if [ "$since_sha" = "$head_sha" ]; then since_sha=""; fi
    fi
  fi
  if [ -n "$since_sha" ]; then
    if ! git cat-file -e "$head_sha^{commit}" 2>/dev/null; then
      since_skipped="the PR's head is not in this clone yet: run the FETCH command, then gather again"
    elif ! git cat-file -e "$since_sha^{commit}" 2>/dev/null; then
      since_skipped="$since_sha is not in this clone (rebased away, or never fetched)"
    elif ! git merge-base --is-ancestor "$since_sha" "$head_sha" 2>/dev/null; then
      since_skipped="$since_sha is not in the head's history: the branch was rebased"
    else
      since_sha=$(git rev-parse "$since_sha^{commit}")
      git diff --no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/ "$since_sha" "$head_sha" > "$diff_tmp"
      git diff --no-ext-diff --name-only "$since_sha" "$head_sha" > "$files_tmp"
    fi
  fi
fi

[ -n "$out_dir" ] || out_dir="$tmp_root/kc-review-$head_sha"
mkdir -p "$out_dir"
out_dir=$(cd "$out_dir" && pwd)
diff_file="$out_dir/review.diff"
changed_files="$out_dir/changed-files.txt"
meta_file="$out_dir/meta.env"
cp "$diff_tmp" "$diff_file"
cp "$files_tmp" "$changed_files"

{
  print_env_line HEAD_SHA "$head_sha"
  print_env_line BASE "$review_base"
  print_env_line TITLE "$review_title"
  if [ -n "$pr_number" ]; then
    print_env_line PR "$pr_number"
    print_env_line URL "$pr_url"
  fi
  print_env_line DIFF_FILE "$diff_file"
  print_env_line CHANGED_FILES "$changed_files"
  if [ -n "$fetch_command" ]; then print_env_line FETCH "$fetch_command"; fi
  if [ -n "$base_stale" ]; then print_env_line BASE_STALE "$base_stale"; fi
  if [ -n "$since_skipped" ]; then
    print_env_line SINCE_SKIPPED "$since_skipped"
  elif [ -n "$since_sha" ]; then
    print_env_line SINCE "$since_sha"
  fi
} > "$meta_file"

cat "$meta_file"
