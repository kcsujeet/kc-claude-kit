#!/usr/bin/env bash
# UserPromptSubmit hook: says when the convention rules are missing from the project or older than
# the installed plugin, once per session and state. Says nothing when they are installed and
# current, so the normal case costs no context. Bash 3.2 compatible, and reads JSON without jq.
#
# It runs on the first prompt, not at SessionStart. A SessionStart hook runs in the folder the
# session started in, which need not be the project (an app can start a session in a spare folder
# and move it), and one registered `async` has no stated route into the model's context; a
# UserPromptSubmit hook's stdout is added as context, and its payload names the folder the session
# is in now (https://code.claude.com/docs/en/hooks). A stale copy went unreported for eleven days
# that way, and the session worked from rules that lacked a step the kit's other hooks cited.
#
# Reads the hook payload from stdin for `cwd` and `session_id`. Run by hand with no payload, it
# checks the current folder and always speaks. A caller that leaves stdin open and sends nothing
# (another script, a test) costs a second's wait, not a hang.
set -u

payload=""
if [ ! -t 0 ]; then
  line=""
  while IFS= read -r -t 1 line || [ -n "$line" ]; do
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
if [ -n "$session_cwd" ] && [ -d "$session_cwd" ]; then
  cd "$session_cwd" || exit 0
fi

rules_dir=""
if [ -f .claude/rules/kc-working-agreement.md ]; then
  rules_dir=".claude/rules"
elif [ -f "$HOME/.claude/rules/kc-working-agreement.md" ]; then
  rules_dir="$HOME/.claude/rules"
fi

plugin_root=${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}

notice=""
if [ -z "$rules_dir" ]; then
  # Not a project directory: nothing to install the rules into.
  [ -d .git ] || exit 0
  notice="The portable coding conventions are not installed in this project. Run /kc-conventions:kc-init to copy them into .claude/rules/, or say so if this project should not have them."
else
  plugin_json="$plugin_root/.claude-plugin/plugin.json"
  [ -f "$plugin_json" ] || exit 0
  plugin_version=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$plugin_json" | head -n 1)
  # Without a readable plugin version there is nothing to compare against.
  [ -n "$plugin_version" ] || exit 0

  stamp_file="$rules_dir/.kc-conventions-version"
  installed_version=""
  [ -f "$stamp_file" ] && installed_version=$(head -n 1 "$stamp_file" | tr -d '[:space:]')
  [ "$installed_version" = "$plugin_version" ] && exit 0

  # /kc-conventions:kc-init installs into the project; a copy in the home folder is refreshed in place.
  refresh="Run /kc-conventions:kc-init to refresh them."
  [ "$rules_dir" = ".claude/rules" ] || refresh="Refresh them with: bash \"$plugin_root/scripts/install-rules.sh\" --dest \"$rules_dir\""
  if [ -z "$installed_version" ]; then
    notice="The portable coding conventions in $rules_dir carry no version stamp, so they may predate kc-conventions plugin $plugin_version. $refresh"
  else
    notice="The portable coding conventions in $rules_dir are from kc-conventions plugin $installed_version, but $plugin_version is installed: this session loaded the older rules, which may lack steps the newer plugins rely on. $refresh"
  fi
fi

# Once per session and state: the same notice on every prompt would be noise, a new state is news.
if [ -n "$session_id" ]; then
  told_file="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}/kc-conventions}/told-installed/$session_id"
  [ "$(cat "$told_file" 2>/dev/null)" != "$notice" ] || exit 0
  mkdir -p "$(dirname "$told_file")"
  printf '%s\n' "$notice" > "$told_file"
fi
echo "$notice"
