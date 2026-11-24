#!/usr/bin/env bash
# Stop hook: blocks a reply that proposes a cause and a fix for a reported problem before the
# problem was reproduced the way the reporter met it (kc-conventions:kc-assess step 3). A cause read
# from code is a guess, and a copy of one layer (a template rendered alone, another browser version,
# a fixture) is not the report; it has to be the reporter's own path: same entry point, renderer or
# runtime and version, environment and real-shaped data.
#
# It blocks when all of these hold:
#
#   a. Some typed message in the session asked to fix something reported (asks_fix).
#   b. The reply proposes a cause and a fix (proposes_cause_and_fix).
#   c. The reply has no "Reproduced:" or "Not reproduced:" line, or it has a "Reproduced:" line and
#      no tool call since the latest fix-asking message ran something that exercises the product.
#
# A turn that edited files needs a run of the product but no Reproduced: or Not reproduced: line.
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
# "Not reproduced: <reason>" with a reason of three or more words passes: it is the honest way out
# when the problem cannot be run here. On the second try (stop_hook_active) it blocks again only when
# a turn that edited nothing still proposes a cause and a fix with neither line.
#
# Input: the Stop payload on stdin. Output: the block JSON, or nothing. Never blocks what it can't
# read: no jq, no transcript or no reply exits 0. Hook schema: https://code.claude.com/docs/en/hooks
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
reply=$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty' 2>/dev/null)
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
stop_hook_active=$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null)
repo_dir=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$reply" ] || exit 0
[ -r "$transcript" ] || exit 0
[ -n "$repo_dir" ] || repo_dir=$PWD

proposes_cause_and_fix "$reply" || exit 0

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

lower_reply=$(printf '%s\n' "$reply" | tr '[:upper:]' '[:lower:]')
has_reproduction_line=false
names_reproduction "$reply" && has_reproduction_line=true
has_reason=false
printf '%s\n' "$lower_reply" | grep -Eq 'not reproduced[*_]*:[[:space:]]*[^[:space:]]+([[:space:]]+[^[:space:]]+){2,}' && has_reason=true
has_reproduced_line=false
printf '%s\n' "$lower_reply" | sed 's/not reproduced//g' | grep -Eq '(^|[^[:alnum:]])reproduced[*_]*:' && has_reproduced_line=true
has_edited_files=false
printf '%s\n' "$tool_calls_since_fix" | grep -Eq "$EDIT_CALLS" && has_edited_files=true

block_unreproduced_cause() {
  printf '%s' "Blocked by the kc-gates plugin: $1 Reproduce the problem the way the reporter met it before proposing a cause: their entry point, renderer or runtime and version, environment and real-shaped data (a copy of one layer, such as a template rendered alone, another browser version or a fixture, is not a reproduction). Then name the evidence on a Reproduced: line (the failing request, test run or screenshot), or say Not reproduced: <why> (at least three words) when it cannot be run here (kc-conventions:kc-assess step 3)." \
    | jq -Rsc '{decision: "block", reason: .}'
  exit 0
}

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
  local name command stripped_command
  while IFS=$'\t' read -r name command; do
    case "$name" in
      mcp__*) printf '%s' "$name" | grep -Eiq "$BROWSER_TOOL" && return 0 ;;
      Bash | REPL)
        # A REPL script runs shell commands inside backtick templates: split on the backticks too.
        [ "$name" = REPL ] && command=$(printf '%s' "$command" | tr '`' ';')
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

if [ "$has_edited_files" = true ]; then
  [ "$stop_hook_active" = true ] && exit 0
  did_run_product || block_unreproduced_cause "a fix was built without reproducing the problem through the reporter's path: nothing since the report ran the product, its tests or a browser (reading code does not count)."
  exit 0
fi

if [ "$stop_hook_active" = true ]; then
  [ "$has_reproduction_line" = true ] || block_unreproduced_cause "this reply proposes a cause and a fix with no Reproduced: or Not reproduced: line."
  exit 0
fi

[ "$has_reason" = true ] && exit 0
[ "$has_reproduction_line" = true ] || block_unreproduced_cause "this reply proposes a cause and a fix for a reported problem with no Reproduced: or Not reproduced: line."
[ "$has_reproduced_line" = true ] || block_unreproduced_cause "its Not reproduced: line gives no reason (say why in at least three words)."
did_run_product || block_unreproduced_cause "its Reproduced: line has no run behind it: nothing since the report ran the product, its tests or a browser (reading code does not count)."
exit 0
