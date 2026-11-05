#!/usr/bin/env bash
# Tests scripts/select-gates.sh against small diffs written in a scratch repo.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
select_gates="$(dirname "$tests_dir")/scripts/select-gates.sh"

# Writes a diff adding <line> to each of the given paths, and their file list,
# into <case-dir>; the files themselves hold <line> under <case-dir>/repo.
make_case() {
  local case_dir=$1 added_line=$2 changed_path
  shift 2
  mkdir -p "$case_dir/repo"
  : > "$case_dir/review.diff"
  : > "$case_dir/changed-files.txt"
  for changed_path in "$@"; do
    mkdir -p "$(dirname "$case_dir/repo/$changed_path")"
    printf '%s\n' "$added_line" > "$case_dir/repo/$changed_path"
    printf '%s\n' "$changed_path" >> "$case_dir/changed-files.txt"
    printf -- '--- a/%s\n+++ b/%s\n@@ -0,0 +1 @@\n+%s\n' "$changed_path" "$changed_path" "$added_line" >> "$case_dir/review.diff"
  done
}

gates_for() {
  local case_dir=$1
  bash "$select_gates" "$case_dir/review.diff" "$case_dir/changed-files.txt" "$case_dir/repo" | sed -n 1p
}

# --- a Ruby-only change ------------------------------------------------------
make_case "$work_dir/ruby" '  def total = items.sum(&:price)' app/models/order.rb
ruby_output=$(bash "$select_gates" "$work_dir/ruby/review.diff" "$work_dir/ruby/changed-files.txt" "$work_dir/ruby/repo")
expect_eq "ruby: rails runs, react, datetime and i18n don't" \
  "GATES=naming,clarity,structure,simplicity,rails,testing,correctness" "$(printf '%s\n' "$ruby_output" | sed -n 1p)"
expect_contains "ruby: react's N/A reason is printed" \
  "react: N/A (no .jsx or .tsx file, and no changed JS or TS file imports React or a React library or defines a hook)" "$ruby_output"
expect_contains "ruby: rails names the file that triggered it" "rails: run (app/models/order.rb)" "$ruby_output"

# --- a React change ----------------------------------------------------------
make_case "$work_dir/tsx" '  return <OrderList orders={orders} />' src/orders/OrderList.tsx
expect_eq "tsx: react runs, rails doesn't" \
  "GATES=naming,clarity,structure,simplicity,react,testing,correctness" "$(gates_for "$work_dir/tsx")"

# A hook in a .ts file is React code too.
make_case "$work_dir/hook" "import { useState } from 'react'" src/orders/useOrders.ts
expect_eq "ts hook importing react: react runs" \
  "GATES=naming,clarity,structure,simplicity,react,testing,correctness" "$(gates_for "$work_dir/hook")"

# A plain .ts module is not.
make_case "$work_dir/plain-ts" 'export const sum = (a: number, b: number) => a + b' src/math.ts
expect_eq "plain ts: react doesn't run" \
  "GATES=naming,clarity,structure,simplicity,testing,correctness" "$(gates_for "$work_dir/plain-ts")"

# A read hook built on a React data library imports nothing from 'react' itself.
make_case "$work_dir/query-hook" "import { useQuery } from '@tanstack/react-query'" src/orders/useOrders.ts
expect_eq "hook on @tanstack/react-query: react runs" \
  "GATES=naming,clarity,structure,simplicity,react,testing,correctness" "$(gates_for "$work_dir/query-hook")"

# A hook that only calls other hooks imports no React library at all; in a React repo it is
# still React code.
make_case "$work_dir/composed-hook" 'export function useOrderCount() { return useOrders().data?.length ?? 0 }' src/orders/useOrderCount.ts
printf '{ "dependencies": { "react": "^19.1.0" } }\n' > "$work_dir/composed-hook/repo/package.json"
expect_eq "hook composing other hooks in a React repo: react runs" \
  "GATES=naming,clarity,structure,simplicity,react,testing,correctness" "$(gates_for "$work_dir/composed-hook")"

# The same shape in a Vue repo is a composable, not React.
make_case "$work_dir/vue-composable" 'export function useOrderCount() { return computed(() => orders.value.length) }' src/composables/useOrderCount.ts
printf '{ "dependencies": { "vue": "^3.5.0" } }\n' > "$work_dir/vue-composable/repo/package.json"
expect_eq "use… function in a Vue repo: react doesn't run" \
  "GATES=naming,clarity,structure,simplicity,testing,correctness" "$(gates_for "$work_dir/vue-composable")"

# --- dates, translations, locale files, the repo's own conventions -----------
make_case "$work_dir/dates" '  expires_at = 30.days.from_now' lib/orders/expiry.py
expect_contains "dates: an added duration runs datetime" \
  "GATES=naming,clarity,structure,simplicity,datetime," "$(gates_for "$work_dir/dates")"

make_case "$work_dir/call" "  const title = t('orders.title')" src/orders/title.js
expect_contains "a translation call runs i18n without a locale file" ",i18n," "$(gates_for "$work_dir/call")"

make_case "$work_dir/locale" '  "ordersTitle": "Orders"' public/locales/en/orders.json
expect_contains "a locale file runs i18n" ",i18n," "$(gates_for "$work_dir/locale")"

make_case "$work_dir/conventions" '  def total = 0' app/models/order.rb
mkdir -p "$work_dir/conventions/repo/.claude"
printf '# Conventions\n' > "$work_dir/conventions/repo/.claude/review-conventions.md"
expect_contains "review-conventions.md runs project-conventions" \
  "correctness,project-conventions" "$(gates_for "$work_dir/conventions")"

# --- one diff with every kind --------------------------------------------------
make_case "$work_dir/mixed" "import { useState } from 'react'" src/orders/Orders.tsx db/migrate/1_add_orders.rb
printf -- '--- a/x\n+++ b/x\n@@ -0,0 +1 @@\n+  placed_at: Time.current\n' >> "$work_dir/mixed/review.diff"
expect_eq "mixed: react, rails and datetime all run, in table order" \
  "GATES=naming,clarity,structure,simplicity,datetime,react,rails,testing,correctness" "$(gates_for "$work_dir/mixed")"

# --- usage errors -------------------------------------------------------------
check_status() {
  local label=$1 expected=$2 status
  shift 2
  set +e
  bash "$select_gates" "$@" >/dev/null 2>&1
  status=$?
  set -e
  expect_eq "$label" "$expected" "$status"
}
check_status "usage: no arguments exits 2" 2
check_status "usage: a missing diff exits 2" 2 "$work_dir/none.diff" "$work_dir/ruby/changed-files.txt"
check_status "usage: a missing file list exits 2" 2 "$work_dir/ruby/review.diff" "$work_dir/none.txt"

finish
