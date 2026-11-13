#!/usr/bin/env bash
# Stop hook: holds back, once, a reply that runs past 180 words of prose. The working agreement
# already says "Keep answers short and to the point" and replies still ran to several hundred words
# for simple questions, so a rule the agent already has and still breaks gets a check.
#
# The count leaves out fenced code blocks and markdown table rows: a command, a diff or a table of
# results is content the person asked for, not explanation. A held reply goes out on its second try
# (`stop_hook_active`), so a reply whose every line is needed is never held twice; the cost of a
# needless hold is that one retry.
#
# Input: the Stop payload on stdin. Output: `{"decision":"block","reason":...}` or nothing.
# Always exits 0, and lets the reply out when jq is missing. Hook schema:
# https://code.claude.com/docs/en/hooks
set -u

readonly MAX_WORDS=180

# The words in the text on stdin, outside fenced blocks and table rows.
prose_word_count() {
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
[ "$(printf '%s' "$payload" | jq -r '.stop_hook_active // false')" = true ] && exit 0
reply=$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty')
[ -n "$reply" ] || exit 0

words=$(printf '%s\n' "$reply" | prose_word_count)
[ "$words" -gt "$MAX_WORDS" ] || exit 0

jq -n --arg reason "This reply is $words words. Cut it to what the person needs: the answer or the state first, then only what they must act on. Drop recaps, background, restated rules and explanations nobody asked for (working agreement: Keep answers short). If every line is needed, send it again unchanged." \
  '{decision: "block", reason: $reason}'
