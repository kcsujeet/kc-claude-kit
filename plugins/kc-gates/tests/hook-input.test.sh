#!/usr/bin/env bash
# Tests scripts/lib/hook-input.sh directly: split_segments cuts a command where bash would, never
# inside quoted text, comments or heredoc bodies, including the apostrophes bash doesn't read as
# quotes; mask_quoted_text breaks flag-like words in that text; and extract_field's no-jq path
# decodes the JSON string, or keeps the captured text when it can't.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
# shellcheck source=../scripts/lib/hook-input.sh
. "$(dirname "$tests_dir")/scripts/lib/hook-input.sh"

# Prints the segments of <command>, one per line, trimmed, blank ones left out.
segments_of() {
  split_segments "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$' || true
}

# --- where bash splits ----------------------------------------------------------------------------
expect_eq "separators outside quotes split" \
  "$(printf 'git status\ngit diff')" "$(segments_of 'git status; git diff')"
expect_eq "a ; inside double quotes doesn't" 1 \
  "$(segments_of 'gh pr review 5 -b "Looks good; ship it" --approve' | wc -l | tr -d ' ')"
expect_eq "a | inside single quotes doesn't" 1 \
  "$(segments_of "gh pr review 5 -b 'tests | lint pass' --approve" | wc -l | tr -d ' ')"
expect_eq "a ; between escaped quotes in a double-quoted body doesn't" 1 \
  "$(segments_of 'gh pr review 5 -b "said \"ship; it\" today" --approve' | wc -l | tr -d ' ')"
expect_eq "a ; inside an ANSI-C string doesn't" 1 \
  "$(segments_of "echo \$'it\\'s; fine'" | wc -l | tr -d ' ')"
expect_eq "an escaped ; doesn't" 1 \
  "$(segments_of 'find . -name "*.tmp" -exec rm {} \;' | wc -l | tr -d ' ')"
expect_eq "an unclosed quote splits as before" 2 \
  "$(segments_of 'echo "half; git status' | wc -l | tr -d ' ')"

# --- apostrophes bash doesn't read as quotes ------------------------------------------------------
expect_eq "an escaped apostrophe opens no quote, so later commands stay their own" \
  "$(printf "echo it\\\\'s\ngh api repos/shop/web/pulls/5/comments -f body=x\necho 'z'")" \
  "$(segments_of "echo it\\'s; gh api repos/shop/web/pulls/5/comments -f body=x; echo 'z'")"
comment_command=$(printf "git status # don't stage yet\ngh api repos/shop/web/pulls/5/comments -f body=x\necho 'z'")
expect_eq "an apostrophe in a comment opens no quote" \
  "gh api repos/shop/web/pulls/5/comments -f body=x" "$(segments_of "$comment_command" | sed -n 2p)"
heredoc_command=$(printf "cat <<EOF > notes.txt\nit's done; ship | it\nEOF\ngh api repos/shop/web/pulls/5/comments -f body=x\necho 'z'")
expect_eq "a heredoc body's apostrophes and separators stay in the body" \
  "gh api repos/shop/web/pulls/5/comments -f body=x" "$(segments_of "$heredoc_command" | sed -n 3p)"
expect_eq "and the heredoc is one segment up to its end word" "cat <<EOF > notes.txt" \
  "$(segments_of "$heredoc_command" | sed -n 1p)"

unterminated_heredoc=$(printf "cat <<EOF\nit's done; ship | it")
expect_eq "a heredoc whose end word never comes is body to the end" 2 \
  "$(segments_of "$unterminated_heredoc" | wc -l | tr -d ' ')"

# --- flags inside text ------------------------------------------------------------------------------
expect_contains "a flag-like word inside a quoted body is broken" 'x--approve' \
  "$(mask_quoted_text 'gh pr review 5 --comment -b "please --approve once CI passes"')"
expect_eq "a flag quoted on its own is kept" "gh pr review 5 '--approve'" \
  "$(mask_quoted_text "gh pr review 5 '--approve'")"
expect_eq "a command with no quotes is unchanged" "gh pr ready 5 --repo shop/web" \
  "$(mask_quoted_text 'gh pr ready 5 --repo shop/web')"

# --- extract_field without jq -----------------------------------------------------------------------
# Wraps a JSON string literal (already escaped) as the command of a Bash hook payload.
payload_with_command() {
  printf '{"cwd":"/tmp/shop","tool_input":{"command":"%s"}}' "$1"
}
expect_eq "it decodes escaped quotes and backslashes" 'say "hi" to C:\shop' \
  "$(KC_GUARD_NO_JQ=1 extract_field "$(payload_with_command 'say \"hi\" to C:\\shop')" command)"
expect_eq "it decodes a newline" "$(printf 'git status\ngit diff')" \
  "$(KC_GUARD_NO_JQ=1 extract_field "$(payload_with_command 'git status\ngit diff')" command)"
expect_eq "text it can't decode comes back as captured, not empty" 'gh pr ready 5 \ud800' \
  "$(KC_GUARD_NO_JQ=1 extract_field "$(payload_with_command 'gh pr ready 5 \ud800')" command)"
expect_eq "a top-level field is read too" "/tmp/shop" \
  "$(KC_GUARD_NO_JQ=1 extract_field "$(payload_with_command 'true')" cwd)"

finish
