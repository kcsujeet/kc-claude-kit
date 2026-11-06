#!/usr/bin/env bash
# Tests scripts/run-changed-evals.sh in a throwaway repo, with a stand-in `claude` on PATH that
# records its arguments and writes a canned result: only changed cases run, a case passes when it
# passes every grader with the plugin and fails every scored grader without it, its proof.json
# records that, and --check passes only a committed record of a passing run made from the case and
# plugin code at HEAD.
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
# Stand-in for claude: `--version` prints one; `plugin eval` logs its arguments and copies
# $STUB_RESULTS/<case>.json to the --json path, when there is one.
if [ "${1:-}" = --version ]; then echo "9.9.9 (Claude Code)"; exit 0; fi
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

# Runs the script on the current branch against main, with any extra arguments; keeps its output
# and exit status.
last_output="" last_status=0
run_script() {
  : > "$calls"
  last_status=0
  last_output=$(cd "$repo" && env PATH="$stub_bin:$PATH" STUB_CALLS="$calls" STUB_RESULTS="$results" bash "$script" main "$@" 2>&1) || last_status=$?
}

# Drops the proof.json files a run left, so the next run starts from the commit.
reset_tree() { git -C "$repo" checkout -q -- . && git -C "$repo" clean -fdq; }

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

expect_record() {
  local label=$1 file=$2 filter=$3 expected=$4 actual
  actual=$(jq -r "$filter" "$repo/$file" 2>/dev/null || echo "no record")
  if [ "$actual" = "$expected" ]; then pass "$label"; else fail "$label (got: $actual)"; fi
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
write_repo_file plugins/gates/skills/review/SKILL.md 'Review the whole fix.\n'
write_repo_file plugins/shop/skills/checkout/SKILL.md 'A total includes tax.\n'
write_repo_file plugins/other/skills/x/SKILL.md 'Other.\n'
commit_change base

create_branch no-eval
echo "Include shipping." >> "$repo/plugins/shop/skills/checkout/SKILL.md"
commit_change "a rule, no eval"
run_script
expect_status "no changed case passes" 0
expect_output "it says so" "no eval case changed"
expect_calls "and runs nothing" 0
run_script --check
expect_status "--check passes a change to no case" 0

create_branch results-only
write_repo_file plugins/shop/evals/results/run.json '{}\n'
write_repo_file plugins/shop/evals/mocks/server.json '{}\n'
commit_change "a results file and a mock"
run_script --check
expect_output "the runner's results/ and mocks/ folders are no case" "no eval case changed"

create_branch case-deleted
git -C "$repo" rm -rq plugins/shop/evals/totals
commit_change "a deleted case"
run_script --check
expect_output "a deleted case has nothing to run" "no eval case changed"

# A run judges the result and writes the record.
create_branch grader-changed
write_repo_file plugins/shop/evals/totals/graders/finds-it.md 'pattern: shipping|freight\n'
commit_change "a grader edit"
write_result totals true false
write_repo_file plugins/shop/skills/checkout/SKILL.md 'Uncommitted.\n'
run_script
expect_status "a run with uncommitted changes is refused" 2
expect_output "it says why" "commit or stash your changes first"
expect_calls "and runs nothing" 0
reset_tree

run_script
expect_status "a case that passes with the plugin and fails without it passes" 0
expect_output "it says both" "passes with the plugin, fails without it"
expect_calls "one eval run" 1
if grep -qE -- '^plugin eval plugins/shop --case totals --runs 1 --ablation with-without ' "$calls"; then
  pass "the run targets the plugin, one run of that case, with the baseline arm"
else
  fail "the run targets the plugin, one run of that case, with the baseline arm (got: $(cat "$calls"))"
fi
expect_record "the record says it passed" plugins/shop/evals/totals/proof.json .verdict ok
expect_record "the record names the commit" plugins/shop/evals/totals/proof.json .commit "$(git -C "$repo" rev-parse HEAD)"
expect_record "the record keeps each grader's result" plugins/shop/evals/totals/proof.json '.runs.without[0].graders[0].passed' false
expect_record "the record names claude's version" plugins/shop/evals/totals/proof.json .claude "9.9.9 (Claude Code)"
run_script
expect_status "a record left by an earlier run doesn't block the next" 0
reset_tree

write_result totals false false
run_script
expect_status "a case that fails with the plugin fails" 1
expect_output "it names the grader" "with the plugin, graders failed: finds-it"
expect_record "the record says why" plugins/shop/evals/totals/proof.json .verdict "with the plugin, graders failed: finds-it"
reset_tree

write_result totals true true
run_script
expect_status "a case that passes without the plugin fails" 1
expect_output "it says why" "graders passed too, so they prove nothing the kit adds: finds-it"
reset_tree

# A format grader the baseline fails can't stand in for the rule's grader it passes.
printf '{"cases":[{"name":"totals","arms":{"with":[{"error":null,"graders":[{"name":"finds-it","passed":true,"scored":true},{"name":"verdict","passed":true,"scored":true}]}],"without":[{"error":null,"graders":[{"name":"finds-it","passed":true,"scored":true},{"name":"verdict","passed":false,"scored":true}]}]}}]}\n' > "$results/totals.json"
run_script
expect_status "a baseline that passes one scored grader fails the case" 1
expect_output "it names that grader" "prove nothing the kit adds: finds-it"
reset_tree

printf '{"cases":[{"name":"totals","arms":{"with":[{"error":null,"graders":[{"name":"finds-it","passed":true,"scored":true}]}],"without":[{"error":null,"graders":[{"name":"skill-fired","passed":false,"scored":false}]}]}}]}\n' > "$results/totals.json"
run_script
expect_status "a baseline with no scored grader fails the case" 1
expect_output "it says so" "the run without the plugin has no scored grader"
reset_tree

write_result totals true none
run_script
expect_status "a result with no baseline run fails" 1
expect_output "it says so" "no run without the plugin"
reset_tree

rm "$results/totals.json"
run_script
expect_status "a run that writes no result fails" 1
expect_output "it says so" "the eval run wrote no result"
expect_record "and records that" plugins/shop/evals/totals/proof.json .verdict "the eval run wrote no result"
reset_tree

printf '{"cases":[{"name":"totals","arms":{"with":[{"error":"timed out","graders":[]}],"without":[]}}]}\n' > "$results/totals.json"
run_script
expect_status "a run that errors fails" 1
expect_output "it says so" "the run with the plugin errored"
reset_tree

printf '{"cases":[{"name":"totals","arms":{"with":[{"error":null,"graders":[{"name":"finds-it","passed":true,"scored":true}]}],"without":[{"error":"timed out","graders":[{"name":"finds-it","passed":false,"scored":true}]}]}}]}\n' > "$results/totals.json"
run_script
expect_status "an errored baseline run fails" 1
expect_output "it says so" "the run without the plugin errored"
reset_tree

# Without the plugin a skill-fired grader fails by nature; only the scored graders count.
printf '{"cases":[{"name":"totals","arms":{"with":[{"error":null,"graders":[{"name":"finds-it","passed":true,"scored":true}]}],"without":[{"error":null,"graders":[{"name":"finds-it","passed":true,"scored":true},{"name":"skill-fired","passed":false,"scored":false}]}]}}]}\n' > "$results/totals.json"
run_script
expect_status "a baseline that fails only an unscored grader passes the case, so it fails here" 1
expect_output "it says why" "prove nothing the kit adds: finds-it"
reset_tree

printf '{"cases":[]}\n' > "$results/totals.json"
run_script
expect_status "a result without the case fails" 1
expect_output "it says so" "its result has no case named totals"
reset_tree

# --check reads the committed record, runs nothing and needs no key.
run_script --check
expect_status "--check fails a changed case with no record" 1
expect_output "it says so" "FAIL plugins/shop/evals/totals: no local run recorded"
expect_output "it says how to make one" "commit the proof.json it writes"
expect_calls "and runs nothing" 0

write_result totals true false
run_script
commit_change "the record of a passing run"
run_script --check
expect_status "--check passes a committed record of a passing run" 0
expect_output "it says so" "ok   plugins/shop/evals/totals: its recorded run passed"
expect_calls "and runs nothing" 0
run_script
run_script
expect_status "a committed record a run rewrote doesn't block the next run" 0
reset_tree

write_repo_file plugins/shop/evals/totals/graders/finds-it.md 'pattern: freight\n'
commit_change "the grader changes after the run"
run_script --check
expect_status "a record made from other case files fails" 1
expect_output "it says so" "its record was made from other case files"

git -C "$repo" checkout -q HEAD~1
write_repo_file plugins/shop/skills/checkout/SKILL.md 'A total includes tax and shipping.\n'
commit_change "the plugin's rule changes after the run"
run_script --check
expect_status "a record made from other plugin code fails" 1
expect_output "it names the plugin" "its record was made from other code in plugins/shop"

create_branch other-plugin
write_repo_file plugins/shop/evals/totals/graders/finds-it.md 'pattern: freight\n'
commit_change "a grader edit"
write_result totals true false
run_script
commit_change "its record"
write_repo_file plugins/other/skills/x/SKILL.md 'Other, changed.\n'
commit_change "a plugin the case doesn't load changes"
run_script --check
expect_status "a plugin the case doesn't load doesn't stale its record" 0

# Back to the commit that holds the passing record, on a branch of its own.
git -C "$repo" checkout -q -b failing-record grader-changed~1
jq '.verdict = "with the plugin, graders failed: finds-it"' "$repo/plugins/shop/evals/totals/proof.json" > "$work/failed.json"
cp "$work/failed.json" "$repo/plugins/shop/evals/totals/proof.json"
commit_change "a record of a failing run"
run_script --check
expect_status "a record of a failing run fails" 1
expect_output "it gives the reason" "its recorded run failed: with the plugin, graders failed: finds-it"

printf 'not json\n' > "$repo/plugins/shop/evals/totals/proof.json"
commit_change "a broken record"
run_script --check
expect_status "a record that isn't JSON fails" 1
expect_output "it says so" "no local run recorded"

create_branch negative-case
write_repo_file plugins/shop/evals/greeting/prompt.md '---\nname: greeting\ntags: [negative]\n---\nSay hello.\n'
commit_change "a negative case"
write_result greeting true true
run_script
expect_status "a negative case may pass without the plugin" 0
expect_output "it says why" "a negative case"
reset_tree
printf '{"cases":[{"name":"greeting","arms":{"with":[{"error":null,"graders":[]}],"without":[]}}]}\n' > "$results/greeting.json"
run_script
expect_status "a run with no graders fails, negative or not" 1
expect_output "it says so" "has no graders, so it checks nothing"
reset_tree

create_branch beside-another-plugin
write_repo_file plugins/gates/evals/whole-fix/prompt.md '---\nplugins: ["../..", "../../../shop"]\n---\nReview my branch.\n'
commit_change "a case that loads a second plugin"
write_result whole-fix true false
run_script
expect_status "a case loading a second plugin runs" 0
if grep -qE -- '^plugin eval \. --eval-dir plugins/gates/evals --case whole-fix ' "$calls"; then
  pass "it runs from the repo root with --eval-dir"
else
  fail "it runs from the repo root with --eval-dir (got: $(cat "$calls"))"
fi
commit_change "its record"
write_repo_file plugins/shop/skills/checkout/SKILL.md 'A total includes tax, always.\n'
commit_change "the second plugin's rule changes after the run"
run_script --check
expect_status "a change to the second plugin stales the record" 1
expect_output "it names both plugins" "other code in plugins/gates plugins/shop"

create_branch two-cases
write_repo_file plugins/shop/evals/totals/graders/finds-it.md 'pattern: freight\n'
write_repo_file plugins/gates/evals/whole-fix/prompt.md '---\nplugins: ["../..", "../../../shop"]\n---\nReview this branch.\n'
commit_change "two cases"
write_result totals true false
write_result whole-fix false false
run_script
expect_status "one failing case fails the run" 1
expect_calls "each changed case runs once" 2
expect_output "the passing case is reported" "ok   plugins/shop/evals/totals"
expect_output "the failing case is reported" "FAIL plugins/gates/evals/whole-fix"
reset_tree

# The base moving on after the branch was cut changes nothing the branch did.
create_branch base-moves-on
write_repo_file plugins/shop/skills/checkout/SKILL.md 'A total includes tax and shipping.\n'
commit_change "a rule, no eval"
git -C "$repo" checkout -q main
write_repo_file plugins/shop/evals/totals/graders/finds-it.md 'pattern: cents\n'
commit_change "a case edited on main after the branch"
git -C "$repo" checkout -q base-moves-on
run_script --check
expect_output "a case edited on the base after the branch isn't checked" "no eval case changed"

status=0
(cd "$repo" && bash "$script" >/dev/null 2>&1) || status=$?
if [ "$status" -eq 2 ]; then pass "no arguments exit 2"; else fail "no arguments exit 2 (exit $status)"; fi
status=0
(cd "$repo" && bash "$script" main --other >/dev/null 2>&1) || status=$?
if [ "$status" -eq 2 ]; then pass "an unknown flag exits 2"; else fail "an unknown flag exits 2 (exit $status)"; fi

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
