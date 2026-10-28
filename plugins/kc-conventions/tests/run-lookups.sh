#!/usr/bin/env bash
# Runs every lookup fixture and compares the output with its expected.txt.
# Lookups are the skill scripts that take a name or a key instead of a diff, so
# run-sweeps.sh (diff in, hits out) does not fit them.
#
# Layout: tests/lookups/<topic>/<script>/
#   repo/                      files the lookup searches; the runner copies it
#                              to a temp dir, makes it a git work tree with every
#                              file tracked, and runs each case from inside it
#   untracked.txt              optional: paths under repo/ to leave untracked
#   cases/<case>/args          the script's arguments, one per line; `{repo}`
#                              is replaced with the repo copy's path
#   cases/<case>/expected.txt  the exact output expected
#
# Exits 1 and names each case whose output differs, 0 when all match.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

failures=0
case_count=0

for lookup_dir in "$tests_dir"/lookups/*/*/; do
  lookup_dir=${lookup_dir%/}
  script_name=$(basename "$lookup_dir")
  topic=$(basename "$(dirname "$lookup_dir")")
  lookup_script="$plugin_dir/skills/$topic/scripts/$script_name.sh"
  if [ ! -f "$lookup_script" ]; then
    echo "FAIL $topic/$script_name: no script at skills/$topic/scripts/$script_name.sh"
    failures=$((failures + 1))
    continue
  fi

  repo_copy="$work_dir/$topic-$script_name"
  cp -R "$lookup_dir/repo" "$repo_copy"
  git -C "$repo_copy" init -q
  untracked_list="$lookup_dir/untracked.txt"
  ( cd "$repo_copy" && find . -type f -not -path './.git/*' | sed 's|^\./||' ) | while IFS= read -r repo_file; do
    if [ -f "$untracked_list" ] && grep -qxF "$repo_file" "$untracked_list"; then continue; fi
    git -C "$repo_copy" add -- "$repo_file"
  done

  for case_dir in "$lookup_dir"/cases/*/; do
    case_dir=${case_dir%/}
    case_label="$topic/$script_name/$(basename "$case_dir")"
    case_count=$((case_count + 1))

    lookup_args=()
    while IFS= read -r arg_line || [ -n "$arg_line" ]; do
      if [ "$arg_line" = "{repo}" ]; then arg_line=$repo_copy; fi
      lookup_args+=("$arg_line")
    done < "$case_dir/args"

    actual_output="$work_dir/out.txt"
    if ! (cd "$repo_copy" && bash "$lookup_script" "${lookup_args[@]}") > "$actual_output"; then
      echo "FAIL $case_label: script exited non-zero"
      failures=$((failures + 1))
      continue
    fi
    if diff -u "$case_dir/expected.txt" "$actual_output" > "$work_dir/diff.txt"; then
      echo "ok   $case_label"
    else
      echo "FAIL $case_label: output differs from expected.txt"
      sed 's/^/     /' "$work_dir/diff.txt"
      failures=$((failures + 1))
    fi
  done
done

echo "$case_count cases, $failures failure(s)"
[ "$failures" -eq 0 ]
