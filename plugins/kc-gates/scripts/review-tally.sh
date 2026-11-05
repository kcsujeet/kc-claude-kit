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
set -euo pipefail

tally_file=${KC_READY_DIR:-$HOME/.claude/kc-ready-for-review}/tally.tsv

usage() {
  sed -n '7,11s/^# \{0,1\}//p' "$0" >&2
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

case "${1:-}" in
  add) shift; add_line "$@" ;;
  report) report ;;
  *) usage ;;
esac
