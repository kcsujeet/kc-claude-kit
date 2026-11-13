#!/usr/bin/env bash
# Stop hook: notes a reply that stated something nothing in its turn checked, for the next turn's
# reminder (remind-reply-rules.sh) to name. It never blocks: by the time a Stop hook runs, the
# person has already seen the reply, so a block only shows them a second copy of it. It is the
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
# And two things a reply must open with or check first:
#
#   - After a turn whose hooks asked for the reload status first (remind-reload.sh in the desktop app,
#     update-after-merge.sh), the reply's first line gives the reload status.
#   - A reply that says it can't confirm or doesn't know something is noted as a reminder to check
#     every source that could settle it first; the script can't tell whether that happened.
#
# It sees only that such a call happened, not whether it was a read or what it found.
#
# Input: the Stop payload on stdin. Output: none; each miss is appended to
# the session's misses file (lib/reply-misses.sh). Always exits 0, and notes nothing when jq, the
# plugin data folder, a session id or the transcript is missing. Hook schema:
# https://code.claude.com/docs/en/hooks
set -u

# shellcheck source=lib/reply-misses.sh
. "$(dirname "$0")/lib/reply-misses.sh"

# CLIs that act on an account: a key, a login or a permission decides whether a command works.
readonly ACCOUNT_CLIS='stripe|wrangler|gh|aws|gcloud|az|fly|flyctl|vercel|netlify|heroku|firebase|supabase|doctl|railway|render'

# A sentence that says what instructions hold, require or lack.
readonly INSTRUCTIONS_CLAIM='(the kit|kit.s|kc-[a-z]+|working agreement|hand-off checklist|checklist|claude\.md|agents\.md|the rules?|a rule|skill)[^.!?]{0,80}(says|say|requires?|needs?|asks? for|forbids?|allows?|already|has no|have no|does not|doesn.t|is not|isn.t|are not|aren.t|can.t|cannot|only)'

# A sentence that says something couldn't be settled.
readonly UNCERTAIN_CLAIM="(can.t|cannot|couldn.t|could not) (confirm|verify|tell whether|tell if|say whether)|I don.t know (whether|if)|not sure (whether|if)"

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
session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty')
reply=$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty')
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty')
[ -n "$reply" ] && [ -r "$transcript" ] || exit 0

# The tool calls since the person's last typed message, one per line: the tool's name, a tab,
# then the path or command it was given.
turn_tool_calls=$(jq -L "$(dirname "$0")/lib" -rs '
  include "typed-message";
  turn_entries[]
  | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")
  | .name + "\t" + ((.input.file_path // .input.path // .input.command // .input.pattern // "") | tostring | gsub("\n"; " "))
' "$transcript" 2>/dev/null) || exit 0

misses=()

# True when a hook this turn asked for the reload status on the reply's first line.
reload_line_asked=$(jq -L "$(dirname "$0")/lib" -rs '
  include "typed-message";
  [turn_entries[] | select(.attachment.type == "hook_additional_context")
     | .attachment.content[]? | select(test("first line of your reply"))] | length > 0
' "$transcript" 2>/dev/null)
first_line=$(printf '%s\n' "$reply" | grep -m1 -v '^[[:space:]]*$')
if [ "$reload_line_asked" = true ] && ! printf '%s' "$first_line" | grep -Eiq 'reload|install'; then
  misses+=("Plugins were installed in that turn, and the reply's first line didn't give the reload status.")
fi

if printf '%s' "$reply" | tr '\n' ' ' | grep -Eiq "$UNCERTAIN_CLAIM"; then
  misses+=("It said it couldn't confirm or didn't know something. That is a claim too: check every source that could settle it (every log, file and command) and cite what you found, or name the one you couldn't check and why.")
fi

# A claim can wrap across lines, so the reply is matched as one line.
if printf '%s' "$reply" | tr '\n' ' ' | grep -Eiq "$INSTRUCTIONS_CLAIM" \
  && ! printf '%s\n' "$turn_tool_calls" | grep -Eq "$INSTRUCTIONS_SOURCE"; then
  misses+=("It said what instructions hold or require (the kit, a rule, a checklist, CLAUDE.md) without reading them first.")
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
  misses+=("It handed the person a ${unchecked_clis[*]} command without first running ${unchecked_clis[*]} or reading its config.")
fi

[ "${#misses[@]}" -gt 0 ] || exit 0
append_reply_misses "$session_id" "${misses[@]}"
exit 0
