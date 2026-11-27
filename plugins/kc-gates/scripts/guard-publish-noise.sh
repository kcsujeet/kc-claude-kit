#!/usr/bin/env bash
# PreToolUse guard for Bash: text published from a file is read before it goes out. A file filled
# from a command's output (a pull request body read back with the CLI, a commit message from a log,
# release notes from a changelog tool) can carry the tool's own notices with the content, and they
# get published as if they were part of it. It denies a command that publishes a file holding one:
#
#   - gh pr|issue|release create|edit|comment with --body-file / -F <file>, or --notes-file
#   - gh api with a field read from a file (-F body=@<file>, --field body=@<file>)
#   - git commit -F / --file <file>
#
# A notice is a line a command-line tool prints about itself, not content: git's "hint:" and
# "warning:" lines, npm's "npm WARN" and "npm notice", Node's "(node:<pid>)" warnings, a CLI's
# "A new release of ... is available" banner, and terminal colour codes. Read the field raw (an API
# call with a JSON query), check the file, and publish that.
#
# It never blocks what it can't read: no jq, a missing file or an unreadable payload exits 0.
# Output: the PreToolUse deny JSON, or nothing. Hook schema: https://code.claude.com/docs/en/hooks
set -u

scripts_dir=$(dirname "$0")
# shellcheck source=lib/hook-input.sh
. "$scripts_dir/lib/hook-input.sh"

readonly NOTICE_PATTERN='^(hint|warning): |^npm (WARN|notice|ERR!) |^\(node:[0-9]+\) |^A new release of [^ ]+ is available|'$'\033''\[[0-9;]*m'

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
command_text=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$command_text" ] || exit 0
working_dir=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)

is_publishing=false
if printf '%s' "$command_text" | grep -Eq 'gh[[:space:]]+(pr|issue|release)[[:space:]]+(create|edit|comment)|gh[[:space:]]+api[[:space:]]|git[[:space:]]+commit'; then is_publishing=true; fi
$is_publishing || exit 0

# Prints each file the command publishes, one per line.
get_published_files() {
  printf '%s\n' "$command_text" | tr ' ' '\n' | awk '
    take { gsub(/^["\047]|["\047]$/, ""); print; take = 0; next }
    /^(--body-file|--notes-file|-F|--file|--field)$/ { take = 1; next }
    /^--(body-file|notes-file|file)=/ { sub(/^--[a-z-]+=/, ""); gsub(/^["\047]|["\047]$/, ""); print }
  ' | sed -E 's/^[A-Za-z_]+=@//' | grep -v '=' || true
}

while IFS= read -r published_file; do
  [ -n "$published_file" ] || continue
  case "$published_file" in /*) ;; *) [ -z "$working_dir" ] || published_file="$working_dir/$published_file" ;; esac
  [ -f "$published_file" ] || continue
  notice_line=$(grep -Em1 "$NOTICE_PATTERN" "$published_file" 2>/dev/null || true)
  [ -n "$notice_line" ] || continue
  notice_line=$(printf '%s' "$notice_line" | LC_ALL=C tr -d '\000-\037' | cut -c1-80)
  print_pretooluse_deny "Blocked by the kc-gates plugin: $published_file holds a command-line tool's own notice, not content (\"$notice_line\"), so it would be published as part of the text. The file was probably filled from a command's output: read the field raw (an API call with a JSON query), remove the notice, read the file, then publish it."
  exit 0
done < <(get_published_files)
exit 0
