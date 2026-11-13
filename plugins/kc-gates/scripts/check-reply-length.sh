#!/usr/bin/env bash
# Stop hook: holds back, once, a reply that runs past 180 words of prose.
#
# The count leaves out fenced code blocks and markdown table rows: a command, a diff or a table of
# results is content the person asked for, not explanation. A held reply goes out on its second try
# (`stop_hook_active`), so a reply whose every line is needed is never held twice; the cost of a
# needless hold is that one retry.
#
# Input: the Stop payload on stdin. Output: `{"decision":"block","reason":...}` or nothing.
# Always exits 0; without jq nothing is parsed, so the reply goes out. Hook schema:
# https://code.claude.com/docs/en/hooks
set -u

readonly MAX_WORDS=180

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

payload=$(cat)
[ "$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null)" = true ] && exit 0
reply=$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty' 2>/dev/null)

prose_words=$(printf '%s\n' "$reply" | count_prose_words)
[ "$prose_words" -gt "$MAX_WORDS" ] || exit 0

jq -n --arg reason "This reply is $prose_words words. Cut it to what the person needs: the answer or the state first, then only what they must act on. Drop recaps, background, restated rules and explanations nobody asked for (working agreement: Keep answers short). If every line is needed and no other check asked for changes, send it again unchanged." \
  '{decision: "block", reason: $reason}'
