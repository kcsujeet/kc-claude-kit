#!/usr/bin/env bash
# UserPromptSubmit hook: says when the convention rules are missing from the project, or when the
# project's copy or the home folder's is older than the installed plugin, once per session and
# state. Says nothing when they are installed and current, so the normal case costs no context.
# Bash 3.2 compatible, and reads JSON without jq.
#
# It runs on the first prompt, not at SessionStart. A SessionStart hook runs in the folder the
# session started in, which need not be the project (an app can start a session in a spare folder
# and move it), and one registered `async` has no stated route into the model's context; a
# UserPromptSubmit hook's stdout is added as context, and its payload names the folder the session
# is in now (https://code.claude.com/docs/en/hooks).
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

readonly RULE_FILE=kc-working-agreement.md
project_rules_dir=".claude/rules"
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
    echo "The portable coding conventions in $rules_dir are from kc-conventions plugin $installed_version, but $plugin_version is installed: this session loaded the older rules, which may lack steps the newer plugins rely on. $refresh"
  fi
}

if [ ! -f "$project_rules_dir/$RULE_FILE" ] && [ ! -f "$home_rules_dir/$RULE_FILE" ]; then
  # Not a project directory: nothing to install the rules into. A worktree's .git is a file.
  [ -e .git ] || exit 0
  notice="The portable coding conventions are not installed in this project. Run /kc-conventions:kc-init to copy them into .claude/rules/, or say so if this project should not have them."
else
  # Without a readable plugin version there is nothing to compare against.
  [ -n "$plugin_version" ] || exit 0
  # A session loads the home copy beside the project's, so each is checked. /kc-conventions:kc-init
  # installs into the project; the home copy is refreshed in place.
  notice=$(
    print_stale_notice "$project_rules_dir" "Run /kc-conventions:kc-init to refresh them."
    print_stale_notice "$home_rules_dir" "Refresh them with: bash \"$plugin_root/scripts/install-rules.sh\" --dest \"$home_rules_dir\""
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
