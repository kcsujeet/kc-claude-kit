#!/usr/bin/env bash
# PreToolUse hook (Edit, Write, MultiEdit, NotebookEdit): denies the first file change made for a
# reported problem before the problem was reproduced the way the reporter met it
# (kc-conventions:kc-assess step 3). A cause read from code is a guess, and a copy of one layer (a
# template rendered alone, another browser version, a fixture) is not the report; it has to be the
# reporter's own path: same entry point, renderer or runtime and version, environment and
# real-shaped data. The check runs before the edit, while it can still change what Claude does; a
# Stop hook that checked the reply instead ran after the person had read it.
#
# It denies when all of these hold:
#
#   a. Some typed message in the session asked to fix something reported (asks_fix).
#   b. No tool call since the latest such message ran something that exercises the product, and no
#      text Claude wrote since then has a "Not reproduced: <reason>" line (three or more words).
#   c. The file is not a test or spec (writing the failing test is how a problem gets reproduced).
#
# What exercises the product: a Bash or REPL command that starts with a test runner (rspec, jest,
# vitest, pytest, playwright, cypress, go test, cargo test, npm/pnpm/yarn/bun test or run test), a
# runtime or request tool (curl, http, wget, node, python, ruby, rails, php, java), or a browser
# (chrome, chromium); a browser, playwright or puppeteer MCP tool; or a command matching an
# extended-regex line of the repo's optional .claude/reproduce-commands file (one per line, # starts
# a comment; a missing file means the built-ins only). Repo patterns match the stripped command
# (`bin/shop-check x` is `shop-check x`). Reading or searching code (cat, sed, grep, rg, git show,
# log or diff, the Read, Grep and Glob tools) never counts.
#
# "Not reproduced: <reason>" is the honest way out when the problem cannot be run here, or needs no
# run (a typo). A reply that only proposes a cause is not checked: remind-reply-rules.sh tells
# Claude the rule when the prompt asks for a fix.
#
# Input: the PreToolUse payload on stdin. Output: the deny JSON, or nothing. Never denies what it
# can't read: no jq, no transcript or no file path exits 0. Hook schema:
# https://code.claude.com/docs/en/hooks
set -u

# shellcheck source=lib/reply-misses.sh
. "$(dirname "$0")/lib/reply-misses.sh"

# What a command starts with (after list_stripped_commands) when it runs the product or its tests.
readonly RUN_WORDS='(rspec|jest|vitest|pytest|playwright|cypress|curl|http|https|wget|node|python3?|ruby|php|java|rails|chrome|chromium|google-chrome)'
# Whole-command forms: package-manager test scripts, go and cargo tests, a browser opened by open.
readonly RUN_SEGMENTS='^(npm|pnpm|yarn|bun)[[:space:]]+(test|run[[:space:]]+test[^[:space:]]*)([[:space:]]|$)|^(go|cargo)[[:space:]]+test([[:space:]]|$)|^open[[:space:]].*chrom'
readonly BROWSER_TOOL='^mcp__.*(playwright|puppeteer|browser|chrom)'


command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
repo_dir=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
edited_path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
[ "$(printf '%s' "$payload" | jq -r '.hook_event_name // empty' 2>/dev/null)" = PreToolUse ] || exit 0
[ -r "$transcript" ] || exit 0
[ -n "$repo_dir" ] || repo_dir=$PWD

# Writing a test or spec is how a problem gets reproduced.
printf '%s' "$edited_path" | grep -Eiq '(^|/)(tests?|specs?|__tests__)/|\.(test|spec)\.[a-z]+$|_(test|spec)\.[a-z]+$' && exit 0

fix_index=""
while IFS=$'\t' read -r index text; do
  asks_fix "$text" && fix_index=$index
done < <(jq -L "$(dirname "$0")/lib" -rs '
  include "typed-message";
  to_entries[] | select(.value | is_typed_message)
  | "\(.key)\t\([.value | typed_texts] | join(" ") | gsub("[\n\t]"; " "))"
' "$transcript" 2>/dev/null)
[ -n "$fix_index" ] || exit 0

tool_calls_since_fix=$(jq -L "$(dirname "$0")/lib" -rs --argjson from "$fix_index" '
  include "typed-message";
  .[$from + 1:][] | get_tool_call_lines
' "$transcript" 2>/dev/null) || exit 0
written_since_fix=$(jq -rs --argjson from "$fix_index" '
  .[$from + 1:][] | select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text
' "$transcript" 2>/dev/null | tr '[:upper:]' '[:lower:]')

printf '%s\n' "$written_since_fix" | grep -Eq 'not reproduced[*_]*:[[:space:]]*[^[:space:]]+([[:space:]]+[^[:space:]]+){2,}' && exit 0

extra_patterns=""
if [ -r "$repo_dir/.claude/reproduce-commands" ]; then
  extra_patterns=$(sed -e 's/^[[:space:]]*#.*//' -e '/^[[:space:]]*$/d' "$repo_dir/.claude/reproduce-commands")
fi

is_run_command() {
  local command=$1
  printf '%s' "$command" | grep -Eq "^$RUN_WORDS([[:space:]]|\$)" && return 0
  printf '%s' "$command" | grep -Eq "$RUN_SEGMENTS" && return 0
  [ -n "$extra_patterns" ] && printf '%s' "$command" | grep -Eq -f <(printf '%s\n' "$extra_patterns") && return 0
  return 1
}

did_run_product() {
  local tool_name command stripped_command
  while IFS=$'\t' read -r tool_name command; do
    case "$tool_name" in
      mcp__*) printf '%s' "$tool_name" | grep -Eiq "$BROWSER_TOOL" && return 0 ;;
      Bash | REPL)
        # A REPL script runs shell commands inside backtick templates: split on the backticks too.
        [ "$tool_name" = REPL ] && command=$(printf '%s' "$command" | tr '`' ';')
        while IFS= read -r stripped_command; do
          is_run_command "$stripped_command" && return 0
        done < <(printf '%s\n' "$command" | list_stripped_commands)
        ;;
    esac
  done <<EOF
$tool_calls_since_fix
EOF
  return 1
}

did_run_product && exit 0
printf '%s' "Blocked by the kc-gates plugin: this change is for a reported problem, but nothing since the report ran the product, its tests or a browser (reading code does not count). Reproduce the problem the way the reporter met it first: their entry point, renderer or runtime and version, environment and real-shaped data (a copy of one layer, such as a template rendered alone, another browser version or a fixture, is not a reproduction). Then edit again. When it cannot be run here or needs no run, write a Not reproduced: <why> line (at least three words) in a message before the edit, since a line in the same message may not be seen yet (kc-conventions:kc-assess step 3)." \
  | jq -Rsc '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: .}}'
exit 0
