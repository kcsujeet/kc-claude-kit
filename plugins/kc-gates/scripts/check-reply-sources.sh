#!/usr/bin/env bash
# Stop hook: holds back a reply that states something it never checked in this turn, for the two
# kinds of claim a script can tell apart from the turn's own tool calls:
#
#   - A claim about what a set of instructions says (the kit, a working agreement, a checklist, a
#     repo's CLAUDE.md, a rule or skill): "the kit doesn't require...", "the rules already say...".
#     The turn must have read an instructions file (a Read, Grep or shell command naming a rules or
#     skills folder, CLAUDE.md, AGENTS.md, SKILL.md, a .claude folder or the kit's plugins).
#   - A command handed to the person, in a shell code block, for a CLI that acts on an account
#     (a payments, hosting, cloud or code-host CLI). The turn must have run that CLI itself (an
#     auth status, a config listing, a read-only list) or read its config, so a missing login, key
#     or permission is found before the person runs into it.
#
# The working agreement already asks for both ("A claim needs a check behind it"); this is the
# trigger that makes the check happen. It can't tell whether what was read supports the claim,
# only that nothing was read.
#
# A held-back reply gets the reason and one more try: when Claude Code is already continuing
# because of a stop hook (`stop_hook_active`), the reply goes out, so a reply that explains why it
# can't check (a CLI the session may not run) is never held twice.
#
# Input: the Stop payload on stdin (`last_assistant_message`, `transcript_path`,
# `stop_hook_active`). Output: `{"decision":"block","reason":...}` or nothing. Always exits 0, and
# lets the reply out when jq or the transcript is missing. Hook schema:
# https://code.claude.com/docs/en/hooks
set -u

# CLIs that act on an account: a key, a login or a permission decides whether a command works.
readonly ACCOUNT_CLIS='stripe|wrangler|gh|aws|gcloud|az|fly|flyctl|vercel|netlify|heroku|firebase|supabase|doctl|railway|render'

# A sentence that says what instructions hold, require or lack.
readonly INSTRUCTIONS_CLAIM='(the kit|kit.s|kc-[a-z]+|working agreement|hand-off checklist|checklist|claude\.md|agents\.md|the rules?|a rule|skill)[^.!?]{0,80}(says|say|requires?|needs?|asks? for|forbids?|allows?|already|has no|have no|does not|doesn.t|is not|isn.t|are not|aren.t|can.t|cannot|only)'

# What reading instructions looks like in a tool call's path or command.
readonly INSTRUCTIONS_SOURCE='kc-claude-kit|plugins/kc-|(^|/)rules/|/skills/|(^|/)\.claude/|CLAUDE\.md|AGENTS\.md|SKILL\.md'

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
[ "$(printf '%s' "$payload" | jq -r '.stop_hook_active // false')" = true ] && exit 0
reply=$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty')
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty')
[ -n "$reply" ] && [ -r "$transcript" ] || exit 0

# The tool calls since the person's last typed message, one per line: the name, a tab, then the
# path or command it was given.
turn_tool_calls=$(jq -rs '
  def typed: .type == "user" and (.isMeta | not) and (.isCompactSummary | not)
    and ((.message.content | type) == "string"
      or ([.message.content[]? | select(.type == "text")] | length) > 0)
    and ([.message.content[]? | select(.type == "tool_result")] | length) == 0
    and ((if (.message.content | type) == "string" then .message.content
          else ([.message.content[]? | select(.type == "text") | .text] | join(" ")) end)
         | test("^(<system-reminder>|<task-notification>|<local-command|<command-name>|Caveat: )") | not);
  (map(typed) | rindex(true) // -1) as $start
  | .[($start + 1):][]
  | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")
  | .name + "\t" + ((.input.file_path // .input.path // .input.command // .input.pattern // "") | tostring | gsub("\n"; " "))
' "$transcript" 2>/dev/null) || exit 0

reasons=()

if printf '%s' "$reply" | grep -Eiq "$INSTRUCTIONS_CLAIM" \
  && ! printf '%s\n' "$turn_tool_calls" | grep -Eq "$INSTRUCTIONS_SOURCE"; then
  reasons+=("This reply says what instructions hold or require (the kit, a rule, a checklist, CLAUDE.md), and nothing in this turn read them. Read the rule it is about and cite its file and line, or drop the claim.")
fi

# The CLI each command in a shell code block starts with, after a runner such as bunx or sudo.
handed_clis=$(printf '%s\n' "$reply" | awk '
  /^[[:space:]]*```(bash|sh|shell|zsh|console)?[[:space:]]*$/ { inside = !inside; next }
  inside { print }
' | sed -E 's/^[[:space:]]*(\$[[:space:]]+)?//; s/^((sudo|bunx|npx|pnpx|pnpm dlx|yarn dlx|bun x)[[:space:]]+)+//' \
  | grep -Eo "^($ACCOUNT_CLIS)([[:space:]]|$)" | tr -d '[:space:]' | sort -u)

tab=$'\t'
unchecked_clis=()
for cli in $handed_clis; do
  printf '%s\n' "$turn_tool_calls" | grep -Eq "(^Bash${tab}(.*[^[:alnum:]_/.-])?$cli([[:space:]]|$))|(/\.config/$cli|/\.$cli)" \
    || unchecked_clis+=("$cli")
done
if [ "${#unchecked_clis[@]}" -gt 0 ]; then
  reasons+=("This reply hands the person a ${unchecked_clis[*]} command, and this turn never ran ${unchecked_clis[*]} or read its config. Check what the command needs that you can see (the login, the keys and what they may do, the account it acts on) with a read-only command, fix what is missing first, or say in the reply why you can't check.")
fi

[ "${#reasons[@]}" -gt 0 ] || exit 0
jq -n --arg reason "${reasons[*]}" '{decision: "block", reason: $reason}'
