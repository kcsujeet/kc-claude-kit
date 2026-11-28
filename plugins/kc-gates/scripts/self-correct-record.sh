#!/usr/bin/env bash
# The record kc-self-correct leaves: which content it reviewed and fixed until clean, keyed on the
# content's git tree hash (tree-hash.sh), never a commit, so uncommitted work can be reviewed and a
# later commit of the same content matches it. kc-ready-for-human-review and the hand-off guard
# read it. One file per tree under ${KC_SELF_CORRECT_DIR:-$HOME/.claude/kc-self-correct}.
#
#   self-correct-record.sh write --rounds <1-3> --open <n> --pass <dir> [--size small|full] [--tree <hash>]
#       Records that the pass folder's rounds reviewed the content (default: the working tree as it
#       is now). Refused unless every round has verdict blocks, rounds after the first have fixes.txt,
#       and the last round's meta.env TREE (when it has one) is this content: content that changed
#       after the last round needs another round on the delta. The record says clean=yes only when
#       nothing is open and the last round found nothing (or final.txt settles what round 3 found).
#   self-correct-record.sh check <tree> [--clean]
#       Prints the record and exits 0 when one exists for that tree (with --clean, a clean one);
#       exits 1 otherwise.
#   self-correct-record.sh help
set -euo pipefail

scripts_dir=$(cd "$(dirname "$0")" && pwd)
records_dir=${KC_SELF_CORRECT_DIR:-$HOME/.claude/kc-self-correct}
readonly MAX_ROUNDS=3

usage() {
  awk '/^#   self-correct-record.sh/ { show = 1 } show && /^#$/ { exit } show { sub(/^# ?/, ""); print }' "$0" >&2
  exit 2
}

is_tree_hash() { printf '%s' "$1" | grep -Eqx '[0-9a-f]{40}'; }

# Prints the number of findings a round's gate blocks list (bullets under FINDINGS:).
count_round_findings() {
  local file
  for file in "$1"/verdicts/*; do
    cat "$file"
    echo
  done | awk '/^FINDINGS:/ { in_findings = 1; next } /^GATE:/ { in_findings = 0 } in_findings && /^- / && !/^- (none|None)/ { found++ } END { print found + 0 }'
}

write_record() {
  local rounds="" open="" pass_dir="" size="" tree="" round dir problems=() findings broken clean=no meta_tree
  while [ "$#" -gt 0 ]; do
    [ "$#" -ge 2 ] || usage
    case "$1" in
      --rounds) rounds=$2 ;;
      --open) open=$2 ;;
      --pass) pass_dir=$2 ;;
      --size) size=$2 ;;
      --tree) tree=$2 ;;
      *) usage ;;
    esac
    shift 2
  done
  printf '%s' "$rounds" | grep -Eqx '[1-9]' || { echo "self-correct-record: --rounds is the count of rounds, 1 to $MAX_ROUNDS" >&2; exit 2; }
  [ "$rounds" -le "$MAX_ROUNDS" ] || { echo "self-correct-record: at most $MAX_ROUNDS rounds: past that the fixes keep making findings, so stop and ask the person whether the approach is wrong" >&2; exit 2; }
  printf '%s' "$open" | grep -Eqx '[0-9]+' || { echo "self-correct-record: --open is a count" >&2; exit 2; }
  case "$size" in '' | small | full) ;; *) echo "self-correct-record: --size is small or full" >&2; exit 2 ;; esac
  [ -d "$pass_dir" ] || { echo "self-correct-record: --pass <dir> is the pass folder" >&2; exit 2; }
  [ -n "$tree" ] || tree=$(bash "$scripts_dir/tree-hash.sh") || exit 1
  is_tree_hash "$tree" || { echo "self-correct-record: $tree is not a tree hash" >&2; exit 2; }

  for ((round = 1; round <= rounds; round++)); do
    dir=$pass_dir/round-$round
    if [ -z "$(ls -A "$dir/verdicts" 2>/dev/null)" ]; then
      problems+=("round-$round: no verdict blocks in round-$round/verdicts/")
    fi
  done
  if { [ "$rounds" -gt 1 ] || [ "$open" -gt 0 ]; } && [ ! -f "$pass_dir/fixes.txt" ]; then
    problems+=("no fixes.txt: a line per finding (fixed, mechanical or open) is the record of what the rounds fixed")
  fi
  meta_tree=$(sed -n 's/^TREE=//p' "$pass_dir/round-$rounds/meta.env" 2>/dev/null | head -n 1 || true)
  if [ -n "$meta_tree" ] && [ "$meta_tree" != "$tree" ]; then
    problems+=("the content changed after round $rounds reviewed it (its TREE is $meta_tree, the content is $tree): review the delta as another round, within the $MAX_ROUNDS-round limit")
  fi
  if [ "${#problems[@]}" -gt 0 ]; then
    echo "self-correct-record: refused; the pass folder does not show the rounds ran:" >&2
    printf '  %s\n' "${problems[@]}" >&2
    exit 1
  fi

  findings=$(count_round_findings "$pass_dir/round-$rounds")
  broken=$(awk -F '\t' '$2 == "breaks" { n++ } END { print n + 0 }' "$pass_dir/round-$rounds/uses-verdicts.txt" 2>/dev/null || echo 0)
  if [ "$open" -eq 0 ] && { [ "$findings" -eq 0 ] && [ "$broken" -eq 0 ] || { [ "$rounds" -eq "$MAX_ROUNDS" ] && [ -f "$pass_dir/final.txt" ]; }; }; then
    clean=yes
  fi
  mkdir -p "$records_dir"
  {
    printf 'tree=%s\ndate=%s\nrounds=%s\nopen=%s\nclean=%s\npass=%s\n' "$tree" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rounds" "$open" "$clean" "$pass_dir"
    [ -z "$size" ] || printf 'size=%s\n' "$size"
  } > "$records_dir/$tree"
  echo "self-correct record written: $records_dir/$tree (clean=$clean)"
}

check_record() {
  local tree=$1 clean_only=false
  shift
  case "${1:-}" in
    '') ;;
    --clean) clean_only=true ;;
    *) usage ;;
  esac
  is_tree_hash "$tree" || usage
  [ -f "$records_dir/$tree" ] || return 1
  if $clean_only && ! grep -qx 'clean=yes' "$records_dir/$tree"; then
    return 1
  fi
  cat "$records_dir/$tree"
}

case "${1:-}" in
  help | --help | -h) { awk '/^#   self-correct-record.sh/ { show = 1 } show && /^#$/ { exit } show { sub(/^# ?/, ""); print }' "$0"; exit 0; } ;;
  write) shift; write_record "$@" ;;
  check) [ "$#" -ge 2 ] || usage; shift; check_record "$@" ;;
  *) usage ;;
esac
