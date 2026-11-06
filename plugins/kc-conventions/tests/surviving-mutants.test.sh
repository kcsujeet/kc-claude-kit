#!/usr/bin/env bash
# Tests skills/kc-testing/scripts/surviving-mutants.sh against throwaway git repos: the mutants it
# makes for each language, a mutant the tests catch, an unviable one, a timeout, the time budget,
# a flaky or broken baseline, a diff that isn't HEAD's, the setup command, usage errors, and that
# the repo's own working tree is never touched, even when the run is killed.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
script="$(dirname "$tests_dir")/skills/kc-testing/scripts/surviving-mutants.sh"
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

commit_all() { git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@example.com commit -q -m "$2"; }

# Makes repo <name> with a first commit, then commits the files written by the caller under
# $work_dir/<name>-files, and saves the diff between the two as $work_dir/<name>.diff.
make_repo() {
  local name=$1 repo="$work_dir/$1"
  git init -q "$repo"
  echo "# shop-kit" > "$repo/README.md"
  commit_all "$repo" base
  cp -R "$work_dir/$name-files/." "$repo/"
  commit_all "$repo" change
  git -C "$repo" diff --no-color --src-prefix=a/ --dst-prefix=b/ HEAD~1...HEAD > "$work_dir/$name.diff"
}

# Runs the script in repo <name> with the remaining arguments; prints its output, then `exit <n>`.
run_in() {
  local name=$1 status=0
  shift
  (cd "$work_dir/$name" && bash "$script" "$work_dir/$name.diff" "$@") || status=$?
  echo "exit $status"
}

# One file per language, and a test file whose condition must not be mutated.
mkdir -p "$work_dir/probe-files/src"
cat > "$work_dir/probe-files/src/order.ts" <<'EOF'
export function orderLabel(total: number, limit: number, isPaid: boolean, label: string) {
  if (total === limit && isPaid) return 'full'
  if (total !== limit || !isPaid) return 'open'
  if (total <= limit) return 'within'
  const note = "a && b inside a string"
  return total > limit ? label : note
}
// a comment with && in it
export const ORDER_ID = /^ord_\w+$/
EOF
cat > "$work_dir/probe-files/src/order.sh" <<'EOF'
check_order() {
  [ -n "$1" ] || return 1
  if [ "$1" -lt 3 ]; then echo small; fi
  if [ ! -f "$1" ] && [ "$1" != none ]; then echo missing; fi
  return 0
}
EOF
cat > "$work_dir/probe-files/src/order.py" <<'EOF'
def is_open(paid, shipped):
    if paid and not shipped:
        return True
EOF
cat > "$work_dir/probe-files/src/order.rb" <<'EOF'
def order_state(order)
  return :none unless order
end
EOF
cat > "$work_dir/probe-files/src/order.test.ts" <<'EOF'
if (isPaid && isShipped) expect(state).toBe('done')
EOF
make_repo probe
cp "$work_dir/probe/src/order.ts" "$work_dir/order.ts.before"

expect_eq "every mutant of each language survives tests that check nothing" \
"mutation: 31 mutants on 11 lines: 0 caught (0 timed out), 0 unviable, 31 survived, 0 lines not mutated; baseline runs: 1, slowest 0s; test: true
src/order.py:2: \`and\` to \`or\`:     if paid and not shipped:
src/order.py:2: \`not\` removed:     if paid and not shipped:
src/order.py:3: \`True\` to \`False\`:         return True
src/order.rb:2: \`unless\` to \`if\`:   return :none unless order
src/order.rb:2: line deleted:   return :none unless order
src/order.sh:2: \`||\` to \`&&\`:   [ -n \"\$1\" ] || return 1
src/order.sh:2: \`-n\` to \`-z\`:   [ -n \"\$1\" ] || return 1
src/order.sh:2: line deleted:   [ -n \"\$1\" ] || return 1
src/order.sh:3: \`-lt\` to \`-ge\`:   if [ \"\$1\" -lt 3 ]; then echo small; fi
src/order.sh:4: \`&&\` to \`||\`:   if [ ! -f \"\$1\" ] && [ \"\$1\" != none ]; then echo missing; fi
src/order.sh:4: \`!=\` to \`=\`:   if [ ! -f \"\$1\" ] && [ \"\$1\" != none ]; then echo missing; fi
src/order.sh:4: \`!\` removed:   if [ ! -f \"\$1\" ] && [ \"\$1\" != none ]; then echo missing; fi
src/order.ts:2: \`&&\` to \`||\`:   if (total === limit && isPaid) return 'full'
src/order.ts:2: \`===\` to \`!==\`:   if (total === limit && isPaid) return 'full'
src/order.ts:2: left of \`&&\` dropped:   if (total === limit && isPaid) return 'full'
src/order.ts:2: right of \`&&\` dropped:   if (total === limit && isPaid) return 'full'
src/order.ts:2: line deleted:   if (total === limit && isPaid) return 'full'
src/order.ts:3: \`||\` to \`&&\`:   if (total !== limit || !isPaid) return 'open'
src/order.ts:3: \`!==\` to \`===\`:   if (total !== limit || !isPaid) return 'open'
src/order.ts:3: \`!\` removed:   if (total !== limit || !isPaid) return 'open'
src/order.ts:3: left of \`||\` dropped:   if (total !== limit || !isPaid) return 'open'
src/order.ts:3: right of \`||\` dropped:   if (total !== limit || !isPaid) return 'open'
src/order.ts:3: line deleted:   if (total !== limit || !isPaid) return 'open'
src/order.ts:4: \`<=\` to \`<\`:   if (total <= limit) return 'within'
src/order.ts:4: line deleted:   if (total <= limit) return 'within'
src/order.ts:6: \`>\` to \`>=\`:   return total > limit ? label : note
src/order.ts:6: ternary forced to its first branch:   return total > limit ? label : note
src/order.ts:6: ternary forced to its second branch:   return total > limit ? label : note
src/order.ts:9: regex \`^\` removed: export const ORDER_ID = /^ord_\\w+\$/
src/order.ts:9: regex \`\$\` removed: export const ORDER_ID = /^ord_\\w+\$/
src/order.ts:9: regex \`\\w\` widened to \`.\`: export const ORDER_ID = /^ord_\\w+\$/
exit 0" "$(run_in probe --test true --runs 1)"

expect_eq "--paths mutates only the files it matches" \
  "mutation: 7 mutants on 3 lines: 0 caught (0 timed out), 0 unviable, 7 survived, 0 lines not mutated" \
  "$(run_in probe --test true --runs 1 --paths '\.sh$' | sed -n 1p | sed 's/; baseline.*//')"

caught=$(run_in probe --runs 1 --test '! grep -qF "if (total !== limit && isPaid)" src/order.ts && grep -qF "|| return 1" src/order.sh')
expect_eq "a mutant whose text the tests reject is caught, and only that one" \
  "mutation: 31 mutants on 11 lines: 3 caught (0 timed out), 0 unviable, 28 survived, 0 lines not mutated" \
  "$(printf '%s\n' "$caught" | sed -n 1p | sed 's/; baseline.*//')"
caught_lines='order\.ts:2: .===.|order\.sh:2: (.\|\|.|line deleted)'
expect_eq "the caught mutants are not listed" "" "$(printf '%s\n' "$caught" | grep -E "$caught_lines" || true)"

expect_eq "the repo's own working tree is untouched" "" "$(git -C "$work_dir/probe" status --porcelain)"
expect_eq "the mutated file in the repo is the committed one" "same" \
  "$(cmp -s "$work_dir/probe/src/order.ts" "$work_dir/order.ts.before" && echo same || echo changed)"
expect_eq "no worktree is left registered" "1" "$(git -C "$work_dir/probe" worktree list | wc -l | tr -d ' ')"

# A value fallback whose order matters, one of `??`, a boolean `||` whose order doesn't, and an
# optional element read (`?.[0]`), which is neither dropped nor swapped since it isn't a plain read.
# Nor is a negated read, a literal, or a pair with one boolean side swapped.
mkdir -p "$work_dir/fallback-files/src"
cat > "$work_dir/fallback-files/src/sender.ts" <<'EOF'
export const senderEmail = (user) => user?.sender?.email || user?.email
export const shippingName = (order) => order.shipping.name ?? order.billing.name
export const isSettled = (order) => order.isPaid || order.isRefunded
export const firstTag = (order) => order.note || order.tags?.[0]
export const hasNote = (order) => !order.note.text || order.title.text
export const noteText = (order) => order.note.text || 'none'
export const giftFlag = (order) => order.isGift || order.gift.enabled
EOF
make_repo fallback
expect_eq "a value fallback's sides are swapped, and its operands drop whole across \`?.\`" \
"mutation: 19 mutants on 7 lines: 0 caught (0 timed out), 0 unviable, 19 survived, 0 lines not mutated; baseline runs: 1, slowest 0s; test: true
src/sender.ts:1: \`||\` to \`&&\`: export const senderEmail = (user) => user?.sender?.email || user?.email
src/sender.ts:1: left of \`||\` dropped: export const senderEmail = (user) => user?.sender?.email || user?.email
src/sender.ts:1: right of \`||\` dropped: export const senderEmail = (user) => user?.sender?.email || user?.email
src/sender.ts:1: sides of \`||\` swapped: export const senderEmail = (user) => user?.sender?.email || user?.email
src/sender.ts:2: sides of \`??\` swapped: export const shippingName = (order) => order.shipping.name ?? order.billing.name
src/sender.ts:3: \`||\` to \`&&\`: export const isSettled = (order) => order.isPaid || order.isRefunded
src/sender.ts:3: left of \`||\` dropped: export const isSettled = (order) => order.isPaid || order.isRefunded
src/sender.ts:3: right of \`||\` dropped: export const isSettled = (order) => order.isPaid || order.isRefunded
src/sender.ts:4: \`||\` to \`&&\`: export const firstTag = (order) => order.note || order.tags?.[0]
src/sender.ts:4: left of \`||\` dropped: export const firstTag = (order) => order.note || order.tags?.[0]
src/sender.ts:5: \`||\` to \`&&\`: export const hasNote = (order) => !order.note.text || order.title.text
src/sender.ts:5: \`!\` removed: export const hasNote = (order) => !order.note.text || order.title.text
src/sender.ts:5: left of \`||\` dropped: export const hasNote = (order) => !order.note.text || order.title.text
src/sender.ts:5: right of \`||\` dropped: export const hasNote = (order) => !order.note.text || order.title.text
src/sender.ts:6: \`||\` to \`&&\`: export const noteText = (order) => order.note.text || 'none'
src/sender.ts:6: left of \`||\` dropped: export const noteText = (order) => order.note.text || 'none'
src/sender.ts:7: \`||\` to \`&&\`: export const giftFlag = (order) => order.isGift || order.gift.enabled
src/sender.ts:7: left of \`||\` dropped: export const giftFlag = (order) => order.isGift || order.gift.enabled
src/sender.ts:7: right of \`||\` dropped: export const giftFlag = (order) => order.isGift || order.gift.enabled
exit 0" "$(run_in fallback --test true --runs 1)"
# A test that only ever sets one side (the login address empty, a sending address set) passes
# with the sides swapped; one that sets both and expects the sending address catches it.
one_sided='grep -qF "user?.sender?.email" src/sender.ts && grep -qF "user?.email" src/sender.ts'
expect_eq "the swap survives a test that can't tell the order" \
  "src/sender.ts:1: sides of \`||\` swapped" \
  "$(run_in fallback --runs 1 --paths 'sender' --test "$one_sided" | grep -oF "src/sender.ts:1: sides of \`||\` swapped" || true)"
both_set='! grep -qF "user?.email || user?.sender?.email" src/sender.ts && ! grep -qF "order.billing.name ?? order.shipping.name" src/sender.ts'
expect_eq "each swap writes the other side first, so a test that rejects that order catches both" \
  "mutation: 19 mutants on 7 lines: 2 caught" \
  "$(run_in fallback --runs 1 --test "$both_set" | sed -n 1p | sed "s/ (0 timed out).*//")"

mkdir -p "$work_dir/unviable-files"
cat > "$work_dir/unviable-files/input.sh" <<'EOF'
check_input() {
  if [ -z "$1" ]; then return 1
  fi
}
EOF
make_repo unviable
expect_eq "a mutant that no longer parses is unviable, not run" \
  "mutation: 2 mutants on 1 lines: 0 caught (0 timed out), 1 unviable, 1 survived, 0 lines not mutated" \
  "$(run_in unviable --test true --runs 1 | sed -n 1p | sed 's/; baseline.*//')"

mkdir -p "$work_dir/hang-files"
cat > "$work_dir/hang-files/stock.sh" <<'EOF'
wait_for_stock() {
  while false; do :; done
}
EOF
make_repo hang
expect_eq "a mutant that hangs is killed at the deadline and counts as caught" \
  "mutation: 1 mutants on 1 lines: 1 caught (1 timed out), 0 unviable, 0 survived, 0 lines not mutated
exit 0" \
  "$(run_in hang --runs 1 --test '. ./stock.sh && wait_for_stock' | sed 's/; baseline.*//')"

mkdir -p "$work_dir/budget-files"
cat > "$work_dir/budget-files/limits.sh" <<'EOF'
if [ "$1" -lt 1 ]; then :; fi
if [ "$1" -gt 9 ]; then :; fi
EOF
make_repo budget
expect_eq "lines the time budget doesn't reach are listed, not dropped" \
  "mutation: 1 mutants on 1 lines: 0 caught (0 timed out), 0 unviable, 1 survived, 1 lines not mutated
limits.sh:1: \`-lt\` to \`-ge\`: if [ \"\$1\" -lt 1 ]; then :; fi
limits.sh:2: not mutated (time budget): if [ \"\$1\" -gt 9 ]; then :; fi
exit 0" \
  "$(cd "$work_dir/budget" && { KC_MUTANTS_BUDGET_SECONDS=5 bash "$script" "$work_dir/budget.diff" --runs 1 --test 'sleep 3'; echo "exit $?"; } | sed 's/; baseline.*//')"

expect_eq "a broken baseline stops the run" \
  "mutation: not run: the tests failed 2 of 2 baseline runs; test: exit 1" \
  "$(run_in probe --runs 2 --test 'exit 1' | sed -n 1p)"
flip='if [ -f .ran ]; then rm .ran; exit 1; fi; touch .ran'
expect_eq "a flaky baseline stops the run, with exit 1" \
  "mutation: not run: the tests failed 1 of 3 baseline runs; test: $flip
exit 1" \
  "$(run_in probe --runs 3 --test "$flip" | sed -n '1p;$p')"

sed 's/total <= limit/total < limit/' "$work_dir/probe.diff" > "$work_dir/stale.diff"
expect_eq "a diff that isn't of HEAD stops the run before any mutant" \
  "mutation: not run: the diff does not match HEAD at src/order.ts:4; test: true
exit 1" \
  "$(cd "$work_dir/probe" && { bash "$script" "$work_dir/stale.diff" --test true --runs 1; echo "exit $?"; })"

expect_eq "the setup command runs in the throwaway checkout first" "0" \
  "$(run_in probe --runs 1 --setup 'touch .ready' --test 'test -f .ready' | tail -n 1 | sed 's/exit //')"
expect_eq "without it, the same tests fail the baseline" "1" \
  "$(run_in probe --runs 1 --test 'test -f .ready' | tail -n 1 | sed 's/exit //')"
expect_eq "and the setup left nothing in the repo" "" "$(git -C "$work_dir/probe" status --porcelain)"

mkdir -p "$work_dir/not-a-repo"
expect_eq "outside a git work tree it doesn't run" \
  "mutation: not run: not inside a git work tree; test: true
exit 1" \
  "$(cd "$work_dir/not-a-repo" && { GIT_CEILING_DIRECTORIES=$work_dir bash "$script" "$work_dir/probe.diff" --test true; echo "exit $?"; })"

for args in "--runs 1" "--test true --runs 0" "--test true --max-minutes x" "--test true --colour" "--test"; do
  # shellcheck disable=SC2086  # each case is a list of words
  expect_eq "usage error: $args" "exit 2" "$(run_in probe $args 2>/dev/null | tail -n 1)"
done
expect_eq "usage error: the diff read from stdin" "2" \
  "$(cd "$work_dir/probe" && { bash "$script" - --test true 2>/dev/null; echo "$?"; })"

# A test command that leaves a process running from the checkout in a process group of its own
# (a server it started, as Playwright's web server does) gets it stopped after each run, so the
# next run can't reuse it.
stray_marker="$work_dir/stray-tree"
run_in budget --runs 1 --test "pwd > '$stray_marker'; set -m; (exec -a \"\$(pwd)/stray-server\" sleep 60) & true" > /dev/null
expect_eq "a process the tests left running from the checkout is stopped" "" \
  "$(pgrep -f "$(cat "$stray_marker")/stray-server" || true)"

# Killed mid-run, while a mutant's tests run: the repo's own tree is untouched either way. TERM
# also removes the throwaway worktree; KILL can't be trapped, so it leaves one, outside the repo.
for signal in TERM KILL; do
  (cd "$work_dir/probe" && exec bash "$script" "$work_dir/probe.diff" --runs 1 --test 'sleep 1') > /dev/null 2>&1 &
  run_pid=$!
  sleep 2
  kill "-$signal" "$run_pid" 2>/dev/null || true
  wait "$run_pid" 2>/dev/null || true
  expect_eq "killed with $signal mid-run: the repo's tree is untouched" "" "$(git -C "$work_dir/probe" status --porcelain)"
  expect_eq "killed with $signal mid-run: the mutated file in the repo is the committed one" "same" \
    "$(cmp -s "$work_dir/probe/src/order.ts" "$work_dir/order.ts.before" && echo same || echo changed)"
  if [ "$signal" = TERM ]; then
    expect_eq "killed with TERM: its worktree was removed" "1" "$(git -C "$work_dir/probe" worktree list | wc -l | tr -d ' ')"
  fi
done
git -C "$work_dir/probe" worktree list --porcelain | sed -n 's/^worktree //p' | grep '/kc-mutants\.' |
  while IFS= read -r stale_tree; do
    git -C "$work_dir/probe" worktree remove --force "$stale_tree"
    rm -rf "$(dirname "$stale_tree")"
  done

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
