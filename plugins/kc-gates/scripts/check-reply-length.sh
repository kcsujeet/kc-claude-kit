#!/usr/bin/env bash
# Stop hook: notes a reply that ran past the reply word limit (lib/reply-misses.sh) in prose, for
# the next turn's reminder (remind-reply-rules.sh) to name. It never blocks: by the time a Stop
# hook runs, the person has already seen the reply, so a block only shows them a second copy of it.
#
# The count leaves out fenced code blocks and markdown table rows: a command, a diff or a table of
# results is content the person asked for, not explanation.
#
# Input: the Stop payload on stdin. Output: none; the miss is appended to the session's misses
# file. Always exits 0, and notes nothing without jq, the plugin data folder or a session id.
# Hook schema: https://code.claude.com/docs/en/hooks
set -u

# shellcheck source=lib/reply-misses.sh
. "$(dirname "$0")/lib/reply-misses.sh"

# The words in the text on stdin, outside fenced blocks and table rows.
count_prose_words() {
  awk '
    /^[ \t]*(```|~~~)/ { inside = !inside; next }
    inside { next }
    /^[ \t]*\|/ { next }
    { words += NF }
    END { print words + 0 }
  '
}

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
reply=$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty' 2>/dev/null)

prose_words=$(printf '%s\n' "$reply" | count_prose_words)
[ "$prose_words" -gt "$REPLY_MAX_WORDS" ] || exit 0

append_reply_misses "$session_id" "It ran $prose_words words of prose, past the $REPLY_MAX_WORDS limit."
exit 0
