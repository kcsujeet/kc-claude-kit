#!/usr/bin/env bash
# Tests scripts/verify-gate-blocks.sh: the mechanical half of the verification gate. Each case saves
# a round folder (review.diff, changed-files.txt, meta.env, verdicts/) for a real commit in a scratch
# repo and expects the problem lines, one per fault, or the passing verification block.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
verify="$scripts/verify-gate-blocks.sh"

repo="$work_dir/repo"
run_git() { git -C "$repo" -c user.name=t -c user.email=t@example.test "$@"; }
git init -q -b main "$repo"
mkdir -p "$repo/shop"
printf 'a\nb\nc\nd\ne\n' > "$repo/shop/total.sh"
run_git add -A && run_git commit -q -m base
base=$(run_git rev-parse HEAD)
printf 'f\ng\nh\n' >> "$repo/shop/total.sh"
run_git add -A && run_git commit -q -m change
head=$(run_git rev-parse HEAD)
short=${head:0:7}

# A round folder for base..head with a passing block for each gate select-gates.sh lists, a
# verification block and a SCOPE: block: the good case every other case edits.
build_round() {
  round="$work_dir/round-$RANDOM$RANDOM"
  mkdir -p "$round/verdicts"
  run_git diff --src-prefix=a/ --dst-prefix=b/ "$base" "$head" > "$round/review.diff"
  run_git diff --name-only "$base" "$head" > "$round/changed-files.txt"
  printf 'HEAD_SHA=%s\nBASE=%s\n' "$head" "$base" > "$round/meta.env"
  local gate
  for gate in $(bash "$scripts/select-gates.sh" "$round/review.diff" "$round/changed-files.txt" "$repo" | sed -n 's/^GATES=//p' | tr ',' ' '); do
    printf 'GATE: %s\nSTATUS: PASS\nBOXES:\n- [PASS] §X1: read shop/total.sh:7@%s\nFINDINGS:\n- none\n' "$gate" "$short" > "$round/verdicts/$gate.txt"
  done
  # shellcheck disable=SC2016 # the fence is part of a pasted block.
  printf 'SCOPE:\nBOXES:\n- [N/A] §G1: local diff\n- [PASS] §G2: matches the title\n- [N/A] §G3: no linked issue\n- [N/A] §G4: read whole\n- [PASS] §G5: weighed one script\n' > "$round/verdicts/scope.txt"
}

last_output=""
last_status=0
run_verify() {
  last_status=0
  last_output=$(bash "$verify" "$@" 2>&1) || last_status=$?
}
expect_clean() {
  run_verify "$round" "$repo"
  expect_eq "$1" 0 "$last_status"
}
expect_problem() {
  local label=$1 needle=$2
  shift 2
  run_verify "$@" "$round" "$repo"
  expect_eq "$label: exits 1" 1 "$last_status"
  expect_contains "$label: says" "$needle" "$last_output"
}
# Overwrites a gate's verdict file with the given text (\n escapes expanded).
set_gate() { printf '%b' "$2" > "$round/verdicts/$1.txt"; }

build_round
expect_clean "a complete round passes"
expect_contains "it prints a verification block" "GATE: verification" "$last_output"
expect_contains "its status is PASS" "STATUS: PASS" "$last_output"
expect_contains "it counts the resolved citations" "1 citation(s) path:line@sha, every one resolves at head $short" "$last_output"
expect_contains "it says what it did not judge" "SOURCE: verify-gate-blocks.sh" "$last_output"

# The passing block is the verification record: it is not read back as a gate block, and the
# receipt's shape check (GATE:, STATUS:, a box with evidence) accepts it.
printf '%s\n' "$last_output" > "$round/verdicts/verification.txt"
expect_clean "its own earlier output in verdicts/ is not read back"

# --- citations ---------------------------------------------------------------
build_round
set_gate naming "GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N1: read shop/total.sh:7@1234567\nFINDINGS:\n- none\n"
expect_problem "§V12: a citation with another sha" "sha 1234567 is not the head $short" 
build_round
set_gate naming "GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N1: read total.sh:7@$short\nFINDINGS:\n- none\n"
run_verify "$round" "$repo"
expect_eq "§V12: a bare file name: exits 1" 1 "$last_status"
expect_problem "a bare file name is told where the file is" "total.sh does not exist at the head" 
expect_contains "the hint names the repo path" "(cite the repo path: shop/total.sh)" "$last_output"
build_round
set_gate naming "GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N1: read shop/total.sh:99@$short\nFINDINGS:\n- none\n"
expect_problem "§V12: a line past the end of the file" "line 99 is not in shop/total.sh at the head (it has 8)"

# --- sweeps ------------------------------------------------------------------
build_round
set_gate clarity "GATE: clarity\nSTATUS: PASS\nBOXES:\n- [PASS] §C1: grepped ternaries: 3 hits: shop/total.sh:6 ok, shop/total.sh:7 ok\nFINDINGS:\n- none\n"
expect_problem "3 hits with 2 verdicts" "§C1: \"grepped ternaries: 3 hits\" has 2 per-hit verdict(s)"
set_gate clarity "GATE: clarity\nSTATUS: PASS\nBOXES:\n- [PASS] §C1: grepped ternaries: 3 hits: shop/total.sh:6 ok, shop/total.sh:7 ok, shop/total.sh:8 ok\nFINDINGS:\n- none\n"
expect_clean "3 hits with 3 verdicts passes"
set_gate clarity "GATE: clarity\nSTATUS: PASS\nBOXES:\n- [PASS] §C1: grepped ternaries: 3 hits\n    shop/total.sh:6 ok\n    shop/total.sh:7 ok\n    shop/total.sh:8 ok\nFINDINGS:\n- none\n"
expect_clean "per-hit verdicts on indented lines under the box count"
set_gate clarity "GATE: clarity\nSTATUS: PASS\nBOXES:\n- [PASS] §C1: grepped ternaries: 0 hits\nFINDINGS:\n- none\n"
expect_clean "0 hits needs no verdicts"
set_gate clarity "GATE: clarity\nSTATUS: PASS\nBOXES:\n- [PASS] §C1: grepped ternaries: 1 hit: shop/total.sh:6 ok; grepped as-casts: 2 hits: shop/total.sh:7 ok\nFINDINGS:\n- none\n"
expect_problem "each sweep in a box is counted on its own" "\"grepped as-casts: 2 hits\" has 1 per-hit verdict(s)"
set_gate clarity "GATE: clarity\nSTATUS: PASS\nBOXES:\n- [PASS] §C1: grepped ternaries: 3 hits: shared/reproduce-commands:2 ok, bin/setup:4 ok, shop/Makefile:L1 ok\nFINDINGS:\n- none\n"
expect_clean "per-hit verdicts citing extensionless files with a directory count"
set_gate clarity "GATE: clarity\nSTATUS: PASS\nBOXES:\n- [PASS] §C1: grepped ternaries: 2 hits: hits:3 ok, count:4 ok\nFINDINGS:\n- none\n"
expect_problem "a plain word and a number is not a citation" "has 0 per-hit verdict(s)"
set_gate clarity "GATE: clarity\nSTATUS: PASS\nBOXES:\n- [PASS] §C1: grepped ternaries: 2 hits: shop/total.sh:6 ok, shop/total.sh:6 ok\nFINDINGS:\n- none\n"
expect_problem "one location twice is one verdict" "has 1 per-hit verdict(s)"

# --- boxes that contradict themselves ----------------------------------------
build_round
set_gate naming "GATE: naming\nSTATUS: FAIL\nBOXES:\n- [FAIL] §N1: PASS, every name reads as its role\nFINDINGS:\n- none\n"
expect_problem "a FAIL box whose text says PASS" "§N1 is marked FAIL but its text says PASS"
set_gate naming "GATE: naming\nSTATUS: FAIL\nBOXES:\n- [FAIL] §N1: N/A, no new names\nFINDINGS:\n- none\n"
expect_problem "a FAIL box whose text says N/A" "§N1 is marked FAIL but its text says N/A"
set_gate naming "GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N1: FAIL, a name hides its role\nFINDINGS:\n- none\n"
expect_problem "a PASS box whose text says FAIL" "§N1 is marked PASS but its text says FAIL"
set_gate naming "GATE: naming\nSTATUS: FAIL\nBOXES:\n- [FAIL] §N1: shop/total.sh:7 a name is unclear, but PASS elsewhere\nFINDINGS:\n- none\n"
expect_clean "PASS in the middle of a FAIL box's text is not a contradiction"

# --- STATUS against boxes ----------------------------------------------------
build_round
set_gate naming "GATE: naming\nSTATUS: PASS\nBOXES:\n- [FAIL] §N1: shop/total.sh:7 unclear\n- [PASS] §N2: fine\nFINDINGS:\n- x\n"
expect_problem "STATUS: PASS with a FAIL box" "GATE: naming says STATUS: PASS but 1 box(es) are FAIL (§N1)"
set_gate naming "GATE: naming\nSTATUS: FAIL\nBOXES:\n- [PASS] §N1: fine\nFINDINGS:\n- none\n"
expect_problem "STATUS: FAIL with no FAIL box" "GATE: naming says STATUS: FAIL but no box is FAIL"
set_gate naming "GATE: naming\nSTATUS: PASS (N/A)\nBOXES:\n- [PASS] §N1: fine\nFINDINGS:\n- none\n"
expect_problem "STATUS: PASS (N/A) with a PASS box" "GATE: naming says STATUS: PASS (N/A) but a box is not N/A"
set_gate naming "GATE: naming\nSTATUS: PASS (N/A)\nBOXES:\n- [N/A] §N1: no names added\nFINDINGS:\n- none\n"
expect_clean "STATUS: PASS (N/A) with only N/A boxes passes"
set_gate naming "GATE: naming\nBOXES:\n- [PASS] §N1: fine\nFINDINGS:\n- none\n"
expect_problem "no STATUS line" "GATE: naming has no STATUS: line"

# --- gate blocks and SCOPE ---------------------------------------------------
build_round
rm "$round/verdicts/testing.txt"
expect_problem "a listed gate with no block" "verdicts/: no GATE: testing block"
build_round
rm "$round/verdicts/scope.txt"
expect_problem "no SCOPE block" "verdicts/: no SCOPE: block"
build_round
sed '/§G3/d' "$round/verdicts/scope.txt" > "$work_dir/scope.tmp" && mv "$work_dir/scope.tmp" "$round/verdicts/scope.txt"
expect_problem "a SCOPE block without §G3" "SCOPE: marks §G3 0 time(s)"
build_round
printf -- '- [PASS] §G2: again\n' >> "$round/verdicts/scope.txt"
expect_problem "§G2 marked twice" "SCOPE: marks §G2 2 time(s)"
build_round
# shellcheck disable=SC2016 # the fence is part of a pasted block.
printf '```\nGATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N1: fine\nFINDINGS:\n- none\n```\n' > "$round/verdicts/naming.txt"
expect_clean "a block pasted inside a code fence is read"

# One run lists every problem, not the first.
build_round
rm "$round/verdicts/testing.txt" "$round/verdicts/scope.txt"
set_gate naming "GATE: naming\nSTATUS: PASS\nBOXES:\n- [FAIL] §N1: PASS\nFINDINGS:\n- none\n"
set_gate clarity "GATE: clarity\nSTATUS: PASS\nBOXES:\n- [PASS] §C1: grepped ternaries: 4 hits: shop/total.sh:6@abcdef0\nFINDINGS:\n- none\n"
run_verify "$round" "$repo"
expect_eq "several problems: one line each" 6 "$(printf '%s\n' "$last_output" | grep -c .)"
expect_contains "several problems: the missing gate" "no GATE: testing block" "$last_output"
expect_contains "several problems: the missing scope" "no SCOPE: block" "$last_output"
expect_contains "several problems: the contradiction and the status" "says STATUS: PASS but 1 box(es) are FAIL" "$last_output"
expect_contains "several problems: the sweep" "has 1 per-hit verdict(s)" "$last_output"
expect_contains "several problems: the citation" "sha abcdef0 is not the head" "$last_output"

# --- layout asserted by reasoning ---------------------------------------------
build_round
set_gate react "GATE: react\nSTATUS: PASS\nBOXES:\n- [PASS] §R19: layout fine at 1920, estimated by calculation: 20cqw leaves 384px\nFINDINGS:\n- none\n"
expect_problem "a layout box passed by calculation" "§R19 states behaviour it did not run or measure (\"estimated\")"
expect_contains "it tells the gate to run or measure it" "run or measure it" "$last_output"
set_gate react "GATE: react\nSTATUS: PASS\nBOXES:\n- [PASS] §R19: the card should render without overflow on narrow screens\nFINDINGS:\n- none\n"
expect_problem "a layout box that says should render" "states behaviour it did not run or measure"
set_gate react "GATE: react\nSTATUS: PASS\nBOXES:\n- [PASS] §R19: estimated column width 41px at 375\nFINDINGS:\n- none\n"
expect_problem "an estimated width" "states behaviour it did not run or measure (\"estimated\")"
set_gate react "GATE: react\nSTATUS: PASS\nBOXES:\n- [PASS] §R19: it would fit, see captures/wide-1920.png\nFINDINGS:\n- none\n"
expect_clean "reasoning words beside a screenshot path pass"
set_gate react "GATE: react\nSTATUS: PASS\nBOXES:\n- [PASS] §R19: should render fine; measured 412px wide at 1920\nFINDINGS:\n- none\n"
expect_clean "reasoning words beside a measured value pass"
set_gate react "GATE: react\nSTATUS: FAIL\nBOXES:\n- [FAIL] §R19: estimated width is wrong, would overflow\nFINDINGS:\n- x\n"
expect_clean "a FAIL box is not held to it"
set_gate react "GATE: react\nSTATUS: PASS\nBOXES:\n- [PASS] §R1: estimated delivery date is shown by the order page\nFINDINGS:\n- none\n"
expect_clean "estimated with no layout word is not a layout claim"
set_gate testing "GATE: testing\nSTATUS: PASS\nBOXES:\n- [PASS] §T1: the empty state will display a notice; read shop/total.sh:7@$short\nFINDINGS:\n- none\n"
expect_problem "any gate's box that says what will display, with nothing run" "(\"will display\")"
set_gate testing "GATE: testing\nSTATUS: PASS\nBOXES:\n- [PASS] §T1: the page should load in 40ms; 12 passed\nFINDINGS:\n- none\n"
expect_clean "a behaviour claim beside a passed-test count passes"
set_gate testing "GATE: testing\nSTATUS: PASS\nBOXES:\n- [PASS] §T1: the page should load; exit 0\nFINDINGS:\n- none\n"
expect_clean "a behaviour claim beside exit 0 passes"
set_gate testing "GATE: testing\nSTATUS: PASS\nBOXES:\n- [PASS] §T1: the page would load quickly; GET /cart 200\nFINDINGS:\n- none\n"
expect_clean "a behaviour claim beside a request line passes"
set_gate testing "GATE: testing\nSTATUS: PASS\nBOXES:\n- [PASS] §T1: the response time is estimated at 40ms from the query count\nFINDINGS:\n- none\n"
expect_problem "an estimated response time is behaviour not measured" "(\"estimated\")"
set_gate react "GATE: react\nSTATUS: PASS\nBOXES:\n- [PASS] §R19: column width computed by hand is 41px\nFINDINGS:\n- none\n"
expect_problem "a layout box computed by hand" "(\"computed by hand\")"
set_gate react "GATE: react\nSTATUS: PASS\nBOXES:\n- [PASS] §R19: the header wouldn't overflow on paper\nFINDINGS:\n- none\n"
expect_problem "a layout box that holds on paper" "states behaviour it did not run or measure"
set_gate react "GATE: react\nSTATUS: PASS\nBOXES:\n- [PASS] §R19: in theory the sidebar column stays visible on a narrow screen\nFINDINGS:\n- none\n"
expect_problem "a layout box that holds in theory" "(\"in theory\")"

# --- dense expressions (clarity §C13) -----------------------------------------
# The round's diff is replaced by one adding two dense lines (a call chain, calls nested three deep)
# and a plain one; the gates listed stay the ones the original diff picked.
build_dense_round() {
  build_round
  printf 'diff --git a/shop/total.sh b/shop/total.sh\n--- a/shop/total.sh\n+++ b/shop/total.sh\n@@ -5,0 +6,3 @@\n+names=items.filter(isPaid).map(toName).join(",")\n+price=formatMoney(roundCents(convert(amount, rate)))\n+total=sum(items)\n' > "$round/review.diff"
}
set_dense_clarity_gate() { set_gate clarity "GATE: clarity\nSTATUS: PASS\nBOXES:\n- [PASS] §C13: $1\nFINDINGS:\n- none\n"; }
build_dense_round
set_dense_clarity_gate "grepped dense expressions: 2 hits: shop/total.sh:6 chain kept, shop/total.sh:7 nested kept"
expect_clean "dense expressions: a verdict for each hit passes"
set_dense_clarity_gate "grepped dense expressions: 2 hits: shop/total.sh:L6 chain kept, shop/total.sh:L7 nested kept"
expect_clean "dense expressions: an L-prefixed line number counts"
set_gate clarity "GATE: clarity\nSTATUS: PASS\nBOXES:\n- [PASS] §C13: no dense expression\nFINDINGS:\n- none\n"
expect_problem "dense expressions: hits in the diff and no receipt" "dense-expressions.sh finds 2 hit(s) in review.diff but no \"grepped dense expressions: 2 hits\" receipt"
set_dense_clarity_gate "grepped dense expressions: 0 hits"
expect_problem "dense expressions: a receipt that says 0 when the script finds 2" "\"grepped dense expressions: 0 hits\" but dense-expressions.sh finds 2 in review.diff"
set_dense_clarity_gate "grepped dense expressions: 1 hit: shop/total.sh:6 chain kept"
expect_problem "dense expressions: a receipt that counts one of two" "but dense-expressions.sh finds 2 in review.diff"
set_dense_clarity_gate "grepped dense expressions: 3 hits: shop/total.sh:6 a, shop/total.sh:7 b, shop/total.sh:8 c"
expect_problem "dense expressions: a receipt that counts the plain line too" "but dense-expressions.sh finds 2 in review.diff"
set_dense_clarity_gate "grepped dense expressions: 2 hits: shop/total.sh:6 chain kept, shop/total.sh:8 plain"
expect_problem "dense expressions: two verdicts, one on a line that is not a hit" "dense expression shop/total.sh:7 has no verdict of its own"
set_dense_clarity_gate "grepped dense expressions: 2 hits: shop/total.sh:6 chain kept, shop/total.sh:70 other"
expect_problem "dense expressions: line 70 is not line 7" "dense expression shop/total.sh:7 has no verdict of its own"
# A path with regex characters is matched as written, and only as a whole token.
build_round
printf 'diff --git a/app/(portal)/page.ts b/app/(portal)/page.ts\n--- a/app/(portal)/page.ts\n+++ b/app/(portal)/page.ts\n@@ -0,0 +1,1 @@\n+const names = items.filter(isPaid).map(toName).join(",")\n' > "$round/review.diff"
set_dense_clarity_gate "grepped dense expressions: 1 hit: app/(portal)/page.ts:1 chain kept"
expect_clean "dense expressions: a path with parentheses is matched as written"
set_dense_clarity_gate "grepped dense expressions: 1 hit: lib/app/(portal)/page.ts:1 chain kept"
expect_problem "dense expressions: another file's path ending in the hit's path is not the hit" "dense expression app/(portal)/page.ts:1 has no verdict of its own"

build_dense_round
set_dense_clarity_gate "grepped dense expressions: 2 hits: lib/shop/total.sh:6 first, then shop/total.sh:6 chain kept, shop/total.sh:7 nested kept"
expect_clean "dense expressions: a text whose first candidate fails the whole-token check still finds a later one"

# A kc-conventions without the sweep (an older install) is not held to the receipt.
old_install="$work_dir/old-install"
mkdir -p "$old_install"
cp -R "$(dirname "$scripts")" "$old_install/kc-gates"
cp -R "$(dirname "$scripts")/../kc-conventions" "$old_install/kc-conventions"
rm "$old_install/kc-conventions/skills/kc-clarity/scripts/dense-expressions.sh"
build_dense_round
set_gate clarity "GATE: clarity\nSTATUS: PASS\nBOXES:\n- [PASS] §C13: no dense expression\nFINDINGS:\n- none\n"
last_status=0
last_output=$(bash "$old_install/kc-gates/scripts/verify-gate-blocks.sh" "$round" "$repo" 2>&1) || last_status=$?
expect_eq "dense expressions: an install without the sweep passes a round with hits and no receipt" 0 "$last_status"

build_round
set_dense_clarity_gate "grepped dense expressions: 0 hits"
expect_clean "dense expressions: 0 hits and a diff with none passes"
set_dense_clarity_gate "grepped dense expressions: 1 hit: shop/total.sh:7 chain kept"
expect_problem "dense expressions: a hit counted where the script finds none" "but dense-expressions.sh finds 0 in review.diff"
build_round
expect_clean "dense expressions: no receipt and no hit passes"

# An agent's verification block is read like any gate's.
build_round
set_gate verification "GATE: verification\nSTATUS: PASS\nBOXES:\n- [FAIL] §V3: PASS\nFINDINGS:\n- none\n"
expect_problem "an agent's verification block with a contradiction" "§V3 is marked FAIL but its text says PASS"

# --- a later round -----------------------------------------------------------
# The delta renames one line, so only naming is listed; the receipt lines and walk-items are needed.
printf 'f\ng\nh2\n' > "$repo/shop/total.sh"
run_git add -A && run_git commit -q -m rename
later_head=$(run_git rev-parse HEAD)
build_later() {
  round="$work_dir/later-$RANDOM$RANDOM"
  mkdir -p "$round/verdicts"
  printf 'diff --git a/shop/total.sh b/shop/total.sh\n--- a/shop/total.sh\n+++ b/shop/total.sh\n@@ -6,3 +6,3 @@\n f\n g\n-h\n+h2\n' > "$round/review.diff"
  printf 'shop/total.sh\n' > "$round/changed-files.txt"
  printf 'HEAD_SHA=%s\nBASE=%s\n' "$later_head" "$head" > "$round/meta.env"
  printf 'GATE: naming\nSTATUS: PASS\nBOXES:\n- [PASS] §N1: read shop/total.sh:3@%s\nFINDINGS:\n- none\n' "${later_head:0:7}" > "$round/verdicts/naming.txt"
  printf '2 fixes re-checked\n0 rewrites checked\n1 rename-only lines kept\nWalk: shop/total.sh printed the same total\n' > "$round/verdicts/checklist.txt"
}
build_later
run_verify --later-round "$round" "$repo"
expect_eq "a later round with its lines passes (only naming is listed)" 0 "$last_status"
expect_contains "it records the rename-only count" "1 rename-only lines kept" "$last_output"
expect_not_contains "it asks for no SCOPE block" "SCOPE" "$(printf '%s\n' "$last_output" | sed -n '1,/^FINDINGS/p')"
rm "$round/verdicts/checklist.txt"
expect_problem "a later round with no receipt lines" "no \"<n> fixes re-checked\" line" --later-round
expect_contains "it also asks for rewrites" "no \"<n> rewrites checked\" line" "$last_output"
expect_contains "and rename-only lines" "no \"<n> rename-only lines kept\" line" "$last_output"
expect_contains "and the walk" "walk-item shop/total.sh has no \"Walk:\" line" "$last_output"
build_later
printf '2 fixes re-checked\n0 rewrites checked\n3 rename-only lines kept\nWalk: shop/total.sh printed the same total\n' > "$round/verdicts/checklist.txt"
expect_problem "a rename-only count that is not the script's" "\"3 rename-only lines kept\" but rename-only-lines.sh lists 1" --later-round
build_later
printf '2 fixes re-checked\n0 rewrites checked\n1 rename-only lines kept\n' > "$round/verdicts/checklist.txt"
expect_problem "a walk-item with no Walk: line" "walk-item shop/total.sh has no \"Walk:\" line" --later-round
build_later
expect_problem "round 1's rules on a later round's folder (no flag) ask for a SCOPE block" "no SCOPE: block"

# --- usage -------------------------------------------------------------------
run_verify
expect_eq "usage: no arguments exits 2" 2 "$last_status"
run_verify "$work_dir/none" "$repo"
expect_eq "usage: a missing round folder exits 2" 2 "$last_status"

finish
