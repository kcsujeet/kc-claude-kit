#!/usr/bin/env bash
# shellcheck disable=SC2016  # the replies hold Markdown backticks, not shell expansions
# Tests scripts/check-reply-length.sh: a reply over 180 words of prose is noted for the next turn, with its
# word count; fenced code blocks and table rows don't count, and nothing is ever printed.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
hook="$(dirname "$tests_dir")/scripts/check-reply-length.sh"
transcript=$work_dir/transcript.jsonl
printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"how does the cart work?"}]}}' > "$transcript"

# <count> words: "word word word ..."
repeat_word() { awk -v n="$1" 'BEGIN { for (i = 1; i <= n; i++) printf "word "; print "" }'; }

# Runs the hook on <reply>; prints "noted" when it wrote a miss for the next turn, "out" when it
# wrote none, and "unexpected output" when it printed anything (a Stop hook here never blocks).
export CLAUDE_PLUGIN_DATA=$work_dir/data
misses_file=$CLAUDE_PLUGIN_DATA/reply-misses/s
hook_output=$work_dir/hook-output
run_hook() {
  local reply=$1
  rm -f "$misses_file"
  jq -cn --arg reply "$reply" --arg path "$transcript" \
    '{session_id: "s", transcript_path: $path, hook_event_name: "Stop", stop_hook_active: false, last_assistant_message: $reply}' \
    | bash "$hook" > "$hook_output" || { echo "exit $?"; return; }
  if [ -s "$hook_output" ]; then echo "unexpected output"
  elif [ -s "$misses_file" ]; then echo noted
  else echo out; fi
}

long_reply=$(repeat_word 250)
expect_eq "a 50-word reply goes out" out "$(run_hook "$(repeat_word 50)")"
expect_eq "a reply of exactly 180 words goes out" out "$(run_hook "$(repeat_word 180)")"
expect_eq "a 250-word reply is noted" noted "$(run_hook "$long_reply")"
expect_contains "the miss gives the word count" "It ran 250 words of prose" "$(cat "$misses_file")"
expect_eq "a 250-word reply prints nothing, so it is never shown twice" "" "$(cat "$hook_output")"

code_reply=$(printf '%s\n\n```bash\n%s\n```\n' "$(repeat_word 30)" "$(repeat_word 300)")
expect_eq "30 words of prose plus a 300-word code block goes out" out "$(run_hook "$code_reply")"
tilde_reply=$(printf '%s\n\n~~~\n%s\n~~~\n' "$(repeat_word 30)" "$(repeat_word 300)")
expect_eq "a block behind a tilde fence goes out too" out "$(run_hook "$tilde_reply")"

table_rows=$(for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do printf '| %s | %s | %s |\n' "$(repeat_word 8)" "$(repeat_word 8)" "$(repeat_word 8)"; done)
table_reply=$(printf '%s\n\n%s\n' "$(repeat_word 30)" "$table_rows")
expect_eq "30 words of prose plus a long table goes out" out "$(run_hook "$table_reply")"

prose_after_block=$(printf '```bash\nls\n```\n\n%s\n' "$(repeat_word 250)")
expect_eq "long prose after a code block is still noted" noted "$(run_hook "$prose_after_block")"

expect_eq "an empty reply goes out" out "$(run_hook "")"

# Without a data folder or a session id there is nowhere to note a miss: nothing is written,
# printed or reported as an error.
rm -rf "$CLAUDE_PLUGIN_DATA"
expect_eq "with no data folder a long reply prints nothing, errors included" "" \
  "$(jq -cn --arg reply "$long_reply" '{session_id: "s", last_assistant_message: $reply}' | CLAUDE_PLUGIN_DATA='' bash "$hook" 2>&1)"
expect_eq "with no session id a long reply prints nothing, errors included" "" \
  "$(jq -cn --arg reply "$long_reply" '{last_assistant_message: $reply}' | bash "$hook" 2>&1)"
expect_eq "with no session id no misses folder is made" absent "$([ -e "$CLAUDE_PLUGIN_DATA/reply-misses" ] && echo present || echo absent)"

finish
