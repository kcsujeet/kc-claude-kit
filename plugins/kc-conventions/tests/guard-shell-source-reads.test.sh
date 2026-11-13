#!/usr/bin/env bash
# Tests hooks/guard-shell-source-reads.sh: a source file printed through the shell (cat, head, tail,
# sed without -i, git show <rev>:<path>) is denied; searching, diffs, in-place edits, writes,
# non-source files and an empty command are allowed. Every case runs with jq and with the sed
# fallback (KC_GUARD_NO_JQ=1).
set -u

tests_dir=$(cd "$(dirname "$0")" && pwd)
hook="$(dirname "$tests_dir")/hooks/guard-shell-source-reads.sh"

failures=0
cases=0

payload_for() { jq -n --arg command "$1" '{tool_name: "Bash", tool_input: {command: $command}}'; }

# expect_deny <label> <command> <file the deny must name>
expect_deny() {
  local label=$1 command=$2 file=$3 mode output
  for mode in jq nojq; do
    cases=$((cases + 1))
    if [ "$mode" = nojq ]; then
      output=$(payload_for "$command" | KC_GUARD_NO_JQ=1 bash "$hook")
    else
      output=$(payload_for "$command" | bash "$hook")
    fi
    if [[ "$output" == *'"permissionDecision":"deny"'* && "$output" == *"$file"* ]] \
      && printf '%s' "$output" | jq -e . >/dev/null 2>&1; then
      echo "ok   deny  ($mode) $label"
    else
      echo "FAIL deny  ($mode) $label"
      echo "     output: $output"
      failures=$((failures + 1))
    fi
  done
}

expect_allow() {
  local label=$1 command=$2 mode output
  for mode in jq nojq; do
    cases=$((cases + 1))
    if [ "$mode" = nojq ]; then
      output=$(payload_for "$command" | KC_GUARD_NO_JQ=1 bash "$hook")
    else
      output=$(payload_for "$command" | bash "$hook")
    fi
    if [ -z "$output" ]; then
      echo "ok   allow ($mode) $label"
    else
      echo "FAIL allow ($mode) $label"
      echo "     output: $output"
      failures=$((failures + 1))
    fi
  done
}

expect_deny "cat a ruby file" 'cat app/models/order.rb' 'app/models/order.rb'
expect_deny "sed -n range of a tsx file" "sed -n '1,80p' src/orders/OrderForm.tsx" 'src/orders/OrderForm.tsx'
expect_deny "head a tsx file" 'head -40 src/orders/OrderForm.tsx' 'src/orders/OrderForm.tsx'
expect_deny "tail a python file" 'tail -n 20 lib/shop/pricing.py' 'lib/shop/pricing.py'
expect_deny "git show rev:path piped to sed, after cd" 'cd /repo && git show origin/main:src/orders/OrderForm.tsx | sed -n 90,125p' 'src/orders/OrderForm.tsx'
expect_deny "git show at HEAD" 'git show HEAD:src/a.ts' 'src/a.ts'
expect_deny "git show at HEAD~1" 'git show HEAD~1:src/a.ts' 'src/a.ts'
expect_deny "git show at main" 'git show main:src/a.ts' 'src/a.ts'
expect_deny "git show with an empty rev" 'git show :src/a.ts' 'src/a.ts'
expect_deny "git show at a branch with a slash" 'git show feature/abc-1:src/a.ts' 'src/a.ts'
expect_deny "git -C dir show rev:path" 'git -C /repo show main:app/models/order.rb' 'app/models/order.rb'
expect_deny "env assignment before cat" 'FOO=1 cat src/a.ts' 'src/a.ts'
expect_deny "absolute path to cat" '/bin/cat src/a.go' 'src/a.go'
# shellcheck disable=SC2016  # the $f is part of the command under test, not expanded here
expect_deny "git show inside a loop" 'for f in a b; do echo "== $f"; git show origin/main:src/$f.tsx | head; done' '.tsx'

expect_allow "grep -rn" 'grep -rn "order_total" src'
expect_allow "git grep at a revision" 'git grep -n total origin/main -- src'
expect_allow "git log" 'git log --oneline -5'
expect_allow "git diff of a source file" 'git diff origin/main -- src/orders/OrderForm.tsx'
expect_allow "git show of a commit" 'git show abc1234'
expect_allow "git show at a short commit id" 'git show 3857f5a:src/orders/OrderForm.tsx'
expect_allow "git show at a full commit id" 'git show 3857f5a1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7:app/models/order.rb'
expect_allow "git show --stat" 'git show --stat abc1234'
expect_allow "sed -i in place" "sed -i '' 's/a/b/' src/a.ts"
expect_allow "cat package.json" 'cat package.json'
expect_allow "cat a markdown file" 'cat README.md'
expect_allow "wc of a source file" 'wc -l src/orders/OrderForm.tsx'
expect_allow "heredoc that writes a file" "cat > src/orders/new.ts <<'EOF'"
expect_allow "heredoc that writes a file, redirect attached" "cat >src/orders/new.ts <<'EOF'"
expect_allow "grep piped to head" 'grep -rn foo src | head -5'
expect_allow "ls" 'ls src/orders'
expect_allow "empty command" ''

echo "$((cases - failures)) passed, $failures failed"
[ "$failures" -eq 0 ]
