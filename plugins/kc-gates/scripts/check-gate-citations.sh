#!/usr/bin/env bash
# Checks the citations in review gate output against the head under review: every citation shaped
# `path:line@sha` or `path:Lline@sha` must carry a sha that is a prefix of the head sha, and its
# line must exist in that file at the head (`git show <head>:<path>`). A citation with an older
# sha, or a line past the end of the file, was read from another commit or never read, so the
# finding it backs is not evidence.
#
# Usage: check-gate-citations.sh <head-sha> <repo-root> <gate-output-file>...
#
# Prints one line per bad citation (`<file>: <citation>: <problem>`) and exits 1 when there is
# any, 0 when every citation holds (or there are none), 2 on a usage error.
set -euo pipefail

script_name=$(basename "$0")
[ "$#" -ge 3 ] || { echo "usage: $script_name <head-sha> <repo-root> <gate-output-file>..." >&2; exit 2; }
head_sha=$1
repo_root=$2
shift 2
head_full=$(git -C "$repo_root" rev-parse --verify --quiet "$head_sha^{commit}") || { echo "$script_name: $head_sha is not a commit in $repo_root" >&2; exit 2; }

problem_count=0
short_sha_chars=7
for output_file in "$@"; do
  [ -r "$output_file" ] || { echo "$script_name: cannot read $output_file" >&2; exit 2; }
  while IFS= read -r citation; do
    cited_path=${citation%:*}
    rest=${citation##*:}
    cited_line=${rest%%@*}
    cited_line=${cited_line#L}
    cited_sha=${rest##*@}
    problem_text=""
    case "$head_full" in
      "$cited_sha"*) ;;
      *) problem_text="sha $cited_sha is not the head ${head_full:0:short_sha_chars}: re-read the file at the head and cite that" ;;
    esac
    if [ -z "$problem_text" ]; then
      line_count=$(git -C "$repo_root" show "$head_full:$cited_path" 2>/dev/null | grep -c '' || true)
      if ! git -C "$repo_root" cat-file -e "$head_full:$cited_path" 2>/dev/null; then
        problem_text="$cited_path does not exist at the head"
      elif [ "$cited_line" -lt 1 ] || [ "$cited_line" -gt "$line_count" ]; then
        problem_text="line $cited_line is not in $cited_path at the head (it has $line_count)"
      fi
    fi
    if [ -n "$problem_text" ]; then
      printf '%s: %s: %s\n' "$output_file" "$citation" "$problem_text"
      problem_count=$((problem_count + 1))
    fi
  done <<EOF
$(grep -Eo '[A-Za-z0-9_./-]+:L?[0-9]+@[0-9a-fA-F]{4,40}' "$output_file" | sort -u)
EOF
done
[ "$problem_count" -eq 0 ]
