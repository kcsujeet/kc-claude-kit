#!/usr/bin/env bash
# Keeps the count kc-ready-for-review aims to hold at zero: how many of a
# reviewer's comments a rule already covered, so a slipping pass shows up as a
# number instead of a feeling. One line per PR in
# ${KC_READY_DIR:-$HOME/.claude/kc-ready-for-review}/tally.tsv.
#
#   review-tally.sh add <pr-url> <covered> <new> <disagreement>
#       After sorting a reviewer's round (the skill's "After the reviewer
#       comments"). A second add for the same PR replaces its line.
#   review-tally.sh report
#       Totals per month: PRs, covered, new, disagreements.
#   review-tally.sh reverts <repo-dir> [<since>]
#       Merged PRs later reverted on the repo's default branch (origin/HEAD, else the current
#       branch), since a git date (default
#       "3 months ago"): one `<date>  #<pr>  <revert-sha>  <reverted subject>` line each. A revert
#       is the plainest miss review can have; the look-back sorts each like a reviewer comment.
set -euo pipefail

tally_file=${KC_READY_DIR:-$HOME/.claude/kc-ready-for-review}/tally.tsv

usage() {
  sed -n '7,16s/^# \{0,1\}//p' "$0" >&2
  exit 2
}

is_count() {
  printf '%s' "$1" | grep -Eqx '[0-9]+'
}

add_line() {
  [ "$#" -eq 4 ] || usage
  local pr_url=$1 covered=$2 new=$3 disagreement=$4
  if ! is_count "$covered" || ! is_count "$new" || ! is_count "$disagreement"; then
    usage
  fi
  mkdir -p "$(dirname "$tally_file")"
  touch "$tally_file"
  local kept
  kept=$(awk -F'\t' -v pr="$pr_url" '$2 != pr' "$tally_file")
  {
    [ -z "$kept" ] || printf '%s\n' "$kept"
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%Y-%m-%d)" "$pr_url" "$covered" "$new" "$disagreement"
  } > "$tally_file"
}

report() {
  [ -s "$tally_file" ] || { echo "No reviews tallied yet."; return 0; }
  printf 'month\tprs\tcovered\tnew\tdisagreement\n'
  awk -F'\t' '{ month = substr($1, 1, 7); prs[month]++; c[month] += $3; n[month] += $4; d[month] += $5 }
    END { for (m in prs) printf "%s\t%d\t%d\t%d\t%d\n", m, prs[m], c[m], n[m], d[m] }' "$tally_file" | sort
}

# A revert reaches the default branch two ways. GitHub's Revert button squash-merges a revert PR
# as `Revert "<title>" (#<revert-pr>)`, with no "This reverts commit" line, so the reverted PR is
# the commit whose subject is `<title> (#<n>)`. A command-line `git revert` keeps
# "This reverts commit <sha>" in its body. The PR number comes from the reverted commit's subject:
# `(#123)` for a squash merge, `Merge pull request #123` for a merge commit.
reverts() {
  [ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
  local repo_dir=$1 since=${2:-3 months ago} branch revert_sha revert_date reverted_sha subject title pr
  git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || { echo "review-tally: not a git repo: $repo_dir" >&2; exit 2; }
  branch=$(git -C "$repo_dir" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || echo HEAD)
  git -C "$repo_dir" log "$branch" --since="$since" --format='%H %ad' --date=short --grep='^Revert "' |
    while read -r revert_sha revert_date; do
      reverted_sha=$(git -C "$repo_dir" log -1 --format=%B "$revert_sha" | sed -n 's/.*This reverts commit \([0-9a-f]\{7,40\}\).*/\1/p' | head -n 1)
      if [ -n "$reverted_sha" ]; then
        subject=$(git -C "$repo_dir" log -1 --format=%s "$reverted_sha" 2>/dev/null) || continue
      else
        title=$(git -C "$repo_dir" log -1 --format=%s "$revert_sha" | sed -n 's/^Revert "\(.*\)"\( (#[0-9][0-9]*)\)\{0,1\}$/\1/p')
        [ -n "$title" ] || continue
        subject=$(git -C "$repo_dir" log "$revert_sha" --format=%s | grep -F -m 1 "$title (#" || true)
      fi
      pr=$(printf '%s\n' "$subject" | sed -n -e 's/.*(#\([0-9][0-9]*\))$/\1/p' -e 's/^Merge pull request #\([0-9][0-9]*\).*/\1/p' | head -n 1)
      [ -n "$pr" ] || continue
      printf '%s\t#%s\t%s\t%s\n' "$revert_date" "$pr" "${revert_sha:0:12}" "$subject"
    done
}

case "${1:-}" in
  add) shift; add_line "$@" ;;
  report) report ;;
  reverts) shift; reverts "$@" ;;
  *) usage ;;
esac
