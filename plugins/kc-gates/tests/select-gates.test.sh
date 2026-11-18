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

select_gates_output() {
  bash "$select_gates" "$1/review.diff" "$1/changed-files.txt" "$1/repo"
}

gates_for() {
  select_gates_output "$1" | sed -n 1p
}

# --- a Ruby-only change ------------------------------------------------------
make_case "$work_dir/ruby" '  def total = items.sum(&:price)' app/models/order.rb
ruby_output=$(select_gates_output "$work_dir/ruby")
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

# --- security: request handling runs it, and nothing else does -----------------
# (lib/risk-paths.sh is sourced here and by pass-size.sh, so both tests run its code.)
make_case "$work_dir/controller" '  def show; end' app/controllers/orders_controller.rb
expect_contains "a controller file runs security, after correctness" "correctness,security" "$(gates_for "$work_dir/controller")"
expect_contains "security names the file that triggered it" "security: run (app/controllers/orders_controller.rb)" \
  "$(select_gates_output "$work_dir/controller")"

make_case "$work_dir/route-handler" '  return Response.json({})' src/app/api/orders/route.ts
expect_contains "an API route handler runs security" ",security" "$(gates_for "$work_dir/route-handler")"

make_case "$work_dir/auth-file" '  const ok = true' src/lib/session-store.ts
expect_contains "an auth or session file runs security" ",security" "$(gates_for "$work_dir/auth-file")"

make_case "$work_dir/reads-params" '  total = params[:total]' lib/orders/total.rb
reads_params=$(select_gates_output "$work_dir/reads-params")
expect_contains "an added line reading request input runs security, outside any handler path" ",security" "$(printf '%s\n' "$reads_params" | sed -n 1p)"
expect_contains "security names the line that triggered it" "security: run (an added line reads request input or declares a handler: total = params[:total])" "$reads_params"

make_case "$work_dir/express" '  app.get("/orders/:id", show)' src/server.js
expect_contains "an express route added to a plain file runs security" ",security" "$(gates_for "$work_dir/express")"

make_case "$work_dir/model-only" '  def total = items.sum(&:price)' app/models/order.rb
model_only=$(select_gates_output "$work_dir/model-only")
expect_contains "a model with no request input skips security, with a reason" \
  "security: N/A (no controller, route, handler, middleware or auth file changed and no added line reads request input)" "$model_only"
expect_eq "a model with no request input: security is not in GATES" \
  "GATES=naming,clarity,structure,simplicity,rails,testing,correctness" "$(printf '%s\n' "$model_only" | sed -n 1p)"

make_case "$work_dir/controller-spec" '  get "/orders", params: { id: 1 }' spec/controllers/orders_controller_spec.rb
expect_eq "a controller spec alone does not run security" \
  "GATES=naming,clarity,structure,simplicity,rails,testing,correctness" "$(gates_for "$work_dir/controller-spec")"

make_case "$work_dir/prose" 'Read the id with params[:id].' docs/routing.md
expect_eq "prose that mentions params does not run security" \
  "GATES=naming,clarity,structure,simplicity,testing,correctness" "$(gates_for "$work_dir/prose")"

make_case "$work_dir/security-and-conventions" '  def show; end' app/controllers/orders_controller.rb
mkdir -p "$work_dir/security-and-conventions/repo/.claude"
printf '# Conventions\n' > "$work_dir/security-and-conventions/repo/.claude/review-conventions.md"
expect_contains "security sits between correctness and project-conventions" "correctness,security,project-conventions" \
  "$(gates_for "$work_dir/security-and-conventions")"

# In the plugin cache layout (cache/<marketplace>/<plugin>/<version>) kc-conventions is not a
# sibling folder but the highest version under its own name.
cache_dir="$work_dir/cache/shop-kit"
mkdir -p "$cache_dir/kc-gates" "$cache_dir/kc-conventions/2.6.0/scripts/lib" "$cache_dir/kc-conventions/2.6.1/scripts/lib"
cp -R "$(dirname "$tests_dir")" "$cache_dir/kc-gates/3.0.0"
printf "request_surface_pattern='CACHED_OLD'\n" > "$cache_dir/kc-conventions/2.6.0/scripts/lib/request-surface-pattern.sh"
printf "request_surface_pattern='cached_newest'\n" > "$cache_dir/kc-conventions/2.6.1/scripts/lib/request-surface-pattern.sh"
make_case "$work_dir/cached" '  cached_newest = 1' lib/orders/total.rb
cached_output=$(bash "$cache_dir/kc-gates/3.0.0/scripts/select-gates.sh" "$work_dir/cached/review.diff" "$work_dir/cached/changed-files.txt" "$work_dir/cached/repo")
expect_contains "cache layout: the highest kc-conventions version's request_surface_pattern runs security" \
  "security: run (an added line reads request input or declares a handler: cached_newest = 1)" "$cached_output"
rm -rf "$cache_dir/kc-conventions"
expect_contains "cache layout: no kc-conventions is a usage error naming it" "kc-conventions" \
  "$(bash "$cache_dir/kc-gates/3.0.0/scripts/select-gates.sh" "$work_dir/cached/review.diff" "$work_dir/cached/changed-files.txt" "$work_dir/cached/repo" 2>&1 || true)"

# --- WALK: a path a signed-out visitor reaches must be walked ------------------
walk_line_for() { select_gates_output "$1" | grep '^WALK='; }
make_case "$work_dir/walk-route" 'x = 1' src/app/public/orders/page.tsx
expect_eq "a page under a public route: WALK=required" "WALK=required" "$(walk_line_for "$work_dir/walk-route")"
expect_contains "WALK=required carries its reason" "walk: public or guest path, walk it as every audience that can reach it, signed out included (src/app/public/orders/page.tsx)" \
  "$(select_gates_output "$work_dir/walk-route")"

# Only the path decides: no text on a changed line does.
make_case "$work_dir/walk-skip" '  skip_before_action :authenticate_user!' app/controllers/pay_controller.rb
expect_eq "an added skip of the authenticate filter in an ordinary controller: WALK=not-required" "WALK=not-required" "$(walk_line_for "$work_dir/walk-skip")"

make_case "$work_dir/walk-flag" '  const canEdit = !isPublic && !locked' src/orders/edit.ts
expect_eq "an added public flag in an ordinary file: WALK=not-required" "WALK=not-required" "$(walk_line_for "$work_dir/walk-flag")"

expect_eq "a model change: WALK=not-required" "WALK=not-required" "$(walk_line_for "$work_dir/model-only")"
expect_eq "a controller with no public path: WALK=not-required" "WALK=not-required" "$(walk_line_for "$work_dir/controller")"

make_case "$work_dir/walk-spec" 'x = 1' src/app/public/orders/page.test.tsx
expect_eq "a test under a public route: WALK=not-required" "WALK=not-required" "$(walk_line_for "$work_dir/walk-spec")"

make_case "$work_dir/walk-asset" 'x' public/images/logo.svg
expect_eq "a static asset under public/: WALK=not-required" "WALK=not-required" "$(walk_line_for "$work_dir/walk-asset")"

make_case "$work_dir/walk-docs" 'An anonymous visitor hits skip_before_action :authenticate and sees isPublic pages.' docs/auth.md
expect_eq "a markdown file naming public flags: WALK=not-required" "WALK=not-required" "$(walk_line_for "$work_dir/walk-docs")"

make_case "$work_dir/walk-script" '# anonymous: skip_before_action :authenticate, isPublic, guest_token' scripts/check-flags.sh
expect_eq "a shell script whose text holds the old patterns: WALK=not-required" "WALK=not-required" "$(walk_line_for "$work_dir/walk-script")"

make_case "$work_dir/walk-controller" '  def show; end' app/controllers/public/orders_controller.rb
expect_eq "a controller under public/: WALK=required" "WALK=required" "$(walk_line_for "$work_dir/walk-controller")"
make_case "$work_dir/walk-routes" 'get "/orders"' config/routes.rb
expect_eq "a route file: WALK=required" "WALK=required" "$(walk_line_for "$work_dir/walk-routes")"

make_case "$work_dir/walk-vue" '  const isPublic = route.meta.open' src/pages/OrderPage.vue
expect_eq "a .vue page with a public flag but no public path: WALK=not-required" "WALK=not-required" "$(walk_line_for "$work_dir/walk-vue")"

make_case "$work_dir/walk-declared" 'x = 1' src/share/view.ts
expect_eq "a path no list names: WALK=not-required" "WALK=not-required" "$(walk_line_for "$work_dir/walk-declared")"
mkdir -p "$work_dir/walk-declared/repo/.claude"
printf '# shared links are open\n(^|/)share/\n' > "$work_dir/walk-declared/repo/.claude/public-paths.txt"
expect_eq "a path in .claude/public-paths.txt: WALK=required" "WALK=required" "$(walk_line_for "$work_dir/walk-declared")"
expect_contains "the declared path is the reason" "(src/share/view.ts)" "$(select_gates_output "$work_dir/walk-declared")"

# select-gates and pass-size.sh decide "public path" with the same function.
pass_size="$(dirname "$tests_dir")/scripts/pass-size.sh"
for walk_case in walk-route walk-skip walk-flag model-only walk-spec walk-asset walk-docs walk-script walk-controller walk-routes walk-vue walk-declared; do
  walk_verdict=$(walk_line_for "$work_dir/$walk_case")
  risk_verdict=$(bash "$pass_size" "$work_dir/$walk_case/review.diff" "$work_dir/$walk_case/changed-files.txt" "$work_dir/$walk_case/repo" | grep -c '^risk: public or guest path' || true)
  if [ "$walk_verdict" = "WALK=required" ]; then expected_risk=1; else expected_risk=0; fi
  expect_eq "$walk_case: WALK agrees with pass-size.sh's public-path risk" "$expected_risk" "$risk_verdict"
done

# A diff that only removes lines has no added line to read; select-gates still prints its gates.
mkdir -p "$work_dir/removal/repo"
printf 'app/models/order.rb\n' > "$work_dir/removal/changed-files.txt"
printf -- '--- a/app/models/order.rb\n+++ b/app/models/order.rb\n@@ -1 +0,0 @@\n-  def total = 0\n' > "$work_dir/removal/review.diff"
expect_eq "a diff with no added line still selects its gates" \
  "GATES=naming,clarity,structure,simplicity,rails,testing,correctness" "$(gates_for "$work_dir/removal")"

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
