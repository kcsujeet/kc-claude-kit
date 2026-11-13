#!/usr/bin/env bash
# shellcheck disable=SC2016  # the replies hold Markdown backticks, not shell expansions
# Tests scripts/check-reply-length.sh: a reply over 180 words of prose is held back once, with its
# word count; fenced code blocks and table rows don't count, and a second try always goes out.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
hook="$(dirname "$tests_dir")/scripts/check-reply-length.sh"
transcript=$work_dir/transcript.jsonl
printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"how does the cart work?"}]}}' > "$transcript"

# <count> words: "word word word ..."
words() { awk -v n="$1" 'BEGIN { for (i = 1; i <= n; i++) printf "word "; print "" }'; }

hook_output=$work_dir/hook-output
run_hook() {
  local reply=$1 active=${2:-false}
  jq -cn --arg reply "$reply" --arg path "$transcript" --argjson active "$active" \
    '{session_id: "s", transcript_path: $path, hook_event_name: "Stop", stop_hook_active: $active, last_assistant_message: $reply}' \
    | bash "$hook" > "$hook_output" || { echo "exit $?"; return; }
  if grep -q '"decision": *"block"' "$hook_output"; then echo held
  elif [ -s "$hook_output" ]; then echo "unexpected output"
  else echo out; fi
}

long_reply=$(words 250)
expect_eq "a 50-word reply goes out" out "$(run_hook "$(words 50)")"
expect_eq "a reply of exactly 180 words goes out" out "$(run_hook "$(words 180)")"
expect_eq "a 250-word reply is held" held "$(run_hook "$long_reply")"
expect_contains "the reason gives the word count" "This reply is 250 words" "$(cat "$hook_output")"
expect_contains "the reason says to send it unchanged if every line is needed" "send it again unchanged" "$(cat "$hook_output")"
expect_eq "the same turn's second try goes out" out "$(run_hook "$long_reply" true)"

code_reply=$(printf '%s\n\n```bash\n%s\n```\n' "$(words 30)" "$(words 300)")
expect_eq "30 words of prose plus a 300-word code block goes out" out "$(run_hook "$code_reply")"
tilde_reply=$(printf '%s\n\n~~~\n%s\n~~~\n' "$(words 30)" "$(words 300)")
expect_eq "a block behind a tilde fence goes out too" out "$(run_hook "$tilde_reply")"

table_rows=$(for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do printf '| %s | %s | %s |\n' "$(words 8)" "$(words 8)" "$(words 8)"; done)
table_reply=$(printf '%s\n\n%s\n' "$(words 30)" "$table_rows")
expect_eq "30 words of prose plus a long table goes out" out "$(run_hook "$table_reply")"

prose_after_block=$(printf '```bash\nls\n```\n\n%s\n' "$(words 250)")
expect_eq "long prose after a code block is still held" held "$(run_hook "$prose_after_block")"

expect_eq "an empty reply goes out" out "$(run_hook "")"

finish
