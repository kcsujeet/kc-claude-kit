#!/usr/bin/env bash
# Tests scripts/read-config.sh: valid configs normalize with defaults,
# invalid ones print one error per problem and exit 1.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
script="$(dirname "$tests_dir")/scripts/read-config.sh"
fixtures="$tests_dir/fixtures/config"
stderr_file=$(mktemp)
trap 'rm -f "$stderr_file"' EXIT
passes=0
failures=0

pass() { echo "ok   $1"; passes=$((passes + 1)); }
fail() { echo "FAIL $1"; echo "     $2"; failures=$((failures + 1)); }

expect_value() {
  local label=$1 fixture=$2 filter=$3 expected=$4 out actual status=0
  out=$(bash "$script" "$fixtures/$fixture" 2>"$stderr_file") || status=$?
  actual=$(printf '%s' "$out" | jq -c "$filter") || actual="<jq failed>"
  if [ "$status" = 0 ] && [ "$actual" = "$expected" ]; then
    pass "$label"
  else
    fail "$label" "expected $expected, got $actual (status $status); stderr: $(cat "$stderr_file")"
  fi
}

expect_error() {
  local label=$1 fixture=$2 needle=$3 status=0
  bash "$script" "$fixtures/$fixture" >/dev/null 2>"$stderr_file" || status=$?
  if [ "$status" = 1 ] && grep -qF "$needle" "$stderr_file"; then
    pass "$label"
  else
    fail "$label" "status $status, stderr: $(cat "$stderr_file")"
  fi
}

expect_value "defaults: fix rounds"     valid-min.json  '.limits.max_fix_rounds' '4'
expect_value "defaults: per-unit cap"   valid-min.json  '.limits.max_agents_per_unit' '200'
expect_value "defaults: ports"          valid-min.json  '.launch.ports'          '{"base":4100,"per_unit":10}'
expect_value "defaults: models"         valid-min.json  '.models'                '{"workers":"sonnet","staff":"best"}'
expect_value "defaults: login is null"  valid-min.json  '.launch.login'          'null'
expect_value "keeps: staff model"       valid-full.json '.models.staff'          '"opus"'
expect_value "keeps: extra agents"      valid-full.json '.review.extra_agents'   '["event-temple-ruby:rails-security"]'
expect_value "keeps: per-unit cap"      valid-full.json '.limits.max_agents_per_unit' '80'
expect_error "rejects start without {port}" bad-start.json  'launch.start must contain {port}'
expect_error "rejects ready without {port}" bad-start.json  'launch.ready must contain {port}'
expect_error "rejects empty checks"         bad-checks.json 'checks must be a non-empty array'
expect_error "rejects non-JSON"             not-json.json   'not valid JSON'
expect_error "rejects missing file"         missing.json    'not found'
expect_error "rejects launch as a string"   launch-string.json  'launch must be an object'
expect_error "rejects ports as a number"    ports-number.json   'launch.ports must be an object'
expect_error "rejects top-level array"      top-array.json      'must be a JSON object'
expect_error "rejects limits as a string"   limits-string.json  'limits must be an object'
expect_error "rejects models as an array"   models-array.json   'models must be an object'

echo "read-config: $passes passed, $failures failed"
[ "$failures" = 0 ]
