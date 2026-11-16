#!/usr/bin/env bash
# Tests hooks/check-installed.sh: its three states (rules missing, rules stale with no stamp or a
# stamp for another version, rules current), the folder it checks (the payload's `cwd`, not the
# one it was started in), a stale copy in the home folder beside or without a project copy, and
# saying each state once per session. With KC_CONVENTIONS_AUTO_INSTALL=0 (the setting for the
# report-only cases up to the "auto-install" section) the hook only reports; the last section
# covers what it does by default: install or refresh the home copy, never touch a project's files,
# report a failed install and still exit 0.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
hook="$(dirname "$tests_dir")/hooks/check-installed.sh"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

mkdir -p "$work_dir/plugin/.claude-plugin" "$work_dir/home" "$work_dir/project/.git" "$work_dir/spare" "$work_dir/data"
printf '{\n  "name": "conventions",\n  "version": "9.8.7"\n}\n' > "$work_dir/plugin/.claude-plugin/plugin.json"

failures=0
cases=0
# What the helpers export as KC_CONVENTIONS_AUTO_INSTALL; empty leaves it unset (the default).
auto_setting=0
home_dir="$work_dir/home"
# Runs the hook from <start dir> with <payload> on stdin (empty: run by hand, no payload).
run_hook_from() {
  local start_dir=$1 payload=$2
  (cd "$start_dir" && printf '%s' "$payload" \
    | run_env bash "$hook")
}
run_env() {
  if [ -n "$auto_setting" ]; then
    env HOME="$home_dir" KC_CONVENTIONS_AUTO_INSTALL="$auto_setting" CLAUDE_PLUGIN_ROOT="$work_dir/plugin" CLAUDE_PLUGIN_DATA="$work_dir/data" "$@"
  else
    env -u KC_CONVENTIONS_AUTO_INSTALL HOME="$home_dir" CLAUDE_PLUGIN_ROOT="$work_dir/plugin" CLAUDE_PLUGIN_DATA="$work_dir/data" "$@"
  fi
}
expect_output() {
  local label=$1 expected=$2 actual=$3
  cases=$((cases + 1))
  if [ "$actual" = "$expected" ]; then
    echo "ok   $label"
  else
    echo "FAIL $label"
    echo "     expected: $expected"
    echo "     actual:   $actual"
    failures=$((failures + 1))
  fi
}
payload_for() { printf '{"session_id":"%s","cwd":"%s","prompt":"hello"}' "$1" "$2"; }

not_installed="The portable coding conventions are not installed in this project. Run /kc-conventions:kc-init to copy them into .claude/rules/, or say so if this project should not have them."
project_stale="The portable coding conventions in .claude/rules are from kc-conventions plugin 1.0.2, but 9.8.7 is installed: the older rules may lack steps the newer plugins rely on. Run /kc-conventions:kc-init to refresh them."
home_stale="The portable coding conventions in $work_dir/home/.claude/rules are from kc-conventions plugin 1.0.2, but 9.8.7 is installed: the older rules may lack steps the newer plugins rely on. Refresh them with: bash \"$work_dir/plugin/scripts/install-rules.sh\" --dest \"$work_dir/home/.claude/rules\""

# Run by hand in the project, no payload.
expect_output "missing: no rules installed" "$not_installed" "$(run_hook_from "$work_dir/project" "")"

mkdir -p "$work_dir/project/.claude/rules"
touch "$work_dir/project/.claude/rules/kc-working-agreement.md"
expect_output "stale: rules without a version stamp" \
  "The portable coding conventions in .claude/rules carry no version stamp, so they may predate kc-conventions plugin 9.8.7. Run /kc-conventions:kc-init to refresh them." \
  "$(run_hook_from "$work_dir/project" "")"

echo "1.0.2" > "$work_dir/project/.claude/rules/.kc-conventions-version"
expect_output "stale: stamp for an older version" "$project_stale" "$(run_hook_from "$work_dir/project" "")"

# The session started in a spare folder with no .git and moved to the project: the payload's
# cwd is the folder checked.
expect_output "payload cwd: checks the project the session is in, not the folder it was started in" \
  "$project_stale" "$(run_hook_from "$work_dir/spare" "$(payload_for s1 "$work_dir/project")")"
expect_output "once: the same state is not repeated in the same session" \
  "" "$(run_hook_from "$work_dir/spare" "$(payload_for s1 "$work_dir/project")")"
expect_output "once: another session is told" \
  "$project_stale" "$(run_hook_from "$work_dir/spare" "$(payload_for s2 "$work_dir/project")")"

expect_output "payload cwd that is no folder: checks the folder the hook was started in" \
  "$project_stale" "$(run_hook_from "$work_dir/project" "$(payload_for s6 "$work_dir/gone")")"

# A session id is the marker's file name: one that would name a path outside the marker folder
# counts as no id, so nothing is written and the notice is said each time.
escaping_payload=$(payload_for ../../escaped "$work_dir/project")
expect_output "session id with a path in it: told" "$project_stale" "$(run_hook_from "$work_dir/spare" "$escaping_payload")"
expect_output "session id with a path in it: told again, no marker kept" "$project_stale" "$(run_hook_from "$work_dir/spare" "$escaping_payload")"
expect_output "session id with a path in it: nothing written outside the marker folder" \
  "" "$(find "$work_dir" -name escaped)"

# A plugin.json with no version gives nothing to compare a stamp against.
printf '{\n  "name": "conventions"\n}\n' > "$work_dir/plugin/.claude-plugin/plugin.json"
expect_output "plugin with no version: quiet" "" "$(run_hook_from "$work_dir/project" "")"
printf '{\n  "name": "conventions",\n  "version": "9.8.7"\n}\n' > "$work_dir/plugin/.claude-plugin/plugin.json"

echo "9.8.7" > "$work_dir/project/.claude/rules/.kc-conventions-version"
expect_output "current: stamp matches the plugin" "" "$(run_hook_from "$work_dir/project" "")"
expect_output "current: nothing said with a payload either" \
  "" "$(run_hook_from "$work_dir/spare" "$(payload_for s3 "$work_dir/project")")"

# A copy in the home folder serves every project; it is checked where there is no project copy,
# in a folder with no .git too, and the notice names the command that refreshes it in place.
mkdir -p "$work_dir/home/.claude/rules"
touch "$work_dir/home/.claude/rules/kc-working-agreement.md"
echo "1.0.2" > "$work_dir/home/.claude/rules/.kc-conventions-version"
expect_output "home copy: stale, in a folder that is no project" \
  "$home_stale" "$(run_hook_from "$work_dir/spare" "$(payload_for s4 "$work_dir/spare")")"
rm "$work_dir/home/.claude/rules/.kc-conventions-version"
unstamped_home_output=$(run_hook_from "$work_dir/spare" "$(payload_for s4 "$work_dir/spare")")
expect_output "home copy: a new state in the same session is told again" \
  "The portable coding conventions in $work_dir/home/.claude/rules carry no version stamp, so they may predate kc-conventions plugin 9.8.7. Refresh them with: bash \"$work_dir/plugin/scripts/install-rules.sh\" --dest \"$work_dir/home/.claude/rules\"" \
  "$unstamped_home_output"

# A session loads the home copy beside the project's, so a current project copy does not hide a
# stale home copy, and two stale copies are each named.
echo "1.0.2" > "$work_dir/home/.claude/rules/.kc-conventions-version"
expect_output "both copies: project current, home stale" \
  "$home_stale" "$(run_hook_from "$work_dir/spare" "$(payload_for s7 "$work_dir/project")")"
echo "1.0.2" > "$work_dir/project/.claude/rules/.kc-conventions-version"
expect_output "both copies: both stale, each named" \
  "$project_stale
$home_stale" "$(run_hook_from "$work_dir/spare" "$(payload_for s8 "$work_dir/project")")"
expect_output "home folder itself: its copy is named once, as the home copy" \
  "$home_stale" "$(run_hook_from "$work_dir/spare" "$(payload_for s9 "$work_dir/home")")"
echo "9.8.7" > "$work_dir/project/.claude/rules/.kc-conventions-version"
rm -rf "$work_dir/home/.claude"

# A caller that keeps stdin open and sends nothing must not hang the hook: stdin here is a pipe
# whose writer stays silent for SILENT_WRITER_SECONDS, longer than HOOK_RETURN_LIMIT_SECONDS (the
# hook's timeout in hooks.json), so a hook that waits for it fails the time check below instead of
# hanging the suite.
readonly SILENT_WRITER_SECONDS=15
readonly HOOK_RETURN_LIMIT_SECONDS=10
mkfifo "$work_dir/held-open"
run_with_open_stdin() {
  local silent_writer
  sleep "$SILENT_WRITER_SECONDS" > "$work_dir/held-open" &
  silent_writer=$!
  (cd "$work_dir/project" \
    && run_env bash "$hook" \
      < "$work_dir/held-open")
  kill "$silent_writer" 2>/dev/null
  wait "$silent_writer" 2>/dev/null || true
}
started=$SECONDS
echo "1.0.2" > "$work_dir/project/.claude/rules/.kc-conventions-version"
expect_output "open stdin, no payload: checks the current folder and speaks, as when run by hand" \
  "$project_stale" "$(run_with_open_stdin)"
echo "9.8.7" > "$work_dir/project/.claude/rules/.kc-conventions-version"
expect_output "open stdin, no payload: quiet when current" "" "$(run_with_open_stdin)"
returned_in_time=no
[ $((SECONDS - started)) -lt "$HOOK_RETURN_LIMIT_SECONDS" ] && returned_in_time=yes
expect_output "open stdin, no payload: both runs returned within the hook's timeout" yes "$returned_in_time"

expect_output "no project, nothing installed: quiet" \
  "" "$(run_hook_from "$work_dir/spare" "$(payload_for s5 "$work_dir/spare")")"

# A session in a subfolder of a project is told about the project: its copy, or that it has none.
git init -q "$work_dir/repo"
mkdir -p "$work_dir/repo/src/pages"
expect_output "subfolder of a project, nothing installed: told, naming the folder to install from" \
  "The portable coding conventions are not installed in this project. Run /kc-conventions:kc-init from $work_dir/repo to copy them into .claude/rules/, or say so if this project should not have them." "$(run_hook_from "$work_dir/spare" "$(payload_for s11 "$work_dir/repo/src/pages")")"
mkdir -p "$work_dir/repo/.claude/rules"
touch "$work_dir/repo/.claude/rules/kc-working-agreement.md"
echo "1.0.2" > "$work_dir/repo/.claude/rules/.kc-conventions-version"
expect_output "subfolder of a project: the copy at the project's root is checked and named" \
  "The portable coding conventions in $work_dir/repo/.claude/rules are from kc-conventions plugin 1.0.2, but 9.8.7 is installed: the older rules may lack steps the newer plugins rely on. Run /kc-conventions:kc-init from $work_dir/repo to refresh them." "$(run_hook_from "$work_dir/spare" "$(payload_for s12 "$work_dir/repo/src/pages")")"
mkdir -p "$work_dir/repo/src/.claude/rules"
touch "$work_dir/repo/src/.claude/rules/kc-working-agreement.md"
echo "9.8.7" > "$work_dir/repo/src/.claude/rules/.kc-conventions-version"
expect_output "subfolder with a copy of its own: that copy is the one checked" \
  "" "$(run_hook_from "$work_dir/spare" "$(payload_for s13 "$work_dir/repo/src")")"
expect_output "subfolder below a folder with a copy: the nearest copy is the one checked, not the root's" \
  "" "$(run_hook_from "$work_dir/spare" "$(payload_for s14 "$work_dir/repo/src/pages")")"

# A git worktree's .git is a file, and it is a project all the same.
mkdir -p "$work_dir/worktree" && echo "gitdir: $work_dir/project/.git/worktrees/w" > "$work_dir/worktree/.git"
expect_output "worktree, nothing installed: told" \
  "$not_installed" "$(run_hook_from "$work_dir/spare" "$(payload_for s10 "$work_dir/worktree")")"

# --- auto-install (the default): the hook installs or refreshes the home copy itself ---
auto_setting=""
mkdir -p "$work_dir/plugin/scripts" "$work_dir/plugin/rules"
cp "$(dirname "$tests_dir")/scripts/install-rules.sh" "$work_dir/plugin/scripts/"
echo "always on" > "$work_dir/plugin/rules/kc-working-agreement.md"
echo "scoped" > "$work_dir/plugin/rules/kc-naming.md"
fresh_home() { rm -rf "$work_dir/h" && mkdir -p "$work_dir/h" && home_dir="$work_dir/h"; }
installed_line() {
  echo "Installed the portable coding conventions in $work_dir/h/.claude/rules (kc-conventions plugin 9.8.7); they load from the next session. Set KC_CONVENTIONS_AUTO_INSTALL=0 in the environment or in ~/.claude/settings.json env to stop this."
}

# Nothing anywhere: installed into HOME with the stamp, one line, in a project and out of one.
fresh_home
rm -rf "$work_dir/project/.claude"
expect_output "auto: nothing installed, installs into the home folder and says so"   "$(installed_line)" "$(run_hook_from "$work_dir/project" "$(payload_for a1 "$work_dir/project")")"
expect_output "auto: the home copy has both rules and the stamp"   "9.8.7 kc-naming.md kc-working-agreement.md"   "$(cat "$work_dir/h/.claude/rules/.kc-conventions-version") $(cd "$work_dir/h/.claude/rules" && find . -maxdepth 1 -name "*.md" -exec basename {} \; | sort | tr "\n" " " | sed "s/ $//")"
expect_output "auto: nothing is written into the project" "" "$(find "$work_dir/project" -mindepth 1 -maxdepth 1 ! -name .git -exec basename {} \;)"
expect_output "auto: current afterwards, silent" "" "$(run_hook_from "$work_dir/project" "$(payload_for a2 "$work_dir/project")")"
fresh_home
expect_output "auto: installs where there is no project too"   "$(installed_line)" "$(run_hook_from "$work_dir/spare" "$(payload_for a3 "$work_dir/spare")")"
expect_output "auto: said once per session" "" "$(rm -rf "$work_dir/h/.claude"; run_hook_from "$work_dir/spare" "$(payload_for a3 "$work_dir/spare")")"

# Stale or unstamped home copy: refreshed in place.
fresh_home
mkdir -p "$work_dir/h/.claude/rules"
echo "old" > "$work_dir/h/.claude/rules/kc-working-agreement.md"
echo "1.0.2" > "$work_dir/h/.claude/rules/.kc-conventions-version"
expect_output "auto: stale home copy is refreshed and says so"   "$(installed_line | sed 's/^Installed/Refreshed/')" "$(run_hook_from "$work_dir/spare" "$(payload_for a4 "$work_dir/spare")")"
expect_output "auto: the refreshed home copy matches the plugin"   "always on 9.8.7" "$(cat "$work_dir/h/.claude/rules/kc-working-agreement.md") $(cat "$work_dir/h/.claude/rules/.kc-conventions-version")"
rm "$work_dir/h/.claude/rules/.kc-conventions-version"
expect_output "auto: unstamped home copy is refreshed"   "$(installed_line | sed 's/^Installed/Refreshed/')" "$(run_hook_from "$work_dir/spare" "$(payload_for a5 "$work_dir/spare")")"

# Stale project copy: reported as before, files untouched; the stale home copy beside it is refreshed.
mkdir -p "$work_dir/project/.claude/rules"
echo "project edit" > "$work_dir/project/.claude/rules/kc-working-agreement.md"
echo "1.0.2" > "$work_dir/project/.claude/rules/.kc-conventions-version"
expect_output "auto: stale project copy is reported, not rewritten" "$project_stale"   "$(run_hook_from "$work_dir/project" "$(payload_for a6 "$work_dir/project")")"
expect_output "auto: the project's files are untouched"   "project edit 1.0.2" "$(cat "$work_dir/project/.claude/rules/kc-working-agreement.md") $(cat "$work_dir/project/.claude/rules/.kc-conventions-version")"
echo "1.0.2" > "$work_dir/h/.claude/rules/.kc-conventions-version"
expect_output "auto: stale project copy and stale home copy: project reported, home refreshed"   "$project_stale
$(installed_line | sed 's/^Installed/Refreshed/')" "$(run_hook_from "$work_dir/project" "$(payload_for a7 "$work_dir/project")")"
expect_output "auto: project copy only (no home copy), current: nothing installed, silent" ""   "$(echo 9.8.7 > "$work_dir/project/.claude/rules/.kc-conventions-version"; fresh_home; run_hook_from "$work_dir/project" "$(payload_for a8 "$work_dir/project")"; ls -A "$work_dir/h")"

# Opt-out: report only, nothing written.
fresh_home
rm -rf "$work_dir/project/.claude"
auto_setting=0
expect_output "opt-out: nothing installed is reported, not installed" "$not_installed"   "$(run_hook_from "$work_dir/project" "$(payload_for a9 "$work_dir/project")")"
expect_output "opt-out: nothing written to the home folder" "" "$(ls -A "$work_dir/h")"
mkdir -p "$work_dir/h/.claude/rules"
echo "old" > "$work_dir/h/.claude/rules/kc-working-agreement.md"
echo "1.0.2" > "$work_dir/h/.claude/rules/.kc-conventions-version"
expect_output "opt-out: stale home copy is reported with the manual command" "${home_stale//$work_dir/home/$work_dir/h}"   "$(run_hook_from "$work_dir/spare" "$(payload_for a10 "$work_dir/spare")")"
expect_output "opt-out: stale home copy left as it was" "old 1.0.2"   "$(cat "$work_dir/h/.claude/rules/kc-working-agreement.md") $(cat "$work_dir/h/.claude/rules/.kc-conventions-version")"

# A failed install says so with the manual command, writes nothing, and exits 0.
auto_setting=""
fresh_home
mv "$work_dir/plugin/rules" "$work_dir/plugin/rules.away"
failed_output=$(run_hook_from "$work_dir/project" "$(payload_for a11 "$work_dir/project")")
failed_status=0
(cd "$work_dir/project" && run_env bash "$hook" < /dev/null > /dev/null) || failed_status=$?
mv "$work_dir/plugin/rules.away" "$work_dir/plugin/rules"
expect_output "failure: names the error and the manual command"   "Could not install the portable coding conventions into $work_dir/h/.claude/rules: install-rules.sh: no rules found at $work_dir/plugin/rules/*.md; reinstall the kc-conventions plugin rather than building a path by hand. Install them by hand with: bash \"$work_dir/plugin/scripts/install-rules.sh\" --dest \"$work_dir/h/.claude/rules\"" \
  "$failed_output"
expect_output "failure: the hook still exits 0" "0" "$failed_status"

echo "$((cases - failures)) passed, $failures failed"
[ "$failures" -eq 0 ]
