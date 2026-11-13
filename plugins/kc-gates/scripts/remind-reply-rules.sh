#!/usr/bin/env bash
# UserPromptSubmit hook: before Claude writes its reply, reminds it of the reply rules the Stop
# hooks check (check-reply-length.sh, check-reply-sources.sh), and names what the last reply
# missed. The check runs here, at the start of the turn, because no hook runs before a reply is
# shown: a Stop hook that blocks makes Claude write the reply again, and the person sees both.
#
# Input: the UserPromptSubmit payload on stdin (its session_id). Output: the reminder, which
# Claude Code adds to the turn as context; the misses file is removed once named. Always exits 0.
# Hook schema: https://code.claude.com/docs/en/hooks
set -u

echo "Reply rules for this turn: answer first, under 180 words of prose (code blocks and tables don't count), with no recap, background or explanation nobody asked for. Before saying what instructions require, read them this turn and cite the file and line. Before handing over an account CLI's command, check its access."

command -v jq >/dev/null 2>&1 || exit 0
[ -n "${CLAUDE_PLUGIN_DATA:-}" ] || exit 0
session_id=$(jq -r '.session_id // empty' 2>/dev/null)
[ -n "$session_id" ] || exit 0
misses_file="$CLAUDE_PLUGIN_DATA/reply-misses/$session_id"
[ -s "$misses_file" ] || exit 0

echo "Your last reply broke them. Don't repeat or rewrite it; just keep this one within them:"
sed 's/^/- /' "$misses_file"
rm -f "$misses_file"
exit 0
