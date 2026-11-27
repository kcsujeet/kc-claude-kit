#!/usr/bin/env bash
# react §R12: a hook called in a component whose results are only handed on as props (directly or
# through a value derived from them), never read by the component itself. The fetch may belong in
# the child that reads it. Each hit is a hook call for the gate to judge, not a finding.
#
# Usage: pass-through-hooks.sh <diff-file|-> [repo-root]
# Reads each changed .tsx/.jsx file whole from repo-root (default: the current directory), so a
# hook call the diff leaves unchanged is still judged when the diff changes how its results are
# used; a hook is reported only when its call or one of its uses is an added line.
# Prints `path:line: text` per hit, the hook call's line in the new file.
# Exits 0 with or without hits, 2 on a usage error. Portable to bash 3.2 and BSD awk.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then kc_require_diff_arg "$(basename "$0")" "" " [repo-root]"; fi
kc_require_diff_arg "$(basename "$0")" "$1" " [repo-root]"
repo_root=${2:-.}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
diff_copy="$work_dir/review.diff"
cat "$1" > "$diff_copy"
kc_added_lines "$diff_copy" | cut -f1,2 > "$work_dir/added.tsv"
: > "$work_dir/files.tsv"
kc_changed_files "$diff_copy" | while IFS= read -r changed_path; do
  case "$changed_path" in *.tsx | *.jsx) ;; *) continue ;; esac
  [ -f "$repo_root/$changed_path" ] || continue
  awk -v path="$changed_path" '{ printf "%s\t%d\t%s\n", path, NR, $0 }' "$repo_root/$changed_path" >> "$work_dir/files.tsv"
done

awk -F '\t' '
  function word_pattern(name) { return "(^|[^A-Za-z0-9_$])" name "([^A-Za-z0-9_$]|$)" }
  function track(name, origin) {
    if (name == "" || name ~ /^\.\.\./) return
    origin_of[name] = origin
  }
  function track_destructured(list, origin,    parts, n, i, item) {
    n = split(list, parts, ",")
    for (i = 1; i <= n; i++) {
      item = parts[i]
      sub(/=.*$/, "", item)
      if (index(item, ":") > 0) item = substr(item, index(item, ":") + 1)
      gsub(/[ \t]/, "", item)
      track(item, origin)
    }
  }
  function flush(    origin) {
    for (origin in origin_text)
      if (prop_uses[origin] > 0 && own_uses[origin] == 0 && touched[origin]) printf "%s\n", origin_text[origin]
    split("", origin_of); split("", origin_text); split("", prop_uses); split("", own_uses); split("", touched)
  }
  FNR == NR { added[$1 "\t" $2] = 1; next }
  $1 != current_path { flush(); current_path = $1 }
  {
    text = $0
    sub(/^[^\t]*\t[^\t]*\t/, "", text)
    hit = sprintf("%s:%s: %s", $1, $2, text)
    is_added = (($1 "\t" $2) in added)
    if (match(text, /(const|let)[ \t]+\{[^}]*\}[ \t]*=[ \t]*use[A-Z][A-Za-z0-9_]*\(/)) {
      list = substr(text, RSTART, RLENGTH); sub(/^[^{]*\{/, "", list); sub(/\}.*$/, "", list)
      origin_text[hit] = hit; touched[hit] = is_added; track_destructured(list, hit); next
    }
    if (match(text, /(const|let)[ \t]+[A-Za-z_$][A-Za-z0-9_$]*[ \t]*=[ \t]*use[A-Z][A-Za-z0-9_]*\(/)) {
      name = substr(text, RSTART, RLENGTH); sub(/^(const|let)[ \t]+/, "", name); sub(/[ \t]*=.*$/, "", name)
      origin_text[hit] = hit; touched[hit] = is_added; track(name, hit); next
    }
    for (name in origin_of) {
      if (text !~ word_pattern(name)) continue
      origin = origin_of[name]
      if (is_added) touched[origin] = 1
      # A value derived from a tracked name is tracked too; its declaration is not a use.
      # A JSX element held in a variable is a use, not a derived value.
      if (text !~ /=[ \t]*</ && match(text, /^[ \t]*(const|let)[ \t]+[A-Za-z_$][A-Za-z0-9_$]*[ \t]*=/)) {
        derived = substr(text, RSTART, RLENGTH); sub(/^[ \t]*(const|let)[ \t]+/, "", derived); sub(/[ \t]*=.*$/, "", derived)
        if (!(derived in origin_of)) { origin_of[derived] = origin; continue }
      }
      if (text ~ ("[A-Za-z0-9_]+=\\{([^}]*[^A-Za-z0-9_$])?" name "([^A-Za-z0-9_$][^}]*)?\\}")) prop_uses[origin]++
      else own_uses[origin]++
    }
  }
  END { flush() }
' "$work_dir/added.tsv" "$work_dir/files.tsv" | sort -t: -k1,1 -k2,2n
