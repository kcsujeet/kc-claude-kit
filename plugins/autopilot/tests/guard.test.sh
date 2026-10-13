#!/usr/bin/env bash
# Tests scripts/guard.sh: one case per rule in the plan's Task 7.
set -euo pipefail
tests_dir=$(cd "$(dirname "$0")" && pwd)
guard="$(dirname "$tests_dir")/scripts/guard.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
passes=0
failures=0

# A worktree with a config naming risky paths.
wt="$tmp/wt"
git init -q -b main "$wt"
mkdir -p "$wt/.claude" "$wt/db/migrate" "$wt/src"
echo '{"risky_paths":["db/migrate/**","**/payments/**"]}' > "$wt/.claude/autopilot.json"

bash_payload() { jq -cn --arg agent "$1" --arg cmd "$2" --arg cwd "$wt" \
  '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$cmd},cwd:$cwd} + (if $agent == "" then {} else {agent_type:$agent} end)'; }
edit_payload() { jq -cn --arg agent "$1" --arg path "$2" --arg text "$3" --arg cwd "$wt" \
  '{hook_event_name:"PreToolUse",tool_name:"Edit",tool_input:{file_path:$path,old_string:"x",new_string:$text},cwd:$cwd} + (if $agent == "" then {} else {agent_type:$agent} end)'; }
write_payload() { jq -cn --arg agent "$1" --arg path "$2" --arg text "$3" --arg cwd "$wt" \
  '{hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:$path,content:$text},cwd:$cwd} + (if $agent == "" then {} else {agent_type:$agent} end)'; }

check() {
  local expectation=$1 label=$2 payload=$3 output verdict
  output=$(printf '%s' "$payload" | bash "$guard")
  if [ -z "$output" ]; then verdict=allow
  elif printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then verdict=deny
  else verdict="unexpected: $output"; fi
  if [ "$verdict" = "$expectation" ]; then echo "ok   $label"; passes=$((passes + 1))
  else echo "FAIL $label"; echo "     expected $expectation, got $verdict"; failures=$((failures + 1)); fi
}

E=autopilot:engineer
check deny  "1 run files"            "$(write_payload $E "$wt/.autopilot/runs/r1/units.json" '{}')"
check deny  "1 run files, verifier"  "$(write_payload autopilot:verifier "$wt/.autopilot/runs/r1/report.md" 'x')"
check deny  "1 outside runs"         "$(write_payload $E "$wt/.autopilot/notes.md" 'x')"
check allow "1 unit scratch"         "$(write_payload autopilot:qa-persona "$wt/.autopilot/runs/r1/U1/qa/0/flow.cjs" 'x')"
check deny  "1 bash redirect"        "$(bash_payload autopilot:shipper "echo x > $wt/.autopilot/runs/r1/units.json")"
check allow "1 bash unit scratch"    "$(bash_payload autopilot:shipper "bash pr-body.sh in.json > $wt/.autopilot/runs/r1/U1/pr-body.md")"
check deny  "2 merge"                "$(bash_payload autopilot:shipper 'gh pr merge 12 --squash')"
check deny  "2 auto-merge"           "$(bash_payload autopilot:shipper 'gh pr merge --auto 12')"
check deny  "3 force push"           "$(bash_payload autopilot:shipper 'git push --force origin autopilot/r1/U1')"
check deny  "3 push main"            "$(bash_payload autopilot:shipper 'git push origin HEAD:main')"
check allow "3 push own branch"      "$(bash_payload autopilot:shipper 'git push -u origin autopilot/r1/U1')"
check deny  "4 it.skip"              "$(edit_payload $E "$wt/src/picker.test.tsx" "it.skip('inserts', () => {})")"
check deny  "4 rspec skip"           "$(edit_payload $E "$wt/spec/models/reply_spec.rb" "  skip 'flaky'")"
check deny  "4 pytest skip"          "$(write_payload $E "$wt/tests/test_reply.py" "@pytest.mark.skip")"
check allow "4 skip word in source"  "$(edit_payload $E "$wt/src/picker.tsx" "const skip = true")"
check deny  "5 rm test"              "$(bash_payload $E "rm src/picker.test.tsx")"
check deny  "5 git rm spec"          "$(bash_payload $E "git rm spec/models/reply_spec.rb")"
check deny  "6 risky migration"      "$(write_payload $E "$wt/db/migrate/20261012_add_replies.rb" "class X; end")"
check deny  "6 risky nested glob"    "$(edit_payload $E "$wt/src/payments/charge.ts" "x")"
check allow "6 risky only for engineer" "$(edit_payload autopilot:verifier "$wt/db/migrate/a.rb" "x")"
check allow "6 normal file"          "$(edit_payload $E "$wt/src/picker.tsx" "x")"
check deny  "7 lockfile"             "$(edit_payload $E "$wt/package-lock.json" "x")"
check deny  "7 bun add"              "$(bash_payload $E "bun add left-pad")"
check deny  "7 bundle add"           "$(bash_payload $E "bundle add sidekiq")"
check allow "7 plain install"        "$(bash_payload $E "bun install")"
check allow "8 main session"         "$(bash_payload '' 'gh pr merge 12')"
check allow "8 other plugin agent"   "$(bash_payload code-review:naming-gate 'gh pr merge 12')"

# Fix round 1: rewordings of the rules above.
S=autopilot:shipper
nl=$'\n'
run="$wt/.autopilot/runs/r1"
check deny  "10 continuation push"   "$(bash_payload $S "git push \\${nl}--force origin x")"
check deny  "10 continuation merge"  "$(bash_payload $S "gh pr \\${nl}merge 12")"
check deny  "10 continuation write"  "$(bash_payload $S "echo x > \\${nl}$run/units.json")"
check deny  "10 continuation rm"     "$(bash_payload $E "rm \\${nl}src/picker.test.tsx")"
check allow "11 heredoc body is data" "$(bash_payload $S "git commit -F - <<EOF${nl}feat: x${nl}${nl}Next: push to main after review${nl}EOF")"
check deny  "11 command after heredoc" "$(bash_payload $S "cat > src/gen.ts <<'EOF'${nl}x${nl}EOF${nl}gh pr merge 1")"
check deny  "11 quoted << is no heredoc" "$(bash_payload $S "echo \"<<EOF\"${nl}gh pr merge 1${nl}EOF")"
check deny  "11 heredoc opener redirect" "$(bash_payload $S "cat > $run/units.json <<'EOF'${nl}{}${nl}EOF")"
check allow "12 skip property in test"   "$(edit_payload $E "$wt/src/picker.test.ts" "expect(page.skip).toBe(10)")"
check allow "12 skip option in test"     "$(edit_payload $E "$wt/src/repo.test.ts" "repo.findMany({ take: 5, skip: 10 })")"
check allow "12 pending variable in test" "$(edit_payload $E "$wt/src/load.test.ts" "  pending = await load()")"
check allow "12 skip call in test"       "$(edit_payload $E "$wt/src/load.test.ts" "  skip(3)")"
check deny  "12 skip.each"               "$(edit_payload $E "$wt/src/picker.test.ts" "it.skip.each([1])('x', () => {})")"
check deny  "13 merge with -R"       "$(bash_payload $S 'gh pr -R a/b merge 12')"
check deny  "13 merge with --repo"   "$(bash_payload $S 'gh pr --repo a/b merge 12')"
check deny  "14 noclobber redirect"  "$(bash_payload $S "echo x >| $run/units.json")"
check allow "15 push --follow-tags"  "$(bash_payload $S 'git push --follow-tags origin autopilot/r1/U1')"
check deny  "16 rm mixed-case test"  "$(bash_payload $E 'rm -f src/Picker.Test.tsx')"
check deny  "17 rm cypress spec"     "$(bash_payload $E 'rm src/login.cy.ts')"
check deny  "17 rm e2e file"         "$(bash_payload $E 'rm e2e/flows/login.ts')"
check deny  "17 skip in Django tests.py" "$(write_payload $E "$wt/app/tests.py" "@pytest.mark.skip")"
check deny  "18 find -delete tests"  "$(bash_payload $E "find src -name '*.test.ts' -delete")"
check deny  "20 risky directory target" "$(bash_payload $E "cd $wt && cp /tmp/x.rb db/migrate")"
check deny  "18 git clean tests"     "$(bash_payload $E 'git clean -f src/__tests__')"

# Timing: a hook that times out fails open, so long commands must stay fast.
timed() {
  local expectation=$1 label=$2 payload=$3 output seconds verdict
  TIMEFORMAT=%R
  seconds=$( { time printf '%s' "$payload" | bash "$guard" > "$tmp/timed.out"; } 2>&1 )
  output=$(cat "$tmp/timed.out")
  if [ -z "$output" ]; then verdict=allow
  elif printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then verdict=deny
  else verdict="unexpected: $output"; fi
  if [ "$verdict" = "$expectation" ] && awk -v s="$seconds" 'BEGIN { exit !(s < 2) }'; then
    echo "ok   $label (${seconds}s)"; passes=$((passes + 1))
  else
    echo "FAIL $label"; echo "     expected $expectation, got $verdict in ${seconds}s"; failures=$((failures + 1))
  fi
}
heredoc="cat > $wt/src/gen.ts <<'EOF'"
copies="cd $wt"
for i in $(seq 1 200); do
  heredoc="$heredoc${nl}export const value$i = cp(\"src/a$i.ts\") > limit; // rm x.test.ts push main"
  copies="$copies && cp src/a$i.ts src/b$i.ts"
done
heredoc="$heredoc${nl}EOF"
timed allow "19 200-line heredoc under 2s" "$(bash_payload $E "$heredoc")"
timed allow "19 200 cp segments under 2s"  "$(bash_payload $E "$copies")"

# Fix round 2: quote state carries across lines; long lines; risky cd.
check deny  "21 << inside a multi-line double-quoted string" "$(bash_payload $S "echo \"x${nl}<<true\"${nl}gh pr merge 1${nl}true")"
check deny  "21 << inside a multi-line single-quoted string" "$(bash_payload $S "echo 'a${nl}<<EOF'${nl}gh pr merge 1${nl}EOF")"
check deny  "21 quoted delimiter spanning lines" "$(bash_payload $S "cat <<'E${nl}' ; gh pr merge 1${nl}E")"
check deny  "21 escaped quote in \$'...'" "$(bash_payload $S "echo \$'a\\' <<EOF${nl}' ; gh pr merge 1${nl}EOF")"
long_line="echo $(printf 'aaaa bbbb <<cc %.0s' $(seq 1 6800))"
timed deny  "22 100 KB line denied under 2s" "$(bash_payload $S "$long_line")"
medium_line="cp $(printf 'src/a.ts \"b\" (c) %.0s' $(seq 1 3000)) src/out"
timed allow "22 60 KB line allowed under 2s" "$(bash_payload $E "$medium_line")"
many_lines=$(for i in $(seq 1 300); do printf 'echo %0250d\n' 0; done)
timed deny  "22 300 KB over many lines denied under 2s" "$(bash_payload $S "$many_lines")"
big_heredoc="cat > $wt/src/big.ts <<'EOF'${nl}$(for i in $(seq 1 400); do printf 'export const v%d = \"%0250d\"\n' "$i" 0; done)${nl}EOF"
timed allow "22 100 KB heredoc body allowed under 2s" "$(bash_payload $E "$big_heredoc")"
check deny  "23 touch inside a risky dir" "$(bash_payload $E "cd $wt/db/migrate && touch add_col")"
check deny  "23 mv inside a risky dir"    "$(bash_payload $E "cd $wt/db/migrate && mv a b")"
check allow "23 read inside a risky dir"  "$(bash_payload $E "cd $wt/db/migrate && ls")"

# 9: fail closed without jq. PATH without jq, keeping bash core utilities.
nojq="$tmp/nojq"; mkdir -p "$nojq"
for tool in bash cat grep sed tr printf dirname; do
  path=$(command -v "$tool" || true); [ -n "$path" ] && ln -s "$path" "$nojq/$tool"
done
out=$(bash_payload $E 'ls' | PATH="$nojq" bash "$guard")
if printf '%s' "$out" | grep -q 'jq is required'; then echo "ok   9 fail closed without jq"; passes=$((passes + 1))
else echo "FAIL 9 fail closed without jq"; echo "     got: $out"; failures=$((failures + 1)); fi

echo "guard: $passes passed, $failures failed"
[ "$failures" = 0 ]
