#!/usr/bin/env bash
# Stop hook: notes a reply that stated something nothing in its turn checked, for the next turn's
# reminder (remind-reply-rules.sh) to name. It never blocks: by the time a Stop hook runs, the
# person has already seen the reply, so a block only shows them a second copy of it. It is the
# trigger for kc-conventions:kc-check-claims, for the two kinds of
# claim a script can tell from the turn's own tool calls:
#
#   - What instructions say (the kit, a working agreement, a checklist, CLAUDE.md, a rule or
#     skill): the turn must have a tool call naming an instructions file (a rules or skills
#     folder, a .claude folder, CLAUDE.md, AGENTS.md, SKILL.md or the kit's plugins).
#   - A command handed to the person, inside a fenced block, for a CLI that acts on an account
#     (payments, hosting, cloud, code host): the turn must have run that CLI itself, at the start
#     of a command, or named a path in its config folder.
#
# A reply that lists look-back lessons when the session never ran `feedback-ledger.sh list` is
# noted: a look-back written from memory keeps the feedback that stood out and drops the rest.
#
# A cause proposed with no reproduction is kc-assess's required `Reproduced:` box, not this hook's.
#
# A turn whose latest message was only a question (is_only_question) and that made Edit or Write
# calls is noted too: a question is not a change request.
#
# A reply that says a tool, CLI, API or similar cannot do something ("can't", "cannot", "has no way
# to", "doesn't support", "no API for", "isn't possible", in a sentence that also names a tool, CLI,
# API, command, plugin, library, service and the like) is noted unless its turn looked it up: a web
# or docs lookup (WebFetch, WebSearch, a docs or search MCP tool), or a call other than an edit whose
# command or path (not the tool's name) names a word of that sentence, on word boundaries (`shopctl export --help` for "shopctl can't export").
# A capability claim from memory is out of date or wrong as often as not (kc-check-claims).
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

# A sentence that says a tool or service can't do something: the phrase and a tool word in one sentence.
readonly CAPABILITY_CLAIM="(can.t|cannot|has no way to|have no way to|doesn.t support|does not support|no api for|isn.t possible|is not possible)"
readonly CAPABILITY_SUBJECT='(^|[^[:alnum:]])(tools?|cli|api|apis|command|commands|endpoint|plugin|library|sdk|connector|mcp|extension|platform|runtime|service|framework|browser|shell)([^[:alnum:]]|$)'
# Words of a claim sentence that say nothing about which tool it is.
readonly CAPABILITY_STOPWORDS=' the can cannot isn doesn does not support supports there way has have this that with from for and but also into any api cli tool tools command commands possible plugin library endpoint sdk service platform runtime option options flag need needs here your you its are was use used using only just when what which '

# A sentence that says something couldn't be settled.
readonly UNCERTAIN_CLAIM="(can.t|cannot|couldn.t|could not) (confirm|verify|tell whether|tell if|say whether)|I don.t know (whether|if)|not sure (whether|if)"

# What reading instructions looks like in a tool call's path or command.
readonly INSTRUCTIONS_SOURCE='kc-claude-kit|plugins/kc-|(^|/)rules/|/skills/|(^|/)\.claude/|CLAUDE\.md|AGENTS\.md|SKILL\.md'

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
  turn_entries[] | get_tool_call_lines
' "$transcript" 2>/dev/null) || exit 0

misses=()

has_edited_files=false
printf '%s\n' "$turn_tool_calls" | grep -Eq "$EDIT_CALLS" && has_edited_files=true

# A turn whose latest message was only a question and that then edited files: the question gets
# its answer, and nothing is changed until the person asks.
prompt=$(jq -L "$(dirname "$0")/lib" -rs 'include "typed-message"; [.[] | select(is_typed_message)] | last | [typed_texts] | join("\n")' "$transcript" 2>/dev/null)
if is_only_question "$prompt" && [ "$has_edited_files" = true ]; then
  misses+=("You edited files after a question; answer and stop.")
fi

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

# Any tool call in the whole session (not only this turn) whose input ran the ledger's list.
ledger_listed=$(jq -rs '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")
  | .input | tostring | select(test("feedback-ledger\\.sh\"?[ \\t]+list\\b"))] | length > 0' "$transcript" 2>/dev/null)
lists_look_back_lessons=false
reply_one_line=$(printf '%s' "$reply" | tr '\n' ' ')
if printf '%s' "$reply_one_line" | grep -Eiq 'look[- ]?back' && printf '%s' "$reply_one_line" | grep -Eiq 'lessons?'; then
  lists_look_back_lessons=true
fi
if [ "$lists_look_back_lessons" = true ] && [ "$ledger_listed" != true ]; then
  misses+=("It listed look-back lessons without running feedback-ledger.sh list over the session; run it, then give every item, the person's feedback included, a verdict.")
fi

if printf '%s' "$reply" | tr '\n' ' ' | grep -Eiq "$UNCERTAIN_CLAIM"; then
  misses+=("It said it couldn't confirm or didn't know something. That is a claim too: check every source that could settle it (every log, file and command) and cite what you found, or name the one you couldn't check and why.")
fi

# A tool, CLI or API said not to do something, with no lookup of it in the turn. The "can't confirm"
# phrases are the previous note's, so they are taken out first.
uncertain_claim_lower=$(printf '%s' "$UNCERTAIN_CLAIM" | tr '[:upper:]' '[:lower:]')
capability_sentences=$(printf '%s' "$reply" | tr '\n' ' ' | tr '[:upper:]' '[:lower:]' | sed -E "s/$uncertain_claim_lower//g" \
  | grep -Eo "[^.!?]*${CAPABILITY_CLAIM}[^.!?]*" | grep -E "$CAPABILITY_SUBJECT")
if [ -n "$capability_sentences" ]; then
  looked_up=false
  printf '%s\n' "$turn_tool_calls" | grep -Eq '^(WebFetch|WebSearch)	|^mcp__[^	]*(doc|search|context7|resolve-library)' && looked_up=true
  if [ "$looked_up" = false ]; then
    claim_calls=$(printf '%s\n' "$turn_tool_calls" | grep -Ev "$EDIT_CALLS" | awk -F'\t' '{ print $2 }' | tr '[:upper:]' '[:lower:]')
    for word in $(printf '%s' "$capability_sentences" | grep -Eo "[a-z0-9_-]{3,}" | sort -u); do
      case "$CAPABILITY_STOPWORDS" in *" $word "*) continue ;; esac
      printf '%s\n' "$claim_calls" | grep -Eq -- "(^|[^[:alnum:]_-])${word}([^[:alnum:]_-]|\$)" && { looked_up=true; break; }
    done
  fi
  if [ "$looked_up" = false ]; then
    misses+=("It said a tool, CLI or API can't do something with no lookup that turn. That is a claim too: check the version that will run it, in its own docs, its --help or by trying it, then say what you found (kc-conventions:kc-check-claims).")
  fi
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
' | list_command_starts | grep -Ex "$ACCOUNT_CLIS" | sort -u)
ran_clis=$(printf '%s\n' "$turn_tool_calls" | sed -n 's/^Bash	//p' | list_command_starts | grep -Ex "$ACCOUNT_CLIS" | sort -u)

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
