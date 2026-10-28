#!/usr/bin/env bash
# i18n §I3: the two duplicate greps for one key, across the whole source-locale
# tree. A lookup, not a diff sweep: it takes one key, not a diff.
#   1. the English value, as literal text;
#   2. the unscoped leaf key, as `"<leaf-key>":` (whitespace before the colon
#      allowed), so a feature-namespaced key still collides with a flat one.
#
# Usage: locale-duplicates.sh <locale-dir> <value> <leaf-key>
# Prints `value: path:line: text` for each value hit, then
# `key: path:line: text` for each key hit, each group sorted by path and line.
# Every hit is printed, including the file being added to; the gate decides
# which are duplicates, and reasons about semantic equivalents itself.
# Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_name=$(basename "$0")
if [ "$#" -ne 3 ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "usage: $script_name <locale-dir> <value> <leaf-key>" >&2
  exit 2
fi
locale_dir=$1
english_value=$2
leaf_key=$3
if [ ! -d "$locale_dir" ]; then
  echo "$script_name: not a directory: $locale_dir" >&2
  exit 2
fi

# Runs grep -rn with the given pattern flags and prints `<label>: path:line: text`.
labelled_grep() {
  local label=$1 hits grep_status
  shift
  set +e
  hits=$(grep -rnI "$@" "$locale_dir")
  grep_status=$?
  set -e
  if [ "$grep_status" -gt 1 ]; then
    echo "$script_name: grep failed with status $grep_status" >&2
    exit 2
  fi
  [ -n "$hits" ] || return 0
  printf '%s\n' "$hits" | awk -v label="$label" '{
    first = index($0, ":")
    rest = substr($0, first + 1)
    second = index(rest, ":")
    printf "%s\t%d\t%s: %s%s %s\n", substr($0, 1, first - 1), substr(rest, 1, second - 1), label, substr($0, 1, first), substr(rest, 1, second), substr(rest, second + 1)
  }' | sort -t "$(printf '\t')" -k1,1 -k2,2n | cut -f 3-
}

escaped_key=$(printf '%s' "$leaf_key" | sed 's/[][\.*^$+?(){}|/]/\\&/g')

labelled_grep value -F -e "$english_value"
labelled_grep key -E -e "\"$escaped_key\"[[:space:]]*:"
