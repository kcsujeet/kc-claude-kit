#!/usr/bin/env bash
# Tests scripts/pass-size.sh against small diffs written in a scratch directory.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
pass_size="$(dirname "$tests_dir")/scripts/pass-size.sh"

# Writes a diff adding <line> to each of the given paths (new files), and their file list.
make_case() {
  local case_dir=$1 added_line=$2 changed_path
  shift 2
  mkdir -p "$case_dir/repo"
  : > "$case_dir/review.diff"
  : > "$case_dir/changed-files.txt"
  for changed_path in "$@"; do
    printf '%s\n' "$changed_path" >> "$case_dir/changed-files.txt"
    printf -- '--- /dev/null\n+++ b/%s\n@@ -0,0 +1 @@\n+%s\n' "$changed_path" "$added_line" >> "$case_dir/review.diff"
  done
}

size_of() {
  bash "$pass_size" "$1/review.diff" "$1/changed-files.txt" "$1/repo"
}

# --- small: two code files, a test and a locale file, no branch -----------------
make_case "$work_dir/small" '  const label = order.name' src/orders/label.ts src/orders/view.ts \
  src/orders/label.test.ts public/locales/en/orders.json
small=$(size_of "$work_dir/small")
expect_eq "small change: SIZE=small" "SIZE=small" "$(printf '%s\n' "$small" | sed -n 1p)"
expect_eq "no added branch: MUTATION=skip" "MUTATION=skip" "$(printf '%s\n' "$small" | sed -n 2p)"
expect_contains "tests and locale files are left out of the count" "files: 2 counted (2 test, locale or generated left out)" "$small"
expect_contains "no sensitive path: risk none" "risk: none" "$small"

# --- a branch in code turns the sweep on; one only in a test does not -------------
make_case "$work_dir/branch" '  if (order.total > 0) return order' src/orders/total.ts
expect_contains "added if: MUTATION=run" "MUTATION=run" "$(size_of "$work_dir/branch")"
make_case "$work_dir/test-branch" '  if (order.total > 0) return order' src/orders/total.test.ts
expect_contains "branch only in a test: MUTATION=skip" "MUTATION=skip" "$(size_of "$work_dir/test-branch")"

# --- too many files ---------------------------------------------------------------
make_case "$work_dir/many" 'x = 1' a.rb b.rb c.rb d.rb e.rb f.rb
expect_eq "six code files: SIZE=full" "SIZE=full" "$(size_of "$work_dir/many" | sed -n 1p)"

# --- too many lines ---------------------------------------------------------------
mkdir -p "$work_dir/long/repo"
printf 'src/report.ts\n' > "$work_dir/long/changed-files.txt"
{
  printf -- '--- /dev/null\n+++ b/src/report.ts\n@@ -0,0 +1,201 @@\n'
  for line_number in $(seq 1 201); do printf '+const row%s = %s\n' "$line_number" "$line_number"; done
} > "$work_dir/long/review.diff"
expect_eq "201 lines: SIZE=full" "SIZE=full" "$(size_of "$work_dir/long" | sed -n 1p)"
expect_eq "KC_SMALL_LINES raises the limit" "SIZE=small" \
  "$(KC_SMALL_LINES=300 bash "$pass_size" "$work_dir/long/review.diff" "$work_dir/long/changed-files.txt" | sed -n 1p)"

# --- sensitive paths --------------------------------------------------------------
make_case "$work_dir/migration" 'add_column :orders, :note, :string' db/migrate/20260101_add_note.rb
migration=$(size_of "$work_dir/migration")
expect_eq "migration: SIZE=full" "SIZE=full" "$(printf '%s\n' "$migration" | sed -n 1p)"
expect_contains "migration: names the rule and the file" "risk: schema or data migration (db/migrate/20260101_add_note.rb)" "$migration"

make_case "$work_dir/auth" 'x = 1' app/policies/order_policy.rb
expect_contains "policy file: permissions risk" "risk: authentication or permissions (app/policies/order_policy.rb)" "$(size_of "$work_dir/auth")"

make_case "$work_dir/pay" 'x = 1' src/checkout/summary.ts
expect_contains "checkout folder: payments risk" "risk: payments (src/checkout/summary.ts)" "$(size_of "$work_dir/pay")"

make_case "$work_dir/drop" '    remove_column :orders, :legacy_code' lib/tasks/cleanup.rb
expect_contains "added remove_column: deletes data" "risk: deletes data (remove_column :orders, :legacy_code)" "$(size_of "$work_dir/drop")"

mkdir -p "$work_dir/gone/repo"
printf 'src/old.ts\n' > "$work_dir/gone/changed-files.txt"
printf -- '--- a/src/old.ts\n+++ /dev/null\n@@ -1 +0,0 @@\n-export const old = 1\n' > "$work_dir/gone/review.diff"
expect_contains "deleted file: risk" "risk: deletes a file (src/old.ts)" "$(size_of "$work_dir/gone")"

# --- a test of a sensitive path is not a sensitive change; a comment is not a branch ---
make_case "$work_dir/auth-spec" '  # signs in or out the session' spec/controllers/session_controller_spec.rb src/orders/note.rb
auth_spec=$(size_of "$work_dir/auth-spec")
expect_contains "auth spec only: risk none" "risk: none" "$auth_spec"
expect_contains "comment with 'or': MUTATION=skip" "MUTATION=skip" "$auth_spec"

# --- a repo's own sensitive paths -------------------------------------------------
make_case "$work_dir/repo-rule" 'x = 1' app/services/ledger/post.rb
mkdir -p "$work_dir/repo-rule/repo/.claude"
printf '# money moves here\n(^|/)ledger/\n' > "$work_dir/repo-rule/repo/.claude/sensitive-paths.txt"
expect_contains "repo-listed path: risk" "risk: listed in .claude/sensitive-paths.txt (app/services/ledger/post.rb)" "$(size_of "$work_dir/repo-rule")"

# --- usage ------------------------------------------------------------------------
status=0
bash "$pass_size" "$work_dir/missing.diff" "$work_dir/small/changed-files.txt" 2>/dev/null || status=$?
expect_eq "missing diff exits 2" 2 "$status"

finish
