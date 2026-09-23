#!/usr/bin/env bash
# Runs every sweep fixture and compares the output with its expected.txt.
#
# Layout: tests/sweeps/<topic>/<sweep>/
#   input.diff     the unified diff fed to skills/<topic>/scripts/<sweep>.sh
#   expected.txt   the exact output expected
#   repo/          optional: files the sweep reads as the repo root; the runner
#                  copies it to a temp dir and makes it a git work tree
#   untracked.txt  optional: paths under repo/ to leave untracked (one per line)
#
# Exits 1 and names each fixture whose output differs, 0 when all match.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

failures=0
fixture_count=0

for fixture_dir in "$tests_dir"/sweeps/*/*/; do
  fixture_dir=${fixture_dir%/}
  sweep_name=$(basename "$fixture_dir")
  topic=$(basename "$(dirname "$fixture_dir")")
  sweep_script="$plugin_dir/skills/$topic/scripts/$sweep_name.sh"
  # `_shared` fixtures test the topic-independent scripts in scripts/.
  if [ "$topic" = "_shared" ]; then sweep_script="$plugin_dir/scripts/$sweep_name.sh"; fi
  fixture_count=$((fixture_count + 1))

  if [ ! -f "$sweep_script" ]; then
    echo "FAIL $topic/$sweep_name: no script at skills/$topic/scripts/$sweep_name.sh"
    failures=$((failures + 1))
    continue
  fi

  sweep_args=("$fixture_dir/input.diff")
  if [ -d "$fixture_dir/repo" ]; then
    repo_copy="$work_dir/$topic-$sweep_name"
    cp -R "$fixture_dir/repo" "$repo_copy"
    git -C "$repo_copy" init -q
    untracked_list="$fixture_dir/untracked.txt"
    ( cd "$repo_copy" && find . -type f -not -path './.git/*' | sed 's|^\./||' ) | while IFS= read -r repo_file; do
      if [ -f "$untracked_list" ] && grep -qxF "$repo_file" "$untracked_list"; then continue; fi
      git -C "$repo_copy" add -- "$repo_file"
    done
    sweep_args+=("$repo_copy")
  fi

  actual_output="$work_dir/$topic-$sweep_name.out"
  if ! bash "$sweep_script" "${sweep_args[@]}" > "$actual_output"; then
    echo "FAIL $topic/$sweep_name: script exited non-zero"
    failures=$((failures + 1))
    continue
  fi

  if diff -u "$fixture_dir/expected.txt" "$actual_output" > "$work_dir/diff.txt"; then
    echo "ok   $topic/$sweep_name"
  else
    echo "FAIL $topic/$sweep_name: output differs from expected.txt"
    sed 's/^/     /' "$work_dir/diff.txt"
    failures=$((failures + 1))
  fi
done

# The sweeps share one usage contract; check it once per script. The empty-diff
# run happens inside an empty git work tree, which the repo-aware sweeps default to.
# Lookups (scripts whose usage line takes no `<diff-file|->`) are checked for the
# exit-2 half only; run-lookups.sh covers their output.
empty_repo="$work_dir/empty-repo"
mkdir -p "$empty_repo"
git -C "$empty_repo" init -q
for sweep_script in "$plugin_dir"/skills/*/scripts/*.sh; do
  script_label=${sweep_script#"$plugin_dir"/skills/}
  set +e
  bash "$sweep_script" >/dev/null 2>&1
  usage_status=$?
  set -e
  if [ "$usage_status" -ne 2 ]; then
    echo "FAIL $script_label: expected exit 2 with no arguments, got $usage_status"
    failures=$((failures + 1))
  fi
  grep -qF '<diff-file|->' "$sweep_script" || continue
  stdin_output=$(cd "$empty_repo" && printf '' | bash "$sweep_script" - 2>&1) || {
    echo "FAIL $script_label: non-zero exit on an empty diff from stdin: $stdin_output"
    failures=$((failures + 1))
  }
done

echo "$fixture_count fixtures, $failures failure(s)"
[ "$failures" -eq 0 ]
