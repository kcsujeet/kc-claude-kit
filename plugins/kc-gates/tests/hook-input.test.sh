#!/usr/bin/env bash
# Tests scripts/lib/hook-input.sh directly: split_segments cuts at every separator, quotes or not,
# so a guard sees each command a wrapper runs; mask_quoted_text, read before splitting by the
# look-back hook, keeps text bash doesn't run as syntax (quotes, comments, heredoc bodies) in its
# command's segment, including the apostrophes and `<<` bash doesn't read as quotes or heredocs;
# and extract_field's no-jq path decodes the JSON string, or keeps the captured text when it can't.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
# shellcheck source=../scripts/lib/hook-input.sh
. "$(dirname "$tests_dir")/scripts/lib/hook-input.sh"

# Prints the segments of <command> as the look-back hook reads them (masked, then split), one per
# line, trimmed, blank ones left out.
get_masked_segments() {
  split_segments "$(mask_quoted_text "$1")" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$' || true
}

# --- the guards' split ----------------------------------------------------------------------------
expect_eq "split_segments cuts inside quotes too, so a wrapper's commands each get a segment" \
  "$(printf 'bash -c "git status\n git diff"')" "$(split_segments 'bash -c "git status; git diff"')"

# --- the look-back hook's masked split ------------------------------------------------------------
expect_eq "separators outside quotes split" \
  "$(printf 'git status\ngit diff')" "$(get_masked_segments 'git status; git diff')"
expect_eq "a ; inside double quotes doesn't" 1 \
  "$(get_masked_segments 'gh pr review 5 -b "Looks good; ship it" --approve' | wc -l | tr -d ' ')"
expect_eq "a | inside single quotes doesn't" 1 \
  "$(get_masked_segments "gh pr review 5 -b 'tests | lint pass' --approve" | wc -l | tr -d ' ')"
expect_eq "a ; between escaped quotes in a double-quoted body doesn't" 1 \
  "$(get_masked_segments 'gh pr review 5 -b "said \"ship; it\" today" --approve' | wc -l | tr -d ' ')"
expect_eq "a ; inside an ANSI-C string doesn't" 1 \
  "$(get_masked_segments "echo \$'it\\'s; fine'" | wc -l | tr -d ' ')"
expect_eq "an escaped ; doesn't" 1 \
  "$(get_masked_segments 'find . -name "*.tmp" -exec rm {} \;' | wc -l | tr -d ' ')"
expect_eq "an unclosed quote splits as before" 2 \
  "$(get_masked_segments 'echo "half; git status' | wc -l | tr -d ' ')"

# --- apostrophes and << bash doesn't read as quotes or heredocs -----------------------------------
expect_eq "an escaped apostrophe opens no quote, so later commands stay their own" \
  "$(printf "echo it\\\\'s\ngh pr review 5 --approve\necho 'z'")" \
  "$(get_masked_segments "echo it\\'s; gh pr review 5 --approve; echo 'z'")"
comment_command=$(printf "git status # don't stage yet\ngh pr review 5 --approve\necho 'z'")
expect_eq "an apostrophe in a comment opens no quote" \
  "gh pr review 5 --approve" "$(get_masked_segments "$comment_command" | sed -n 2p)"
heredoc_command=$(printf "cat <<EOF > notes.txt\nit's done; ship | it\nEOF\ngh pr review 5 --approve\necho 'z'")
expect_eq "a heredoc body's apostrophes and separators stay in the body" \
  "gh pr review 5 --approve" "$(get_masked_segments "$heredoc_command" | sed -n 3p)"
expect_eq "and the heredoc is one segment up to its end word" "cat <<EOF > notes.txt" \
  "$(get_masked_segments "$heredoc_command" | sed -n 1p)"
dashed_end=$(printf "cat <<MY-END\nit's; done\nMY-END\ngh pr review 5 --approve")
expect_eq "an end word with a dash is read whole" \
  "gh pr review 5 --approve" "$(get_masked_segments "$dashed_end" | sed -n 3p)"
tab_end=$(printf "cat <<-EOF\n\tit's; done\n\tEOF\ngh pr review 5 --approve")
expect_eq "<<- ends at a tab-indented end word" \
  "gh pr review 5 --approve" "$(get_masked_segments "$tab_end" | sed -n 3p)"
indented_end=$(printf "cat <<EOF\nit's; done\n  EOF\nEOF\ngh pr review 5 --approve")
expect_eq "a plain << doesn't end at an indented end word" \
  "gh pr review 5 --approve" "$(get_masked_segments "$indented_end" | sed -n 3p)"
arithmetic_shift=$(printf "echo \$((x << y))\ngh pr review 5 --approve")
expect_eq "<< in arithmetic, with no end line after it, is no heredoc" \
  "gh pr review 5 --approve" "$(get_masked_segments "$arithmetic_shift" | sed -n 2p)"
unterminated_heredoc=$(printf "cat <<EOF\nit's done; ship | it")
expect_eq "nor is a << whose end line never comes" 4 \
  "$(get_masked_segments "$unterminated_heredoc" | wc -l | tr -d ' ')"

# --- flags inside text ------------------------------------------------------------------------------
expect_contains "a flag-like word inside a quoted body is broken" 'x--approve' \
  "$(mask_quoted_text 'gh pr review 5 --comment -b "please --approve once CI passes"')"
expect_eq "a flag quoted on its own is kept" "gh pr review 5 '--approve'" \
  "$(mask_quoted_text "gh pr review 5 '--approve'")"
expect_eq "a command with no quotes is unchanged" "gh pr ready 5 --repo shop/web" \
  "$(mask_quoted_text 'gh pr ready 5 --repo shop/web')"

# --- extract_field without jq -----------------------------------------------------------------------
# Wraps a JSON string literal (already escaped) as the command of a Bash hook payload.
build_payload_with_command() {
  printf '{"cwd":"/tmp/shop","tool_input":{"command":"%s"}}' "$1"
}
expect_eq "it decodes escaped quotes and backslashes" 'say "hi" to C:\shop' \
  "$(KC_GUARD_NO_JQ=1 extract_field "$(build_payload_with_command 'say \"hi\" to C:\\shop')" command)"
expect_eq "it decodes a newline" "$(printf 'git status\ngit diff')" \
  "$(KC_GUARD_NO_JQ=1 extract_field "$(build_payload_with_command 'git status\ngit diff')" command)"
expect_eq "text it can't decode comes back as captured, not empty" 'gh pr ready 5 \ud800' \
  "$(KC_GUARD_NO_JQ=1 extract_field "$(build_payload_with_command 'gh pr ready 5 \ud800')" command)"
expect_eq "a top-level field is read too" "/tmp/shop" \
  "$(KC_GUARD_NO_JQ=1 extract_field "$(build_payload_with_command 'true')" cwd)"

finish
