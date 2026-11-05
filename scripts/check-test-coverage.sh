#!/usr/bin/env bash
# Fails when a plugin script has no test, so "every script is tested" stays true as scripts are
# added. Run from the repo root (CI does, on every PR).
#
# A script under plugins/ (not in tests/ or evals/) counts as tested when:
#   - a file in its plugin's tests/ names it, or
#   - it is a sweep or lookup with a fixture folder of its name under its plugin's tests/, or
#   - it is a symlink to a script that is tested, or
#   - scripts/test-coverage-exempt.txt lists its path with the reason it needs no test of its own
#     (`<path> <reason>`), such as a sourced library its callers' tests run.
#
# Prints one line per untested script and exits 1 when there is any, 0 otherwise.
set -euo pipefail

exempt_file=scripts/test-coverage-exempt.txt
untested=0

is_exempt() {
  [ -f "$exempt_file" ] && grep -qE "^$1[[:space:]]+[^[:space:]]" "$exempt_file"
}

is_tested() {
  local script_path=$1 plugin_dir script_name link target
  plugin_dir=$(printf '%s\n' "$script_path" | cut -d/ -f1-2)
  script_name=$(basename "$script_path" .sh)
  if [ -L "$script_path" ]; then
    link=$(readlink "$script_path")
    target=$(cd "$(dirname "$script_path")/$(dirname "$link")" && pwd)/$(basename "$link")
    target=${target#"$PWD"/}
    is_tested "$target"
    return
  fi
  is_exempt "$script_path" && return 0
  [ -d "$plugin_dir/tests" ] || return 1
  grep -rqsE "(^|[^A-Za-z0-9_-])$script_name(\.sh)?([^A-Za-z0-9_-]|$)" "$plugin_dir/tests" --include='*.sh' && return 0
  find "$plugin_dir/tests" -mindepth 3 -maxdepth 3 -type d -name "$script_name" | grep -q . && return 0
  return 1
}

while IFS= read -r script_path; do
  [ -n "$script_path" ] || continue
  if ! is_tested "$script_path"; then
    echo "$script_path has no test (add one under its plugin's tests/, or list it in $exempt_file with the reason)"
    untested=$((untested + 1))
  fi
done < <(git ls-files 'plugins/*.sh' | grep -vE '/(tests|evals)/')

if [ "$untested" -gt 0 ]; then
  echo "$untested untested script(s)" >&2
  exit 1
fi
echo "test coverage: every plugin script has a test"
