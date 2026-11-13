#!/usr/bin/env bash
# Tests hooks/guard-shell-source-reads.sh: a source file printed through the shell (cat, head, tail,
# sed without -i, git show <rev>:<path>, behind env/sudo/time or a subshell paren) is denied; a pinned
# commit, searching, diffs, in-place edits, writes, quoted text, heredoc bodies, non-source files and
# an empty command are allowed. Every case runs with jq and with the sed fallback (KC_GUARD_NO_JQ=1)
# and also fails when the hook exits non-zero or writes to stderr.
set -u

tests_dir=$(cd "$(dirname "$0")" && pwd)
hook="$(dirname "$tests_dir")/hooks/guard-shell-source-reads.sh"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

failures=0
cases=0

build_bash_payload() { jq -n --arg command "$1" '{tool_name: "Bash", tool_input: {command: $command}}'; }

# Runs the hook on <command> in <mode> (jq or nojq); sets output, status and errors.
run_hook() {
  local mode=$1 command=$2
  if [ "$mode" = nojq ]; then
    output=$(build_bash_payload "$command" | KC_GUARD_NO_JQ=1 bash "$hook" 2>"$work_dir/stderr")
  else
    output=$(build_bash_payload "$command" | bash "$hook" 2>"$work_dir/stderr")
  fi
  status=$?
  errors=$(cat "$work_dir/stderr")
}

# expect_deny <label> <command> <file the deny must name>
expect_deny() {
  local label=$1 command=$2 file=$3 mode output status errors
  local is_deny names_file is_valid_json
  for mode in jq nojq; do
    cases=$((cases + 1))
    run_hook "$mode" "$command"
    is_deny=0 names_file=0 is_valid_json=0
    [[ "$output" == *'"permissionDecision":"deny"'* ]] && is_deny=1
    [[ "$output" == *"$file"* ]] && names_file=1
    printf '%s' "$output" | jq -e . >/dev/null 2>&1 && is_valid_json=1
    if [ "$is_deny" = 1 ] && [ "$names_file" = 1 ] && [ "$is_valid_json" = 1 ] \
      && [ "$status" -eq 0 ] && [ -z "$errors" ]; then
      echo "ok   deny  ($mode) $label"
    else
      echo "FAIL deny  ($mode) $label"
      echo "     status: $status  errors: $errors"
      echo "     output: $output"
      failures=$((failures + 1))
    fi
  done
}

expect_allow() {
  local label=$1 command=$2 mode output status errors
  for mode in jq nojq; do
    cases=$((cases + 1))
    run_hook "$mode" "$command"
    if [ -z "$output" ] && [ "$status" -eq 0 ] && [ -z "$errors" ]; then
      echo "ok   allow ($mode) $label"
    else
      echo "FAIL allow ($mode) $label"
      echo "     status: $status  errors: $errors"
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
expect_deny "git show at a tag" 'git show v1.2.0:src/a.ts' 'src/a.ts'
expect_deny "git show with the output redirected to a file" 'git show HEAD:src/a.ts > /tmp/x' 'src/a.ts'
expect_deny "git -C dir show rev:path" 'git -C /repo show main:app/models/order.rb' 'app/models/order.rb'
expect_deny "env assignment before cat" 'FOO=1 cat src/a.ts' 'src/a.ts'
expect_deny "absolute path to cat" '/bin/cat src/a.go' 'src/a.go'
# shellcheck disable=SC2016  # the $f is part of the command under test, not expanded here
expect_deny "git show inside a loop" 'for f in a b; do echo "== $f"; git show origin/main:src/$f.tsx | head; done' '.tsx'
expect_deny "env wrapper" 'env cat src/a.ts' 'src/a.ts'
expect_deny "sudo wrapper" 'sudo cat src/a.ts' 'src/a.ts'
expect_deny "time wrapper" 'time cat src/a.ts' 'src/a.ts'
expect_deny "subshell paren" '(cat src/a.ts)' 'src/a.ts'
expect_deny "standalone subshell paren" '( cat src/a.ts )' 'src/a.ts'
expect_deny "env wrapper with an assignment" 'env FOO=1 cat src/a.ts' 'src/a.ts'
expect_deny "quoted pipe in a sed script does not split the read" 'sed -n "/a|b/p" src/a.ts' 'src/a.ts'
expect_deny "quoted file name" 'cat "src/a.ts"' 'src/a.ts'
expect_deny "a real read after a heredoc ends" $'cat > x.txt <<EOF\nhi\nEOF\ncat src/a.ts' 'src/a.ts'
expect_deny "a read after a bare assignment" 'FOO=1; cat src/a.ts' 'src/a.ts'

expect_allow "grep -rn" 'grep -rn "expires_at" src'
expect_allow "git grep at a revision" 'git grep -n total origin/main -- src'
expect_allow "git log" 'git log --oneline -5'
expect_allow "git log -p on a rev:path" 'git log -p main:src/a.ts'
expect_allow "git diff of a source file" 'git diff origin/main -- src/orders/OrderForm.tsx'
expect_allow "git diff of rev:path operands" 'git diff main:src/a.ts HEAD:src/a.ts'
expect_allow "git show of a commit" 'git show abc1234'
expect_allow "git show at a short commit id" 'git show 3857f5a:src/orders/OrderForm.tsx'
expect_allow "git show at a full commit id" 'git show 3857f5a1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7:app/models/order.rb'
# shellcheck disable=SC2016  # the variables are part of the command under test, not expanded here
{
  expect_allow "git show at a variable" 'git show $SHA:src/a.ts'
  expect_allow "git show at a braced variable" 'git show ${SHA}:src/a.ts'
  expect_allow "git show at a quoted variable" 'git show "$HEAD_SHA":src/a.ts'
}
expect_allow "git show at a commit id with ~1" 'git show 1234567~1:src/a.ts'
expect_allow "git show at a commit id with ^" 'git show abc1234^:src/a.ts'
expect_allow "git show at a commit id with ^2" 'git show abc1234^2:src/a.ts'
expect_allow "git show --stat" 'git show --stat abc1234'
expect_allow "sed -i in place" "sed -i '' 's/a/b/' src/a.ts"
expect_allow "cat package.json" 'cat package.json'
expect_allow "cat a markdown file" 'cat README.md'
expect_allow "wc of a source file" 'wc -l src/orders/OrderForm.tsx'
expect_allow "heredoc that writes a file" "cat > src/orders/new.ts <<'EOF'"
expect_allow "heredoc that writes a file, redirect attached" "cat >src/orders/new.ts <<'EOF'"
expect_allow "heredoc body that mentions a read" $'cat > src/a.ts <<\'EOF\'\nhead src/b.ts\nEOF'
expect_allow "heredoc commit message that mentions a read" $'git commit -F - <<EOF\ncat src/a.ts is mentioned\nEOF'
expect_allow "commit message that mentions a read" 'git commit -m "x; cat src/a.ts"'
expect_allow "quoted pipe that mentions a read" 'echo "a | head src/a.ts"'
expect_allow "grep piped to head" 'grep -rn foo src | head -5'
expect_allow "ls" 'ls src/orders'
expect_allow "empty command" ''
expect_allow "a bare assignment" 'FOO=1'
expect_allow "a trailing semicolon" 'ls ;'

# The fallback really runs under KC_GUARD_NO_JQ=1: a stub jq that answers `echo hi` for any input
# is used without the flag (allow) and bypassed with it (deny).
mkdir -p "$work_dir/stub"
printf '#!/bin/sh\necho "echo hi"\n' > "$work_dir/stub/jq"
chmod +x "$work_dir/stub/jq"
stub_payload=$(build_bash_payload 'cat src/a.ts')
cases=$((cases + 1))
fallback_output=$(printf '%s' "$stub_payload" | PATH="$work_dir/stub:$PATH" KC_GUARD_NO_JQ=1 bash "$hook")
if [[ "$fallback_output" == *'"permissionDecision":"deny"'* ]]; then
  echo "ok   fallback used with KC_GUARD_NO_JQ=1"
else
  echo "FAIL fallback not used with KC_GUARD_NO_JQ=1: $fallback_output"
  failures=$((failures + 1))
fi
cases=$((cases + 1))
stub_output=$(printf '%s' "$stub_payload" | PATH="$work_dir/stub:$PATH" bash "$hook")
if [ -z "$stub_output" ]; then
  echo "ok   jq used without KC_GUARD_NO_JQ"
else
  echo "FAIL jq not used without KC_GUARD_NO_JQ: $stub_output"
  failures=$((failures + 1))
fi

echo "$((cases - failures)) passed, $failures failed"
[ "$failures" -eq 0 ]
