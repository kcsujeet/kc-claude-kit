# shellcheck shell=bash
# Finding the review gather-review.sh saved, shared by the guards that hold a review to its walk
# receipt (guard-github-post.sh, guard-review-walk.sh). Sourced, never executed.

# True when <dir> holds what gather-review.sh saved of a review: its diff and changed files.
has_review_files() {
  [ -n "$1" ] && [ -f "$1/review.diff" ] && [ -f "$1/changed-files.txt" ]
}

# Prints the saved review folder (gather-review.sh's kc-review-*, from the last day) with the
# newest meta.env among those for this repo and, when given, this pull request; nothing if none.
find_review_dir() {
  local repo=$1 number=$2 candidate meta
  local -a metas=()
  while IFS= read -r candidate; do
    has_review_files "$candidate" || continue
    meta=$candidate/meta.env
    [ -f "$meta" ] || continue
    if [ -n "$number" ] && ! grep -qx "PR=$number" "$meta"; then continue; fi
    if [ -n "$repo" ] && ! grep '^URL=' "$meta" | grep -qiF "github.com/$repo/"; then continue; fi
    metas+=("$meta")
  done <<EOF
$(find "${TMPDIR:-/tmp}" -maxdepth 1 -type d -name 'kc-review-*' -mtime -1 2>/dev/null)
EOF
  [ "${#metas[@]}" -gt 0 ] || return 0
  # shellcheck disable=SC2012 # ls -t sorts by mtime; the paths are the guard's own temp folders
  dirname "$(ls -t "${metas[@]}" | head -n 1)"
}
