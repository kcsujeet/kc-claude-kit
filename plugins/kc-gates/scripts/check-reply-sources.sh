#!/usr/bin/env bash
# Stop hook: holds back, once, a reply that states something nothing in its turn checked. It is the
# trigger for the working agreement's "A claim needs a check behind it", for the two kinds of
# claim a script can tell from the turn's own tool calls:
#
#   - What instructions say (the kit, a working agreement, a checklist, CLAUDE.md, a rule or
#     skill): the turn must have a tool call naming an instructions file (a rules or skills
#     folder, a .claude folder, CLAUDE.md, AGENTS.md, SKILL.md or the kit's plugins).
#   - A command handed to the person, inside a fenced block, for a CLI that acts on an account
#     (payments, hosting, cloud, code host): the turn must have run that CLI itself, at the start
#     of a command, or named a path in its config folder.
#
# It sees only that such a call happened, not whether it was a read or what it found. A held reply
# goes out on its second try (`stop_hook_active`), so one that explains why it can't check is
# never held twice; the cost of a needless hold is that one retry.
#
# Input: the Stop payload on stdin. Output: `{"decision":"block","reason":...}` or nothing.
# Always exits 0, and lets the reply out when jq or the transcript is missing. Hook schema:
# https://code.claude.com/docs/en/hooks
set -u

# CLIs that act on an account: a key, a login or a permission decides whether a command works.
readonly ACCOUNT_CLIS='stripe|wrangler|gh|aws|gcloud|az|fly|flyctl|vercel|netlify|heroku|firebase|supabase|doctl|railway|render'

# A sentence that says what instructions hold, require or lack.
readonly INSTRUCTIONS_CLAIM='(the kit|kit.s|kc-[a-z]+|working agreement|hand-off checklist|checklist|claude\.md|agents\.md|the rules?|a rule|skill)[^.!?]{0,80}(says|say|requires?|needs?|asks? for|forbids?|allows?|already|has no|have no|does not|doesn.t|is not|isn.t|are not|aren.t|can.t|cannot|only)'

# What reading instructions looks like in a tool call's path or command.
readonly INSTRUCTIONS_SOURCE='kc-claude-kit|plugins/kc-|(^|/)rules/|/skills/|(^|/)\.claude/|CLAUDE\.md|AGENTS\.md|SKILL\.md'

# The first word of each command in each line on stdin: split on && || ; |, then past a `$ `
# prompt, VAR=value assignments and runners (sudo, env, bunx, npx and the like) with their flags.
command_starts() {
  awk '{
    count = split($0, commands, /&&|\|\||;|\|/)
    for (i = 1; i <= count; i++) {
      command = commands[i]
      sub(/^[ \t]*(\$[ \t]+)?/, "", command)
      while (1) {
        if (sub(/^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+/, "", command)) continue
        if (sub(/^(sudo|env|bunx|npx|pnpx|bun x|pnpm dlx|yarn dlx)[ \t]+/, "", command)) {
          while (sub(/^-[^ \t]*[ \t]+/, "", command)) {}
          continue
        }
        break
      }
      split(command, words, /[ \t]+/)
      if (words[1] != "") print words[1]
    }
  }'
}

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
[ "$(printf '%s' "$payload" | jq -r '.stop_hook_active // false')" = true ] && exit 0
reply=$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty')
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty')
[ -n "$reply" ] && [ -r "$transcript" ] || exit 0

# The tool calls since the person's last typed message, one per line: the tool's name, a tab,
# then the path or command it was given.
turn_tool_calls=$(jq -L "$(dirname "$0")/lib" -rs '
  include "typed-message";
  (map(is_typed_message) | rindex(true) // -1) as $start
  | .[($start + 1):][]
  | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")
  | .name + "\t" + ((.input.file_path // .input.path // .input.command // .input.pattern // "") | tostring | gsub("\n"; " "))
' "$transcript" 2>/dev/null) || exit 0

reasons=()

# A claim can wrap across lines, so the reply is matched as one line.
if printf '%s' "$reply" | tr '\n' ' ' | grep -Eiq "$INSTRUCTIONS_CLAIM" \
  && ! printf '%s\n' "$turn_tool_calls" | grep -Eq "$INSTRUCTIONS_SOURCE"; then
  reasons+=("This reply says what instructions hold or require (the kit, a rule, a checklist, CLAUDE.md), and nothing in this turn read them. Read the rule it is about and cite its file and line, or drop the claim.")
fi

# The account CLIs the reply's fenced blocks run, and the ones this turn's shell commands ran.
handed_clis=$(printf '%s\n' "$reply" | awk '
  /^[ \t]*(```|~~~)/ { inside = !inside; next }
  inside { print }
' | command_starts | grep -Ex "$ACCOUNT_CLIS" | sort -u)
ran_clis=$(printf '%s\n' "$turn_tool_calls" | sed -n 's/^Bash	//p' | command_starts | grep -Ex "$ACCOUNT_CLIS" | sort -u)

unchecked_clis=()
for cli in $handed_clis; do
  printf '%s\n' "$ran_clis" | grep -qx "$cli" && continue
  printf '%s\n' "$turn_tool_calls" | grep -Eq "/\.config/$cli(/|$)|/\.$cli(/|$)" && continue
  unchecked_clis+=("$cli")
done
if [ "${#unchecked_clis[@]}" -gt 0 ]; then
  reasons+=("This reply hands the person a ${unchecked_clis[*]} command, and this turn never ran ${unchecked_clis[*]} or read its config. Check what the command needs that you can see (the login, the keys and what they may do, the account it acts on), fix what is missing first, or say in the reply why you can't check.")
fi

[ "${#reasons[@]}" -gt 0 ] || exit 0
jq -n --arg reason "${reasons[*]}" '{decision: "block", reason: $reason}'
