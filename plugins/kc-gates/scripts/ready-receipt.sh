#!/usr/bin/env bash
# Writes and checks the receipts of kc-ready-for-review: one file per commit
# the pass ended on, named by its full SHA, under
# ${KC_READY_DIR:-$HOME/.claude/kc-ready-for-review}. guard-hand-off.sh lets a
# PR go to review only when its head commit has one.
#
#   ready-receipt.sh write <sha> --rounds <n> --open <n>
#       After a pass: the rounds it ran (1 or 2) and the findings it left
#       open for the user.
#   ready-receipt.sh write <sha> --after <pass-sha>
#       After commits that only apply fixes the user picked from that pass's
#       open list. Refused unless <pass-sha> has a receipt.
#   ready-receipt.sh check <sha>
#       Exits 0 and prints the receipt when there is one, 1 otherwise.
set -euo pipefail

receipts_dir=${KC_READY_DIR:-$HOME/.claude/kc-ready-for-review}

usage() {
  sed -n '7,14s/^# \{0,1\}//p' "$0" >&2
  exit 2
}

is_full_sha() {
  printf '%s' "$1" | grep -Eqx '[0-9a-f]{40}'
}

write_receipt() {
  local sha=$1 rounds="" open="" after=""
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --rounds) rounds=$2; shift 2 ;;
      --open) open=$2; shift 2 ;;
      --after) after=$2; shift 2 ;;
      *) usage ;;
    esac
  done
  mkdir -p "$receipts_dir"
  if [ -n "$after" ]; then
    is_full_sha "$after" || { echo "ready-receipt: --after needs a full SHA" >&2; exit 2; }
    if [ ! -f "$receipts_dir/$after" ]; then
      echo "ready-receipt: $after has no receipt; run the pass first" >&2
      exit 1
    fi
    printf 'sha=%s\ndate=%s\nafter=%s\n' "$sha" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$after" > "$receipts_dir/$sha"
  else
    printf '%s' "$rounds" | grep -Eqx '[12]' || { echo "ready-receipt: --rounds is 1 or 2" >&2; exit 2; }
    printf '%s' "$open" | grep -Eqx '[0-9]+' || { echo "ready-receipt: --open is a count" >&2; exit 2; }
    printf 'sha=%s\ndate=%s\nrounds=%s\nopen=%s\n' "$sha" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rounds" "$open" > "$receipts_dir/$sha"
  fi
  echo "receipt written: $receipts_dir/$sha"
}

[ "$#" -ge 2 ] || usage
action=$1
sha=$2
shift 2
is_full_sha "$sha" || { echo "ready-receipt: <sha> must be a full 40-character SHA" >&2; exit 2; }

case "$action" in
  write) write_receipt "$sha" "$@" ;;
  check) cat "$receipts_dir/$sha" 2>/dev/null ;;
  *) usage ;;
esac
