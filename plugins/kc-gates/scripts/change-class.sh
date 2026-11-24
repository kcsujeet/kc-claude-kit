#!/usr/bin/env bash
# Classifies a change, by script, never by judgment, so the guards that ask the user for typed words
# ask only when a change needs it. Read by guard-loop-stop.sh, guard-hand-off.sh, guard-merge.sh
# and approvals-needed.sh.
#
# Usage: change-class.sh [--dir <repo>] [--base <rev>] [--head <rev> | --staged | --all]
#
#   --dir    The repository (default: the current directory).
#   --base   The revision the change is measured from (default: the merge-base of HEAD, or --head,
#            with the default branch: origin/HEAD, origin/main, origin/master, main, master).
#   --head   The change is <base>..<rev> (default: HEAD).
#   --staged The change is <base> to the index: what `git commit` would record on top of the branch.
#   --all    The change is <base> to the working tree's tracked files (`git commit -a`).
#
# Prints CLASS=<class> first, then one reason line, then pass-size.sh's lines for the same diff:
#   CLASS=prose_small  Only prose files change (Markdown, reStructuredText, AsciiDoc), outside any
#                      script, hook, test or eval folder (KC_CHECK_PATHS), plus files the repo lists
#                      as regenerated from them (.claude/generated-paths.txt, one extended regex per
#                      line) and files whose every changed line only sets a version; no file is
#                      deleted, and at most KC_PROSE_SMALL_LINES (default 30) prose lines change
#                      (added plus removed, regenerated files not counted).
#   CLASS=code_small   Not prose_small, and pass-size.sh says SIZE=small: few files and lines, and no
#                      risk: line (authentication, permissions, payments, migrations, public API,
#                      data or file deletion, a public page).
#   CLASS=full         Anything else, an empty change, or a change the script cannot read.
# Always exits 0 once its arguments parse; 2 on a usage error.
set -u

scripts_dir=$(dirname "$0")
# shellcheck source=lib/risk-paths.sh
. "$scripts_dir/lib/risk-paths.sh"

readonly PROSE_PATHS='\.(md|mdx|markdown|rst|adoc)$'
# A changed line that only sets a version: a JSON or TOML key, or a constant, holding a quoted value
# (the same line guard-loop-stop.sh leaves out of its blame).
readonly VERSION_LINE='^[-+][[:space:]]*"?(version|VERSION)"?[[:space:]]*[:=][[:space:]]*"[^"]*",?[[:space:]]*$'
max_prose_lines=${KC_PROSE_SMALL_LINES:-30}

usage() {
  echo "usage: change-class.sh [--dir <repo>] [--base <rev>] [--head <rev> | --staged | --all]" >&2
  exit 2
}

dir=.
base=""
head_rev=HEAD
mode=rev
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir) [ "$#" -ge 2 ] || usage; dir=$2; shift ;;
    --base) [ "$#" -ge 2 ] || usage; base=$2; shift ;;
    --head) [ "$#" -ge 2 ] || usage; head_rev=$2; mode=rev; shift ;;
    --staged) mode=staged ;;
    --all) mode=all ;;
    *) usage ;;
  esac
  shift
done

print_full() {
  echo "CLASS=full"
  echo "reason: $1"
  exit 0
}

default_branch_ref() {
  local remote_default candidate
  remote_default=$(git -C "$dir" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) || remote_default=""
  for candidate in $remote_default origin/main origin/master main master; do
    git -C "$dir" rev-parse -q --verify "$candidate^{commit}" >/dev/null 2>&1 && { printf '%s' "$candidate"; return; }
  done
}

[ "$mode" != rev ] && head_rev=HEAD
git -C "$dir" rev-parse -q --verify "$head_rev^{commit}" >/dev/null 2>&1 || print_full "no commit $head_rev here"
if [ -z "$base" ]; then
  default_ref=$(default_branch_ref)
  [ -n "$default_ref" ] || print_full "no default branch to measure from"
  base=$(git -C "$dir" merge-base "$default_ref" "$head_rev" 2>/dev/null) || print_full "no merge-base with $default_ref"
fi
git -C "$dir" rev-parse -q --verify "$base^{commit}" >/dev/null 2>&1 || print_full "no base commit $base here"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
diff_options=(--no-color --no-ext-diff --no-renames)
case "$mode" in
  staged)
    git -C "$dir" diff --cached "${diff_options[@]}" "$base" > "$scratch/review.diff" 2>/dev/null || print_full "the staged diff could not be read"
    git -C "$dir" diff --cached --name-only --no-renames "$base" > "$scratch/changed-files.txt" 2>/dev/null ;;
  all)
    git -C "$dir" diff "${diff_options[@]}" "$base" > "$scratch/review.diff" 2>/dev/null || print_full "the working tree diff could not be read"
    git -C "$dir" diff --name-only --no-renames "$base" > "$scratch/changed-files.txt" 2>/dev/null ;;
  *)
    git -C "$dir" diff "${diff_options[@]}" "$base" "$head_rev" > "$scratch/review.diff" 2>/dev/null || print_full "the diff could not be read"
    git -C "$dir" diff --name-only --no-renames "$base" "$head_rev" > "$scratch/changed-files.txt" 2>/dev/null ;;
esac
[ -s "$scratch/changed-files.txt" ] || print_full "the change is empty"

repo_root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || repo_root=$dir
generated_paths='^$'
if [ -f "$repo_root/.claude/generated-paths.txt" ]; then
  while IFS= read -r pattern || [ -n "$pattern" ]; do
    case "$pattern" in '' | '#'*) continue ;; esac
    generated_paths="$generated_paths|$pattern"
  done < "$repo_root/.claude/generated-paths.txt"
fi

# One line per file: "<kind> <changed lines> <path>", kind one of prose, generated, version, deleted,
# other. A file header is read only between `diff --git` and its first hunk.
KC_PROSE=$PROSE_PATHS KC_CHECKS=$KC_CHECK_PATHS KC_GENERATED=$generated_paths KC_VERSION=$VERSION_LINE awk '
  function flush() {
    if (path == "") return
    if (deleted) kind = "deleted"
    else if (path ~ ENVIRON["KC_GENERATED"]) kind = "generated"
    else if (path ~ ENVIRON["KC_PROSE"] && path !~ ENVIRON["KC_CHECKS"]) kind = "prose"
    else if (changed > 0 && only_version) kind = "version"
    else kind = "other"
    print kind, changed + 0, path
    path = ""
  }
  /^diff --git / { flush(); in_header = 1; deleted = 0; changed = 0; only_version = 1; next }
  in_header && /^\+\+\+ \/dev\/null/ { deleted = 1; next }
  in_header && /^--- a\// { path = substr($0, 7); next }
  in_header && /^\+\+\+ b\// { path = substr($0, 7); next }
  in_header && /^Binary files / { only_version = 0; changed++; next }
  /^@@/ { in_header = 0; next }
  in_header { next }
  /^[-+]/ { changed++; if ($0 !~ ENVIRON["KC_VERSION"]) only_version = 0 }
  END { flush() }' "$scratch/review.diff" > "$scratch/kinds.txt"

size_report=$(bash "$scripts_dir/pass-size.sh" "$scratch/review.diff" "$scratch/changed-files.txt" "$repo_root" 2>/dev/null) || size_report="SIZE=full"
prose_lines=$(awk '$1 == "prose" { n += $2 } END { print n + 0 }' "$scratch/kinds.txt")
not_prose=$(awk '$1 == "other" || $1 == "deleted" { print $1 ": " $3; exit }' "$scratch/kinds.txt")

if [ -z "$not_prose" ] && [ "$prose_lines" -le "$max_prose_lines" ]; then
  echo "CLASS=prose_small"
  echo "reason: only prose changes ($prose_lines prose lines, at most $max_prose_lines), plus regenerated files and version bumps"
elif printf '%s\n' "$size_report" | grep -qx 'SIZE=small'; then
  echo "CLASS=code_small"
  echo "reason: pass-size.sh says small with no risk line (${not_prose:-$prose_lines prose lines, over $max_prose_lines})"
else
  echo "CLASS=full"
  echo "reason: not prose alone (${not_prose:-$prose_lines prose lines, over $max_prose_lines}) and pass-size.sh says full"
fi
printf '%s\n' "$size_report"
