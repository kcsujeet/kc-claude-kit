#!/usr/bin/env bash
# Tests scripts/install-rules.sh: every rule lands as a copy, the stamp matches
# plugin.json, a second run is idempotent, --dry-run writes nothing, a missing
# rules directory fails loudly, and hooks/check-installed.sh treats the result
# as current.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
installer="$plugin_dir/scripts/install-rules.sh"
hook="$plugin_dir/hooks/check-installed.sh"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

passes=0
failures=0
record() {
  local label=$1 verdict=$2 detail=${3:-}
  if [ "$verdict" = ok ]; then
    echo "ok   $label"
    passes=$((passes + 1))
  else
    echo "FAIL $label"
    [ -z "$detail" ] || printf '%s\n' "$detail" | sed 's/^/     /'
    failures=$((failures + 1))
  fi
}
expect_eq() {
  local label=$1 expected=$2 actual=$3
  if [ "$expected" = "$actual" ]; then
    record "$label" ok
  else
    record "$label" fail "expected: $expected
actual:   $actual"
  fi
}

plugin_version=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$plugin_dir/.claude-plugin/plugin.json" | head -n 1)
rule_names=$(cd "$plugin_dir/rules" && find . -maxdepth 1 -name "*.md" | sed "s|^\./||" | sort)
rule_count=$(printf '%s\n' "$rule_names" | wc -l | tr -d ' ')

project="$work_dir/project"
mkdir -p "$project/.git"

first_output=$(cd "$project" && bash "$installer")
missing=""
not_copies=""
for rule_name in $rule_names; do
  installed="$project/.claude/rules/$rule_name"
  if [ ! -f "$installed" ]; then missing="$missing $rule_name"; continue; fi
  [ -L "$installed" ] && not_copies="$not_copies $rule_name"
  cmp -s "$installed" "$plugin_dir/rules/$rule_name" || not_copies="$not_copies $rule_name"
done
expect_eq "first run: every rule present" "" "$missing"
expect_eq "first run: every rule is a byte-identical copy, not a symlink" "" "$not_copies"
expect_eq "first run: stamp matches plugin.json" "$plugin_version" "$(cat "$project/.claude/rules/.kc-conventions-version")"
expect_eq "first run: every rule reported new" "$rule_count" "$(printf '%s\n' "$first_output" | grep -c '^new: ')"
expect_eq "first run: summary line" "installed $rule_count rule(s) into .claude/rules" "$(printf '%s\n' "$first_output" | tail -n 1)"

expect_eq "hook: freshly installed rules are current" "" \
  "$(cd "$project" && HOME="$work_dir/home" CLAUDE_PLUGIN_ROOT="$plugin_dir" bash "$hook")"

second_output=$(cd "$project" && bash "$installer")
expect_eq "second run: every rule unchanged" "$rule_count" "$(printf '%s\n' "$second_output" | grep -c '^unchanged: ')"
expect_eq "second run: stamp unchanged" "$plugin_version" "$(cat "$project/.claude/rules/.kc-conventions-version")"
expect_eq "second run: same file set" "$(cd "$project/.claude/rules" && find . -mindepth 1 -maxdepth 1 | sed "s|^\./||" | sort)" \
  "$( { printf '%s\n' "$rule_names"; echo .kc-conventions-version; } | sort)"

echo "local edit" >> "$project/.claude/rules/naming.md"
dry_output=$(cd "$project" && bash "$installer" --dry-run)
expect_eq "dry run: names the locally edited rule" "would replace: naming.md" "$(printf '%s\n' "$dry_output" | grep '^would replace: ')"
if grep -q 'local edit' "$project/.claude/rules/naming.md"; then
  record "dry run: leaves the edited rule alone" ok
else
  record "dry run: leaves the edited rule alone" fail "naming.md was overwritten"
fi
third_output=$(cd "$project" && bash "$installer")
expect_eq "rerun: replaces the edited rule" "replaced: naming.md" "$(printf '%s\n' "$third_output" | grep '^replaced: ')"

custom_dest="$work_dir/custom/rules"
bash "$installer" --dest "$custom_dest" >/dev/null
expect_eq "--dest: installs into the given directory" "$plugin_version" "$(cat "$custom_dest/.kc-conventions-version")"

set +e
bash "$installer" --bogus >/dev/null 2>&1
usage_status=$?
fake_plugin="$work_dir/fake-plugin"
mkdir -p "$fake_plugin/scripts" "$fake_plugin/.claude-plugin"
cp "$installer" "$fake_plugin/scripts/"
printf '{\n  "version": "1.0.0"\n}\n' > "$fake_plugin/.claude-plugin/plugin.json"
missing_output=$(cd "$work_dir" && bash "$fake_plugin/scripts/install-rules.sh" --dest "$work_dir/unused" 2>&1)
missing_status=$?
set -e
expect_eq "usage error: exit 2" "2" "$usage_status"
expect_eq "no rules: exit 1" "1" "$missing_status"
if printf '%s' "$missing_output" | grep -q 'no rules found at'; then
  record "no rules: clear message" ok
else
  record "no rules: clear message" fail "$missing_output"
fi
if [ -e "$work_dir/unused" ]; then
  record "no rules: nothing created" fail "$work_dir/unused exists"
else
  record "no rules: nothing created" ok
fi

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
