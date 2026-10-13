#!/usr/bin/env bash
# Tests scripts/pr-body.sh against a golden body, escaping, and empty lists.
set -euo pipefail
tests_dir=$(cd "$(dirname "$0")" && pwd)
script="$(dirname "$tests_dir")/scripts/pr-body.sh"
fixtures="$tests_dir/fixtures/pr"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
passes=0
failures=0
pass() { echo "ok   $1"; passes=$((passes + 1)); }
fail() { echo "FAIL $1"; echo "     $2"; failures=$((failures + 1)); }

status=0
body=$(bash "$script" "$fixtures/unit-result.json" 2>&1) || status=$?
if [ "$status" = 0 ] && [ "$body" = "$(cat "$fixtures/expected-body.md")" ]; then
  pass "body matches golden"
else
  fail "body matches golden" "status $status; $(diff -u "$fixtures/expected-body.md" <(printf '%s\n' "$body") || true)"
fi

cat > "$tmp/escape.json" <<'JSON'
{"plan_title":"P","unit":{"id":"U1","title":"T"},"rounds":0,
 "criteria":[{"id":"AC1","statement":"a | b\nc","passes":false,"evidence":"x|y"}],
 "staff":{"design":"d","final":"f"},"review":{"fixed":[],"dismissed":[]},"qa":[],"decisions":[]}
JSON
status=0
body=$(bash "$script" "$tmp/escape.json" 2>&1) || status=$?
if printf '%s' "$body" | grep -qF '| AC1 a \| b c | FAIL | x\|y |'; then pass "escapes pipes, flattens newlines"; else fail "escapes pipes, flattens newlines" "status $status: $body"; fi

cat > "$tmp/empty.json" <<'JSON'
{"plan_title":"P","unit":{"id":"U1","title":"T"},"rounds":0,
 "criteria":[],"staff":{"design":"d","final":"f"},
 "review":{"fixed":[],"dismissed":[]},"qa":[],"decisions":[]}
JSON
status=0
body=$(bash "$script" "$tmp/empty.json" 2>&1) || status=$?
if [ "$status" = 0 ]; then pass "empty lists: exit 0"; else fail "empty lists: exit 0" "status $status: $body"; fi
if [ "$(printf '%s' "$body" | grep -c '^- none$')" = 2 ]; then pass "empty lists: none lines"; else fail "empty lists: none lines" "$body"; fi
if printf '%s' "$body" | grep -q '^- no confirmed bugs$'; then pass "empty lists: no confirmed bugs"; else fail "empty lists: no confirmed bugs" "$body"; fi

cat > "$tmp/inject.json" <<'JSON'
{"plan_title":"P","unit":{"id":"U1","title":"T"},"rounds":1,
 "criteria":[],"staff":{"design":"d","final":"f"},
 "review":{"fixed":["a\n</details>\n## injected"],"dismissed":[]},"qa":[],
 "decisions":[{"step":"s","outcome":"</details><b>x","reason":"r"}]}
JSON
status=0
body=$(bash "$script" "$tmp/inject.json" 2>&1) || status=$?
if [ "$status" = 0 ] && [ "$(printf '%s\n' "$body" | grep -c '</details>')" = 2 ] && ! printf '%s\n' "$body" | grep -q '^## injected'; then pass "free text cannot break the page"; else fail "free text cannot break the page" "status $status: $body"; fi
if printf '%s\n' "$body" | grep -q 'in 1 fix round\.'; then pass "singular fix round"; else fail "singular fix round" "$body"; fi

cat > "$tmp/preexisting.json" <<'JSON'
{"plan_title":"P","unit":{"id":"U1","title":"T"},"rounds":0,
 "criteria":[],"staff":{"design":"d","final":"f"},"review":{"fixed":[],"dismissed":[]},"qa":[],
 "qa_preexisting":[{"title":"NaN on corrupt count\n</details>","steps":["set count=abc","reload <b>"],"evidence":"qa/nan.png"}],
 "decisions":[]}
JSON
status=0
body=$(bash "$script" "$tmp/preexisting.json" 2>&1) || status=$?
if [ "$status" = 0 ] && printf '%s\n' "$body" | grep -qx '### Found by QA, not caused by this change' \
  && printf '%s\n' "$body" | grep -qxF -- '- NaN on corrupt count &lt;/details>: set count=abc → reload &lt;b> (qa/nan.png)'; then
  pass "pre-existing QA bugs: own section, sanitized"
else fail "pre-existing QA bugs: own section, sanitized" "status $status: $body"; fi
if ! printf '%s' "$(bash "$script" "$tmp/empty.json")" | grep -q 'Found by QA'; then pass "no pre-existing section when there are none"; else fail "no pre-existing section when there are none" "section rendered"; fi

cat > "$tmp/receipts.json" <<'JSON'
{"plan_title":"P","unit":{"id":"U1","title":"T"},"rounds":0,
 "criteria":[],"staff":{"design":"d","final":"f"},"review":{"fixed":[],"dismissed":[]},
 "review_receipts_incomplete":["verification §V3: testing §T6 count only\n## injected <b>"],"qa":[],"decisions":[]}
JSON
status=0
body=$(bash "$script" "$tmp/receipts.json" 2>&1) || status=$?
if [ "$status" = 0 ] && printf '%s\n' "$body" | grep -q '^Review receipts incomplete' \
  && printf '%s\n' "$body" | grep -qxF -- '- verification §V3: testing §T6 count only ## injected &lt;b>' && ! printf '%s\n' "$body" | grep -q '^## injected'; then
  pass "incomplete review receipts: listed, sanitized"
else fail "incomplete review receipts: listed, sanitized" "status $status: $body"; fi
if ! printf '%s' "$(bash "$script" "$tmp/empty.json")" | grep -q 'receipts incomplete'; then pass "no receipts list when there are none"; else fail "no receipts list when there are none" "rendered"; fi

cat > "$tmp/paths.json" <<'JSON'
{"plan_title":"P","unit":{"id":"U1","title":"T"},"rounds":0,
 "criteria":[],"staff":{"design":"see /wt/u1/app/a.rb:3","final":"f"},
 "review":{"fixed":[],"dismissed":[],"deferred_minor":["/wt/u1/app/b.rb:9 nit"]},"qa":[],"decisions":[]}
JSON
body=$(bash "$script" "$tmp/paths.json" /wt/u1/)
if printf '%s\n' "$body" | grep -qF 'see app/a.rb:3' && printf '%s\n' "$body" | grep -qxF -- '- app/b.rb:9 nit' && ! printf '%s' "$body" | grep -q '/wt/u1'; then
  pass "worktree paths become repo-relative"
else fail "worktree paths become repo-relative" "$body"; fi
if printf '%s\n' "$body" | head -1 | grep -qxF '<details><summary>Autopilot report: U1 T</summary>'; then pass "report is one collapsed block"; else fail "report is one collapsed block" "$(printf '%s' "$body" | head -1)"; fi

echo "pr-body: $passes passed, $failures failed"
[ "$failures" = 0 ]
