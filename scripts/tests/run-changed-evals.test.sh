#!/usr/bin/env bash
# Tests scripts/run-changed-evals.sh in a throwaway repo, with a stand-in `claude` on PATH that
# records its arguments and writes a canned result: only changed cases run, a case passes when it
# passes with the plugin and fails without it, and CI without a key fails instead of skipping.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/run-changed-evals.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
repo=$work/repo
stub_bin=$work/bin
results=$work/results
calls=$work/calls.log
passes=0
failures=0

pass() { echo "ok   $1"; passes=$((passes + 1)); }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

mkdir -p "$stub_bin" "$results"
cat > "$stub_bin/claude" <<'STUB'
#!/usr/bin/env bash
# Stand-in for `claude plugin eval`: logs its arguments and copies $STUB_RESULTS/<case>.json to
# the --json path, when there is one.
printf '%s\n' "$*" >> "$STUB_CALLS"
case_name="" json=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --case) case_name=$2; shift 2 ;;
    --json) json=$2; shift 2 ;;
    *) shift ;;
  esac
done
[ ! -f "$STUB_RESULTS/$case_name.json" ] || cp "$STUB_RESULTS/$case_name.json" "$json"
STUB
chmod +x "$stub_bin/claude"

# Writes a result for <case> whose with-plugin run passes or fails, and whose baseline run passes,
# fails or is missing.
write_result() {
  local case_name=$1 with=$2 without=$3 without_arm
  case "$without" in
    none) without_arm='[]' ;;
    *) without_arm="[{\"error\":null,\"graders\":[{\"name\":\"finds-it\",\"passed\":$without,\"scored\":true}]}]" ;;
  esac
  printf '{"cases":[{"name":"%s","arms":{"with":[{"error":null,"graders":[{"name":"finds-it","passed":%s,"scored":true},{"name":"skill-fired","passed":true,"scored":false}]}],"without":%s}}]}\n' \
    "$case_name" "$with" "$without_arm" > "$results/$case_name.json"
}

# Runs the script on the current branch against main, outside CI unless <env> says otherwise;
# keeps its output and exit status.
last_output="" last_status=0
run_check() {
  : > "$calls"
  last_status=0
  last_output=$(cd "$repo" && env -u GITHUB_ACTIONS -u ANTHROPIC_API_KEY PATH="$stub_bin:$PATH" STUB_CALLS="$calls" STUB_RESULTS="$results" "$@" bash "$script" main 2>/dev/null) || last_status=$?
}

expect_status() {
  local label=$1 expected=$2
  if [ "$last_status" -eq "$expected" ]; then pass "$label"; else fail "$label (exit $last_status, wanted $expected: $last_output)"; fi
}

expect_output() {
  local label=$1 expected_text=$2
  case "$last_output" in
    *"$expected_text"*) pass "$label" ;;
    *) fail "$label (no \"$expected_text\" in: $last_output)" ;;
  esac
}

expect_calls() {
  local label=$1 expected=$2 actual
  actual=$(grep -c . "$calls" || true)
  if [ "$actual" -eq "$expected" ]; then pass "$label"; else fail "$label ($actual eval runs, wanted $expected)"; fi
}

commit_change() {
  git -C "$repo" add -A
  git -C "$repo" -c user.name=t -c user.email=t@example.test commit -q -m "$1"
}
create_branch() { git -C "$repo" checkout -q main && git -C "$repo" checkout -q -b "$1"; }
write_repo_file() { mkdir -p "$(dirname "$repo/$1")" && printf '%b' "$2" > "$repo/$1"; }

git init -q -b main "$repo"
write_repo_file plugins/shop/evals/totals/case.yaml 'name: totals\ntags: [review, positive]\n'
write_repo_file plugins/shop/evals/totals/prompt.md '---\nplugins: ["../.."]\n---\nReview it.\n'
write_repo_file plugins/shop/evals/totals/graders/finds-it.md 'pattern: shipping\n'
write_repo_file plugins/shop/evals/greeting/prompt.md '---\nname: greeting\ntags: [negative]\n---\nSay hi.\n'
write_repo_file plugins/gates/evals/whole-fix/case.yaml 'name: whole-fix\n'
write_repo_file plugins/gates/evals/whole-fix/prompt.md '---\nplugins: ["../..", "../../../shop"]\n---\nReview it.\n'
write_repo_file plugins/shop/skills/checkout/SKILL.md 'A total includes tax.\n'
commit_change base

create_branch no-eval
echo "Include shipping." >> "$repo/plugins/shop/skills/checkout/SKILL.md"
commit_change "a rule, no eval"
run_check
expect_status "no changed case passes" 0
expect_output "it says so" "no eval case changed"
expect_calls "and runs nothing" 0

create_branch results-only
write_repo_file plugins/shop/evals/results/run.json '{}\n'
commit_change "a results file"
run_check
expect_output "the runner's results/ folder is no case" "no eval case changed"

create_branch case-deleted
git -C "$repo" rm -rq plugins/shop/evals/totals
commit_change "a deleted case"
run_check
expect_output "a deleted case has nothing to run" "no eval case changed"

create_branch grader-changed
write_repo_file plugins/shop/evals/totals/graders/finds-it.md 'pattern: shipping|freight\n'
commit_change "a grader edit"
(cd "$repo" && bash "$script" main --list) > "$work/list" 2>/dev/null
if [ "$(cat "$work/list")" = plugins/shop/evals/totals ]; then pass "--list prints the changed case"; else fail "--list prints the changed case (got: $(cat "$work/list"))"; fi
write_result totals true false
run_check GITHUB_ACTIONS=true ANTHROPIC_API_KEY=
expect_status "in CI with no key, a changed case fails" 1
expect_output "it names the missing secret" "no ANTHROPIC_API_KEY secret"
expect_output "it names the case" "plugins/shop/evals/totals"
expect_calls "and runs nothing" 0
run_check GITHUB_ACTIONS=true ANTHROPIC_API_KEY=test-key
expect_status "a case that passes with the plugin and fails without it passes" 0
expect_output "it says both" "passes with the plugin, fails without it"
expect_calls "one eval run" 1
if grep -qE -- '^plugin eval plugins/shop --case totals --runs 1 --ablation with-without ' "$calls"; then
  pass "the run targets the plugin, one run of that case, with the baseline arm"
else
  fail "the run targets the plugin, one run of that case, with the baseline arm (got: $(cat "$calls"))"
fi

write_result totals false false
run_check
expect_status "a case that fails with the plugin fails" 1
expect_output "it names the grader" "with the plugin, graders failed: finds-it"

write_result totals true true
run_check
expect_status "a case that passes without the plugin fails" 1
expect_output "it says why" "passes without the plugin too"

write_result totals true none
run_check
expect_status "a result with no baseline run fails" 1
expect_output "it says so" "no run without the plugin"

rm "$results/totals.json"
run_check
expect_status "a run that writes no result fails" 1
expect_output "it says so" "the eval run wrote no result"

printf '{"cases":[{"name":"totals","arms":{"with":[{"error":"timed out","graders":[]}],"without":[]}}]}\n' > "$results/totals.json"
run_check
expect_status "a run that errors fails" 1
expect_output "it says so" "the run with the plugin errored"

printf '{"cases":[{"name":"totals","arms":{"with":[{"error":null,"graders":[{"name":"finds-it","passed":true,"scored":true}]}],"without":[{"error":"timed out","graders":[{"name":"finds-it","passed":false,"scored":true}]}]}}]}\n' > "$results/totals.json"
run_check
expect_status "an errored baseline run fails" 1
expect_output "it says so" "the run without the plugin errored"

# Without the plugin a skill-fired grader fails by nature; only the scored graders count.
printf '{"cases":[{"name":"totals","arms":{"with":[{"error":null,"graders":[{"name":"finds-it","passed":true,"scored":true}]}],"without":[{"error":null,"graders":[{"name":"finds-it","passed":true,"scored":true},{"name":"skill-fired","passed":false,"scored":false}]}]}}]}\n' > "$results/totals.json"
run_check
expect_status "a baseline that fails only an unscored grader passes the case, so it fails here" 1
expect_output "it says why" "passes without the plugin too"

printf '{"cases":[]}\n' > "$results/totals.json"
run_check
expect_status "a result without the case fails" 1
expect_output "it says so" "its result has no case named totals"

create_branch negative-case
write_repo_file plugins/shop/evals/greeting/prompt.md '---\nname: greeting\ntags: [negative]\n---\nSay hello.\n'
commit_change "a negative case"
write_result greeting true true
run_check
expect_status "a negative case may pass without the plugin" 0
expect_output "it says why" "a negative case"

printf '{"cases":[{"name":"greeting","arms":{"with":[{"error":null,"graders":[]}],"without":[]}}]}\n' > "$results/greeting.json"
run_check
expect_status "a run with no graders fails, negative or not" 1
expect_output "it says so" "has no graders, so it checks nothing"

create_branch beside-another-plugin
write_repo_file plugins/gates/evals/whole-fix/prompt.md '---\nplugins: ["../..", "../../../shop"]\n---\nReview my branch.\n'
commit_change "a case that loads a second plugin"
write_result whole-fix true false
run_check
expect_status "a case loading a second plugin runs" 0
if grep -qE -- '^plugin eval \. --eval-dir plugins/gates/evals --case whole-fix ' "$calls"; then
  pass "it runs from the repo root with --eval-dir"
else
  fail "it runs from the repo root with --eval-dir (got: $(cat "$calls"))"
fi

create_branch two-cases
write_repo_file plugins/shop/evals/totals/graders/finds-it.md 'pattern: freight\n'
write_repo_file plugins/gates/evals/whole-fix/prompt.md '---\nplugins: ["../..", "../../../shop"]\n---\nReview this branch.\n'
commit_change "two cases"
write_result totals true false
write_result whole-fix false false
run_check
expect_status "one failing case fails the run" 1
expect_calls "each changed case runs once" 2
expect_output "the passing case is reported" "ok   plugins/shop/evals/totals"
expect_output "the failing case is reported" "FAIL plugins/gates/evals/whole-fix"

# The base moving on after the branch was cut changes nothing the branch did.
create_branch base-moves-on
write_repo_file plugins/shop/skills/checkout/SKILL.md 'A total includes tax and shipping.\n'
commit_change "a rule, no eval"
git -C "$repo" checkout -q main
write_repo_file plugins/shop/evals/totals/graders/finds-it.md 'pattern: cents\n'
commit_change "a case edited on main after the branch"
git -C "$repo" checkout -q base-moves-on
run_check
expect_output "a case edited on the base after the branch isn't run" "no eval case changed"

status=0
(cd "$repo" && bash "$script" >/dev/null 2>&1) || status=$?
if [ "$status" -eq 2 ]; then pass "no arguments exit 2"; else fail "no arguments exit 2 (exit $status)"; fi
status=0
(cd "$repo" && bash "$script" main --other >/dev/null 2>&1) || status=$?
if [ "$status" -eq 2 ]; then pass "an unknown flag exits 2"; else fail "an unknown flag exits 2 (exit $status)"; fi

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
