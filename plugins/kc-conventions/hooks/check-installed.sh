#!/usr/bin/env bash
# UserPromptSubmit hook: plugins cannot ship rules, so the convention rules load only from a copy
# in .claude/rules/. This hook installs that copy where it is safe to, and reports where it is not,
# once per session and state:
#   - no copy in the project or in ~/.claude/rules: installs into ~/.claude/rules with
#     scripts/install-rules.sh and says so in one line (version, how to opt out). It never installs
#     into a project folder: a project copy may be committed and shared, so that stays
#     /kc-conventions:kc-init's job, on request.
#   - the home copy is stale or unstamped: refreshes it in place and says so.
#   - the project copy is stale: reports it, never rewrites a project's files.
#   - KC_CONVENTIONS_AUTO_INSTALL=0 (environment, or `env` in ~/.claude/settings.json, which Claude
#     Code exports to hooks) keeps report-only behaviour: nothing is written.
#   - a failed install prints the error and the manual command; the hook still exits 0.
# Says nothing when the rules are installed and current, so the normal case costs no context.
# Bash 3.2 compatible, and reads JSON without jq.
#
# It runs on the first prompt, not at SessionStart. A SessionStart hook runs in the folder the
# session started in, which need not be the project (an app can start a session in a spare folder
# and move it), and one registered `async` has no stated route into the model's context; a
# UserPromptSubmit hook's stdout is added as context, and its payload names the folder the session
# is in now (https://code.claude.com/docs/en/hooks). From a subfolder it checks the nearest copy
# above it, up to the project's root.
#
# Reads the hook payload from stdin for `cwd` and `session_id`. Run by hand with no payload, it
# checks the current folder and always speaks. A caller that leaves stdin open and sends nothing
# (another script, a test) costs STDIN_WAIT_SECONDS, not a hang.
set -u

readonly STDIN_WAIT_SECONDS=1

payload=""
if [ ! -t 0 ]; then
  line=""
  while IFS= read -r -t "$STDIN_WAIT_SECONDS" line || [ -n "$line" ]; do
    payload="$payload$line "
    line=""
  done
fi
# A top-level string field of the payload. JSON strings hold no raw newlines, so its lines were joined safely.
payload_field() {
  printf '%s' "$payload" \
    | sed -nE 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p'
}
session_cwd=$(payload_field cwd)
session_id=$(payload_field session_id)
# The id names the marker file below; one that could name a path outside its folder counts as none.
case "$session_id" in *[!A-Za-z0-9_-]*) session_id="" ;; esac
if [ -n "$session_cwd" ] && [ -d "$session_cwd" ]; then
  cd "$session_cwd" || exit 0
fi

readonly RULE_FILE=kc-always.md
project_rules_dir=".claude/rules"
# From a subfolder, the copy that counts is the nearest one above it, up to the project's root
# (the folder holding .git). The notice then names that folder, since /kc-conventions:kc-init
# installs into the folder it is run from.
project_dir=$PWD
while [ ! -f "$project_dir/$project_rules_dir/$RULE_FILE" ] && [ ! -e "$project_dir/.git" ] && [ "$project_dir" != / ]; do
  project_dir=$(dirname "$project_dir")
done
from_project_dir=""
if [ "$project_dir" != "$PWD" ] && [ "$project_dir" != / ]; then
  cd "$project_dir" || exit 0
  project_rules_dir="$project_dir/.claude/rules"
  from_project_dir=" from $project_dir"
fi
home_rules_dir="$HOME/.claude/rules"
# In the home folder itself the two are one copy, refreshed as the home copy is.
[ "$project_rules_dir" -ef "$home_rules_dir" ] && project_rules_dir=""

plugin_root=${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
plugin_version=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$plugin_root/.claude-plugin/plugin.json" 2>/dev/null | head -n 1)

# Prints the notice for the copy in <rules dir>, refreshed by <how>; nothing when there is no copy
# there or it is current.
print_stale_notice() {
  local rules_dir=$1 refresh=$2 stamp_file installed_version=""
  [ -n "$rules_dir" ] && [ -f "$rules_dir/$RULE_FILE" ] || return 0
  stamp_file="$rules_dir/.kc-conventions-version"
  [ -f "$stamp_file" ] && installed_version=$(head -n 1 "$stamp_file" | tr -d '[:space:]')
  [ "$installed_version" = "$plugin_version" ] && return 0
  if [ -z "$installed_version" ]; then
    echo "The portable coding conventions in $rules_dir carry no version stamp, so they may predate kc-conventions plugin $plugin_version. $refresh"
  else
    echo "The portable coding conventions in $rules_dir are from kc-conventions plugin $installed_version, but $plugin_version is installed: the older rules may lack steps the newer plugins rely on. $refresh"
  fi
}

# Installs or refreshes the home copy with the plugin's installer. Prints one line saying what it
# did, or the error and the manual command; never fails the hook.
install_home_copy() {
  local what=$1 output status=0
  output=$(bash "$plugin_root/scripts/install-rules.sh" --dest "$home_rules_dir" 2>&1) || status=$?
  if [ "$status" -eq 0 ]; then
    echo "$what the portable coding conventions in $home_rules_dir (kc-conventions plugin $plugin_version); they load from the next session. Set KC_CONVENTIONS_AUTO_INSTALL=0 in the environment or in ~/.claude/settings.json env to stop this."
  else
    echo "Could not install the portable coding conventions into $home_rules_dir: $(printf '%s' "$output" | tail -n 1). Install them by hand with: bash \"$plugin_root/scripts/install-rules.sh\" --dest \"$home_rules_dir\""
  fi
}

auto_install=true
[ "${KC_CONVENTIONS_AUTO_INSTALL:-1}" = 0 ] && auto_install=false

if [ ! -f "$project_rules_dir/$RULE_FILE" ] && [ ! -f "$home_rules_dir/$RULE_FILE" ]; then
  if [ "$auto_install" = true ]; then
    # The home copy serves every project, so it needs no project; a project copy is kc-init's job.
    notice=$(install_home_copy "Installed")
  else
    # Not a project directory: nothing to install the rules into. A worktree's .git is a file.
    [ -e .git ] || exit 0
    notice="The portable coding conventions are not installed in this project. Run /kc-conventions:kc-init$from_project_dir to copy them into .claude/rules/, or say so if this project should not have them."
  fi
else
  # Without a readable plugin version there is nothing to compare against.
  [ -n "$plugin_version" ] || exit 0
  # A session loads the home copy beside the project's, so each is checked. A stale project copy
  # is only reported (it may be committed and shared); a stale home copy is refreshed in place.
  home_installed_version=""
  [ -f "$home_rules_dir/.kc-conventions-version" ] && home_installed_version=$(head -n 1 "$home_rules_dir/.kc-conventions-version" | tr -d '[:space:]')
  notice=$(
    print_stale_notice "$project_rules_dir" "Run /kc-conventions:kc-init$from_project_dir to refresh them."
    if [ "$auto_install" = true ] && [ -f "$home_rules_dir/$RULE_FILE" ] && [ "$home_installed_version" != "$plugin_version" ]; then
      install_home_copy "Refreshed"
    else
      print_stale_notice "$home_rules_dir" "Refresh them with: bash \"$plugin_root/scripts/install-rules.sh\" --dest \"$home_rules_dir\""
    fi
  )
  [ -n "$notice" ] || exit 0
fi

# Once per session and state: the same notice on every prompt would be noise, a new state is news.
if [ -n "$session_id" ]; then
  told_file="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}/kc-conventions}/told-installed/$session_id"
  [ "$(cat "$told_file" 2>/dev/null)" != "$notice" ] || exit 0
  mkdir -p "$(dirname "$told_file")"
  printf '%s\n' "$notice" > "$told_file"
fi
echo "$notice"
