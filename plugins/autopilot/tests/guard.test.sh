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
# e2e: ops reads run files (config.json) with stderr folded into stdout.
check allow "1 read run file with 2>&1" "$(bash_payload autopilot:ops "cd $wt && bash run-checks.sh $wt/.autopilot/runs/r1/config.json $wt 2>&1 | tail -200")"
check allow "1 read run file with >&2" "$(bash_payload autopilot:ops "bash run-checks.sh $wt/.autopilot/runs/r1/config.json $wt 1>&2")"
check deny  "1 redirect after 2>&1"  "$(bash_payload autopilot:ops "cat x 2>&1 > $wt/.autopilot/runs/r1/units.json")"
check deny  "1 >&file is a write"    "$(bash_payload autopilot:ops "cat x >&$wt/.autopilot/runs/r1/units.json")"
check deny  "2 merge"                "$(bash_payload autopilot:shipper 'gh pr merge 12 --squash')"
check deny  "2 auto-merge"           "$(bash_payload autopilot:shipper 'gh pr merge --auto 12')"
check deny  "2 merge, skeptic"       "$(bash_payload autopilot:skeptic 'gh pr merge 1')"
check deny  "2 merge, review prep"   "$(bash_payload autopilot:review-prep 'gh pr merge 1')"
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
check deny  "32 stack merge"          "$(bash_payload $E 'gh stack merge')"
check deny  "32 stack merge with flag" "$(bash_payload $E 'gh stack -R a/b merge 3')"
check deny  "32 stack submit --auto"  "$(bash_payload $E 'gh stack submit --auto')"
check deny  "32 stack flag before subcommand" "$(bash_payload $E 'gh stack --auto submit')"
check deny  "32 stack submit"         "$(bash_payload $E 'gh stack submit')"
check deny  "32 stack push"           "$(bash_payload $E 'gh stack push')"
check deny  "32 stack after cd"       "$(bash_payload $E 'cd x && gh stack sync')"
check allow "32 stack view"           "$(bash_payload $E 'gh stack view')"
check allow "32 stack list"           "$(bash_payload $E 'gh stack list')"
check allow "32 stack help"           "$(bash_payload $E 'gh stack --help')"
check deny  "32 stack api merge"      "$(bash_payload $E 'gh api -X POST repos/o/r/stacks/4/merge')"
check allow "32 stack create via api" "$(bash_payload $E 'gh api -X POST repos/o/r/stacks -f pull_requests[]=1 -f pull_requests[]=2')"
check allow "32 stack add via api"    "$(bash_payload $E 'gh api -X POST repos/o/r/stacks/4/add -f pull_requests[]=3')"
check allow "32 main session stack"   "$(bash_payload '' 'gh stack submit')"
check allow "34 Stack in a PR title"   "$(bash_payload autopilot:shipper 'gh pr create --title "Reset: Stack the counter cards" --body-file /s/U1/pr-body.md')"
check allow "34 stack view with -R"    "$(bash_payload $E 'gh stack -R a/b view')"
check allow "34 stack list with --repo=" "$(bash_payload $E 'gh stack --repo=a/b list')"
check deny  "34 global -R before stack merge" "$(bash_payload $E 'gh -R a/b stack merge 3')"
check deny  "34 -R then submit view"   "$(bash_payload $E 'gh stack -R a/b submit view')"
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
# $4 is the most seconds allowed (default 2); extra arguments are VAR=value
# settings for the guard's environment.
timed() {
  local expectation=$1 label=$2 payload=$3 limit=${4:-2} output seconds verdict
  shift 3; [ $# = 0 ] || shift
  TIMEFORMAT=%R
  seconds=$( { time printf '%s' "$payload" | env "$@" bash "$guard" > "$tmp/timed.out"; } 2>&1 )
  output=$(cat "$tmp/timed.out")
  if [ -z "$output" ]; then verdict=allow
  elif [ "$(grep -c '"permissionDecision":"deny"' "$tmp/timed.out")" = 1 ]; then verdict=deny
  else verdict="unexpected: $output"; fi
  if [ "$verdict" = "$expectation" ] && awk -v s="$seconds" -v max="$limit" 'BEGIN { exit !(s < max) }'; then
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

# Fix round 3: only allowlisted heredoc openers drop their bodies.
IFS= read -r -d '' a1 <<'CMD' || true
(true)# <<EOF
gh pr merge 1
EOF
CMD
IFS= read -r -d '' a2 <<'CMD' || true
echo "$(echo "'")" '<<EOF;' "$(echo "'")"
gh pr merge 1
EOF
CMD
IFS= read -r -d '' a3 <<'CMD' || true
echo "`echo "'"`" '<<EOF;' "`echo "'"`"
gh pr merge 1
EOF
CMD
IFS= read -r -d '' a4 <<'CMD' || true
echo $[1<<EOF ]
gh pr merge 1
EOF
CMD
IFS= read -r -d '' a5 <<'CMD' || true
echo ${x:-<<EOF }
gh pr merge 1
EOF
CMD
IFS= read -r -d '' unquoted_substitution <<'CMD' || true
cat > notes.md <<EOF
$(gh pr merge 1)
EOF
CMD
IFS= read -r -d '' opener_inside_string <<'CMD' || true
echo "a\"
cat <<EOF
"; gh pr merge 1
EOF
CMD
IFS= read -r -d '' joined_terminator <<'CMD' || true
cat <<EOF
EO\
F
gh pr merge 1
EOF
CMD
check deny  "24 A1 comment after )"            "$(bash_payload $S "$a1")"
check deny  "24 A2 \$( ) inside double quotes" "$(bash_payload $S "$a2")"
check deny  "24 A3 backticks inside double quotes" "$(bash_payload $S "$a3")"
check deny  "24 A4 \$[ ] arithmetic"           "$(bash_payload $S "$a4")"
check deny  "24 A5 \${ } expansion"            "$(bash_payload $S "$a5")"
check deny  "24 unquoted body runs \$( )"      "$(bash_payload $S "$unquoted_substitution")"
check deny  "24 opener inside a multi-line string" "$(bash_payload $S "$opener_inside_string")"
check deny  "24 terminator made by a continuation" "$(bash_payload $S "$joined_terminator")"
check allow "24 tee -a heredoc"                "$(bash_payload $E "cd $wt && tee -a src/notes.md <<'EOF'${nl}push to main${nl}EOF")"
flood="$(head -c 65400 < /dev/zero | tr '\0' ';')gh pr merge 1"
timed deny  "25 65,400 ; then a merge denied under 2s" "$(bash_payload $S "$flood")"
continued="$(printf 'a \\\n%.0s' $(seq 1 30000))${nl}gh pr merge 1"
timed deny  "25 30,000 continuation lines denied under 2s" "$(bash_payload $S "$continued")"

# Fix round 4: cd chains stay linear, a deadline fails closed, and lines
# before a heredoc opener cannot redefine its command.
deep=$(printf 'a/%.0s' $(seq 1 100)); deep=${deep%/}
chain1=""; for i in $(seq 1 300); do chain1="${chain1}cd $deep;"; done
chain2=""; for i in $(seq 1 1999); do chain2="${chain2}cd a/../b/../c/../d/../e/f/g;"; done
timed deny  "26 300 deep relative cds then a merge denied under 3s" "$(bash_payload $E "${chain1}gh pr merge 1")" 3
timed deny  "26 1999 dotted relative cds denied under 3s"          "$(bash_payload $E "${chain2}ls")" 3
check allow "26 a few relative cds"  "$(bash_payload $E "cd src && cd ../db && cd .. && ls")"
check deny  "26 relative cd into a risky dir" "$(bash_payload $E "cd $wt/src && cd ../db/./migrate && touch add_col")"
# The guard's jobs are `sleep <deadline>` and, with the test delay, `sleep <delay>`;
# unusual values make them findable. None may outlive the guard.
timed deny  "27 deadline of 1s denies within 2s" "$(bash_payload $E 'ls')" 2 AUTOPILOT_GUARD_DEADLINE_S=1 AUTOPILOT_GUARD_TEST_DELAY_S=93
if grep -q 'guard timed out' "$tmp/timed.out" && ! pgrep -fx 'sleep 93' > /dev/null; then
  echo "ok   27 timed-out job and its sleep are gone"; passes=$((passes + 1))
else
  echo "FAIL 27 timed-out job and its sleep are gone"; echo "     got: $(cat "$tmp/timed.out"); left: $(pgrep -lfx 'sleep 93')"; failures=$((failures + 1))
fi
timed allow "27 normal command under the deadline" "$(bash_payload $E 'ls')" 2 AUTOPILOT_GUARD_DEADLINE_S=97
if ! pgrep -fx 'sleep 97' > /dev/null; then
  echo "ok   27 no timer left after a normal decision"; passes=$((passes + 1))
else
  echo "FAIL 27 no timer left after a normal decision"; echo "     left: $(pgrep -lfx 'sleep 97')"; failures=$((failures + 1))
fi
check deny  "28 hash -p before heredoc"   "$(bash_payload $S "hash -p /bin/bash cat${nl}cat <<EOF${nl}gh pr merge 1${nl}EOF")"
check deny  "28 alias before heredoc"     "$(bash_payload $S "shopt -s expand_aliases; alias cat=bash${nl}cat <<EOF${nl}gh pr merge 1${nl}EOF")"
check deny  "28 PATH before heredoc"      "$(bash_payload $S "export PATH=/evil:/bin${nl}cat <<EOF${nl}gh pr merge 1${nl}EOF")"
check deny  "28 function before heredoc"  "$(bash_payload $S "function cat { bash; }${nl}cat <<EOF${nl}gh pr merge 1${nl}EOF")"
check deny  "28 enable -n before heredoc" "$(bash_payload $S "enable -n cat${nl}cat <<EOF${nl}gh pr merge 1${nl}EOF")"
check allow "28 cd before heredoc"        "$(bash_payload $S "cd $wt${nl}cat > src/notes.md <<'EOF'${nl}gh pr merge 1${nl}EOF")"

# Fix round 5: the verdict is the job's exit status, job children never
# outlive the guard, and only blank, comment and cd lines may precede an
# allowlisted heredoc opener.
# Runs the guard under a 0-byte file size limit, so the job cannot write its
# reason file: with SIGXFSZ ignored the write fails, by default it kills the job.
check_full() {
  local expectation=$1 label=$2 payload=$3 prelude=$4 output
  output=$(printf '%s' "$payload" | bash -c "$prelude; exec bash \"\$0\"" "$guard")
  if printf '%s' "$output" | grep -q "\"permissionDecision\":\"deny\".*$expectation"; then
    echo "ok   $label"; passes=$((passes + 1))
  else echo "FAIL $label"; echo "     expected deny with '$expectation', got: $output"; failures=$((failures + 1)); fi
}
check_full "tool call denied" "29 merge denied generically when the reason file cannot be written (XFSZ ignored)" "$(bash_payload $S 'gh pr merge 1')" "ulimit -f 0; trap '' XFSZ"
check_full "tool call denied" "29 rm test denied generically when the reason file cannot be written (XFSZ ignored)" "$(bash_payload $E 'rm src/a.test.ts')" "ulimit -f 0; trap '' XFSZ"
check_full "guard error"  "29 merge denied when the job dies writing the reason (default XFSZ)" "$(bash_payload $S 'gh pr merge 1')" "ulimit -f 0"
check_full "guard error"  "29 merge denied when the job dies writing (XFSZ reset to default)" "$(bash_payload $S 'gh pr merge 1')" "ulimit -f 0; trap - XFSZ"
# A job shell killed by TERM leaves its sleep behind unless the parent kills the group.
AUTOPILOT_GUARD_DEADLINE_S=95 AUTOPILOT_GUARD_TEST_DELAY_S=91 bash "$guard" <<< "$(bash_payload $E 'ls')" > "$tmp/term.out" &
guard_pid=$!
for _ in $(seq 1 50); do sleep_pid=$(pgrep -fx 'sleep 91' || true); [ -n "$sleep_pid" ] && break; sleep 0.1; done
job_pid=$(ps -o ppid= -p "$sleep_pid" | tr -d ' ')
kill -TERM "$job_pid"
wait "$guard_pid" || true
if grep -q 'guard error' "$tmp/term.out" && ! pgrep -fx 'sleep 91' > /dev/null && ! pgrep -fx 'sleep 95' > /dev/null; then
  echo "ok   30 TERM to the job shell: denied, sleep and timer gone"; passes=$((passes + 1))
else
  echo "FAIL 30 TERM to the job shell: denied, sleep and timer gone"; echo "     got: $(cat "$tmp/term.out"); left: $(pgrep -lfx 'sleep 9[15]')"; failures=$((failures + 1))
  pkill -fx 'sleep 9[15]' || true
fi
check deny  "31 printf -v PATH before heredoc" "$(bash_payload $S "printf -v PATH /evil${nl}cat <<EOF${nl}gh pr merge 1${nl}EOF")"
check deny  "31 read PATH before heredoc"      "$(bash_payload $S "read PATH < f${nl}cat <<EOF${nl}gh pr merge 1${nl}EOF")"
check deny  "31 mapfile PATH before heredoc"   "$(bash_payload $S "mapfile -t PATH < f${nl}cat <<EOF${nl}gh pr merge 1${nl}EOF")"
check deny  "31 any other command before heredoc" "$(bash_payload $S "ls${nl}cat <<EOF${nl}gh pr merge 1${nl}EOF")"
check allow "31 comment and blank before heredoc" "$(bash_payload $S "# notes${nl}${nl}cd $wt${nl}cat > src/notes.md <<'EOF'${nl}gh pr merge 1${nl}EOF")"
# A comment line never continues in bash, even when it ends in a backslash,
# so it cannot fold the next line into the clean prelude.
check deny  "33 comment backslash hides a function before heredoc" "$(bash_payload $S "# note \\${nl}cat() { bash; }${nl}cat > f <<'EOF'${nl}git push --force origin main${nl}EOF")"
check deny  "33 comment backslash then merge" "$(bash_payload $S "# x \\${nl}gh pr merge 1")"

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
