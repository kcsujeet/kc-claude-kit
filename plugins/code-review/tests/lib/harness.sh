# shellcheck shell=bash
# Shared assertions for the code-review script tests. Sourced, never executed.
# The sourcing runner sets tests_dir before sourcing.

passes=0
failures=0
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

record() {
  local label=$1 verdict=$2 detail=${3:-}
  if [ "$verdict" = ok ]; then
    echo "ok   $label"
    passes=$((passes + 1))
  else
    echo "FAIL $label"
    if [ -n "$detail" ]; then printf '%s\n' "$detail" | sed 's/^/     /'; fi
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

# Passes when <file> matches <expected-file> exactly; shows the diff otherwise.
expect_file() {
  local label=$1 expected_file=$2 actual_file=$3
  if diff -u "$expected_file" "$actual_file" > "$work_dir/expect-file.diff"; then
    record "$label" ok
  else
    record "$label" fail "$(cat "$work_dir/expect-file.diff")"
  fi
}

expect_contains() {
  local label=$1 needle=$2 haystack=$3
  case "$haystack" in
    *"$needle"*) record "$label" ok ;;
    *) record "$label" fail "missing: $needle
in:      $haystack" ;;
  esac
}

# Puts the stub gh first on PATH, answering from <fixture-dir>/routes.tsv, and
# logs every call to $KC_GH_LOG.
use_gh_fixtures() {
  export KC_GH_ROUTES="$1/routes.tsv"
  export KC_GH_LOG="$work_dir/gh-calls.log"
  : > "$KC_GH_LOG"
  case ":$PATH:" in
    *":${tests_dir:?}/lib:"*) ;;
    *) export PATH="$tests_dir/lib:$PATH" ;;
  esac
}

# jq backs the stub's --jq; the scripts under test need it only through gh.
require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL jq is required to run these tests (the gh stub emulates --jq with it)"
    exit 1
  fi
}

finish() {
  echo "$passes passed, $failures failed"
  [ "$failures" -eq 0 ]
}
