#!/usr/bin/env bash
# Tests hooks/guard-shape.sh: with no valid shape file for the current branch, a write to a
# non-test source file (the Edit, Write and MultiEdit tools, a shell redirect, tee, sed -i, cp, mv,
# a REPL write( or edit( call) is denied with the problems; a passing shape file, a trivial
# declaration, a test file, a file that is not source code, a read, the default branch, a detached
# head, a path outside any checkout, another branch's shape file, or a machine with no jq is
# allowed silently.
set -u

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
hook="$plugin_dir/hooks/guard-shape.sh"
skill="$plugin_dir/skills/kc-shape-the-change/SKILL.md"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

failures=0
passes=0

repo="$work_dir/shop"
git init -q -b main "$repo"
git -C "$repo" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
git -C "$repo" checkout -q -b feature/fulfilment-mode
shape_dir="$repo/.git/kc-shape/feature"
mkdir -p "$shape_dir"
awk '/^```markdown$/ { inside = 1; next } inside && /^```$/ { exit } inside' "$skill" > "$work_dir/passing.md"
grep -v '§SH5' "$work_dir/passing.md" > "$work_dir/failing.md"
printf 'trivial: no new storage, no new unit, no behaviour move: fixes the rounding of one displayed total\n' > "$work_dir/trivial.md"

build_tool_payload() { jq -n --arg tool "$1" --arg path "$2" --arg cwd "$repo" '{tool_name: $tool, cwd: $cwd, tool_input: {file_path: $path}}'; }
build_bash_payload() { jq -n --arg command "$1" --arg cwd "${2:-$repo}" '{tool_name: "Bash", cwd: $cwd, tool_input: {command: $command}}'; }
build_repl_payload() { jq -n --arg code "$1" --arg cwd "$repo" '{tool_name: "REPL", cwd: $cwd, tool_input: {code: $code}}'; }

no_jq_bin="$work_dir/no-jq-bin"
mkdir -p "$no_jq_bin"
for tool in bash cat dirname; do ln -s "$(command -v "$tool")" "$no_jq_bin/$tool"; done

# expect_hook_verdict <allow|deny> <label> <payload> [nojq]
expect_hook_verdict() {
  local expectation=$1 label=$2 payload=$3 mode=${4:-jq} output verdict
  if [ "$mode" = nojq ]; then
    output=$(printf '%s' "$payload" | PATH="$no_jq_bin" bash "$hook" 2>&1)
  else
    output=$(printf '%s' "$payload" | bash "$hook" 2>&1)
  fi
  verdict="unexpected: $output"
  [ -z "$output" ] && verdict=allow
  if printf '%s' "$output" | grep -q '"permissionDecision":"deny"' && printf '%s' "$output" | jq -e . >/dev/null 2>&1; then
    verdict=deny
  fi
  if [ "$verdict" = "$expectation" ]; then
    echo "ok   [$mode] $label"; passes=$((passes + 1))
  else
    echo "FAIL [$mode] $label: expected $expectation, got $verdict"; failures=$((failures + 1))
  fi
  last_output=$output
}

source_file="$repo/app/orders/fulfilment.ts"

# §SH1: no shape file on a feature branch.
expect_hook_verdict deny "§SH1 no shape file: Edit of a source file is denied" "$(build_tool_payload Edit "$source_file")"
expect_hook_verdict deny "no shape file: Write of a new source file is denied" "$(build_tool_payload Write "$repo/app/new/unit.rb")"
expect_hook_verdict deny "no shape file: MultiEdit is denied" "$(build_tool_payload MultiEdit "$repo/lib/pricing.py")"
expect_hook_verdict allow "no shape file: a test file passes" "$(build_tool_payload Edit "$repo/app/orders/fulfilment.test.ts")"
expect_hook_verdict allow "no shape file: a spec folder passes" "$(build_tool_payload Write "$repo/spec/models/order_spec.rb")"
expect_hook_verdict allow "no shape file: a tests folder passes" "$(build_tool_payload Write "$repo/tests/orders.py")"
expect_hook_verdict allow "no shape file: test_x.py passes" "$(build_tool_payload Write "$repo/orders/test_totals.py")"
expect_hook_verdict allow "no shape file: a Markdown file passes" "$(build_tool_payload Edit "$repo/README.md")"
expect_hook_verdict allow "no shape file: a shell script passes" "$(build_tool_payload Edit "$repo/bin/run.sh")"
expect_hook_verdict allow "no shape file: a path outside any checkout passes" "$(build_tool_payload Write "$work_dir/scratch.ts")"
expect_hook_verdict allow "no shape file: another tool passes" "$(build_tool_payload Read "$source_file")"
expect_hook_verdict deny "no shape file: the denial names the shape file" "$(build_tool_payload Edit "$source_file")"
if printf '%s' "$last_output" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -qF 'no shape file for branch feature/fulfilment-mode'; then
  echo "ok   the reason names the problem"; passes=$((passes + 1))
else
  echo "FAIL the reason does not name the problem: $last_output"; failures=$((failures + 1))
fi

# Shell and REPL writes.
expect_hook_verdict deny "a redirect into a source file is denied" "$(build_bash_payload 'echo x > app/orders/fulfilment.ts')"
expect_hook_verdict deny "an append into a source file is denied" "$(build_bash_payload 'echo x >> app/orders/fulfilment.ts')"
expect_hook_verdict deny "a redirect with no space is denied" "$(build_bash_payload 'cat patch >app/orders/fulfilment.ts')"
expect_hook_verdict deny "tee into a source file is denied" "$(build_bash_payload 'echo x | tee -a app/orders/fulfilment.ts')"
expect_hook_verdict deny "sed -i on a source file is denied" "$(build_bash_payload "sed -i 's/a/b/' app/orders/fulfilment.ts")"
expect_hook_verdict deny "perl -pi on a source file is denied" "$(build_bash_payload "perl -pi -e 's/a/b/' app/orders/fulfilment.ts")"
expect_hook_verdict deny "cp onto a source file is denied" "$(build_bash_payload 'cp /tmp/draft app/orders/fulfilment.ts')"
expect_hook_verdict deny "mv onto a source file is denied" "$(build_bash_payload 'mv /tmp/draft.js app/orders/fulfilment.js')"
expect_hook_verdict deny "a chained write is denied" "$(build_bash_payload 'git status && echo x > app/orders/fulfilment.ts')"
expect_hook_verdict deny "a leading cd names the checkout" "$(build_bash_payload "cd $repo && echo x > app/orders/fulfilment.ts" "$work_dir")"
expect_hook_verdict allow "a redirect into a test file passes" "$(build_bash_payload 'echo x > app/orders/fulfilment.test.ts')"
expect_hook_verdict allow "a redirect into a log passes" "$(build_bash_payload 'npm test > out.log 2>&1')"
expect_hook_verdict allow "sed -n on a source file (a read) passes" "$(build_bash_payload "sed -n '1,5p' app/orders/fulfilment.ts")"
expect_hook_verdict allow "sed --silent on a source file passes" "$(build_bash_payload "sed --silent -e 1p app/orders/fulfilment.ts")"
expect_hook_verdict allow "cp from a source file passes" "$(build_bash_payload 'cp app/orders/fulfilment.ts /tmp/copy.txt')"
expect_hook_verdict allow "grep over source passes" "$(build_bash_payload 'grep -rn mode app/orders/fulfilment.ts')"
expect_hook_verdict deny "a REPL write( to a source file is denied" "$(build_repl_payload "await write('$repo/app/orders/fulfilment.ts', 'x')")"
expect_hook_verdict deny "a REPL edit( of a source file is denied" "$(build_repl_payload "await edit('app/orders/fulfilment.ts', 'a', 'b')")"
expect_hook_verdict allow "a REPL read of a source file passes" "$(build_repl_payload "await file('app/orders/fulfilment.ts').text()")"
expect_hook_verdict allow "a REPL write to a test file passes" "$(build_repl_payload "await write('app/orders/fulfilment.test.ts', 'x')")"

# A failing shape file.
cp "$work_dir/failing.md" "$shape_dir/fulfilment-mode.md"
expect_hook_verdict deny "§SH5 missing: Edit is denied" "$(build_tool_payload Edit "$source_file")"
if printf '%s' "$last_output" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -qF '§SH5: missing'; then
  echo "ok   the reason carries the checker's problem"; passes=$((passes + 1))
else
  echo "FAIL the reason does not carry the checker's problem: $last_output"; failures=$((failures + 1))
fi
expect_hook_verdict allow "§SH5 missing: a test file still passes" "$(build_tool_payload Edit "$repo/app/orders/fulfilment.test.ts")"
expect_hook_verdict allow "§SH5 missing: with no jq the hook reads nothing and allows" "$(build_tool_payload Edit "$source_file")" nojq

# Another branch's shape file does not apply.
git -C "$repo" checkout -q -b other
expect_hook_verdict deny "another branch's shape file does not apply" "$(build_tool_payload Edit "$source_file")"
git -C "$repo" checkout -q feature/fulfilment-mode

# A passing shape file and a trivial declaration.
cp "$work_dir/passing.md" "$shape_dir/fulfilment-mode.md"
expect_hook_verdict allow "§SH1-§SH8 filled: Edit passes" "$(build_tool_payload Edit "$source_file")"
expect_hook_verdict allow "§SH1-§SH8 filled: a redirect passes" "$(build_bash_payload 'echo x > app/orders/fulfilment.ts')"
expect_hook_verdict allow "§SH1-§SH8 filled: a REPL write passes" "$(build_repl_payload "await write('app/orders/fulfilment.ts', 'x')")"
cp "$work_dir/trivial.md" "$shape_dir/fulfilment-mode.md"
expect_hook_verdict allow "a trivial declaration lets Edit pass" "$(build_tool_payload Edit "$source_file")"

# Never denied: default branch, detached head.
rm -f "$shape_dir/fulfilment-mode.md"
git -C "$repo" checkout -q main
expect_hook_verdict allow "the default branch is never blocked" "$(build_tool_payload Edit "$source_file")"
git -C "$repo" checkout -q --detach
expect_hook_verdict allow "a detached head is never blocked" "$(build_tool_payload Edit "$source_file")"

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
