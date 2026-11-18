# shellcheck shell=bash
# The diff a `git commit` would record, for the hooks that read it. Sourced, never executed.

# get_commit_diff <dir> "<diff options>" <word>...: the diff a `git commit` with these words after
# `commit` would record: the staged diff, or with -a/--all the working tree against HEAD. A
# repository with no commit yet is diffed against the empty tree.
get_commit_diff() {
  local dir=$1 options=$2 word all=false base=HEAD
  shift 2
  for word in "$@"; do
    case "$word" in
      --all) all=true ;;
      --*) ;;
      -*a*) all=true ;;
    esac
  done
  git -C "$dir" rev-parse -q --verify HEAD >/dev/null 2>&1 || base=4b825dc642cb6eb9a060e54bf8d69288fbee4904
  # shellcheck disable=SC2086 # $options is a list of diff options
  if $all; then
    git -C "$dir" diff $options --no-color --no-ext-diff --no-renames "$base"
  else
    git -C "$dir" diff --cached $options --no-color --no-ext-diff --no-renames "$base"
  fi
}
