#!/usr/bin/env bash
# clarity §C13: added lines holding a dense expression, in any language the conventions cover.
# A line is a hit when its code (strings blanked, trailing comment dropped) has any of:
#   - a call chain: one unbroken run of 3+ links ('.name', '?.name', '&.name') of which 2+ are
#     calls (parentheses or a block), as in 'items.filter(isPaid).map(total).join(",")';
#     a plain property path ('order.shop.name') or one call after a path is not a chain;
#   - calls nested 3+ deep: 'f(g(h(x)))'; a keyword's own parentheses ('if (', 'while (') and
#     a declaration's parameter list are not calls;
#   - 3+ non-trivial parts (call, '??' or '||' fallback, ternary, cast) in a line of 70+
#     characters, so a long argument list or assignment doing several things at once.
# Skipped: comment lines, import/require/include lines, and test files (a fluent builder or a
# nested matcher there reads as a sentence). A line broken across several lines is read one
# line at a time. It over-matches, as the other sweeps do: each hit still gets a verdict.
#
# Usage: dense-expressions.sh <diff-file|->
# Scans only the lines the diff adds and prints 'path:line: text' per hit.
# Exits 0 with or without hits, 2 on a usage error.
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

if [ "$#" -ne 1 ]; then kc_require_diff_arg "$(basename "$0")" ""; fi
kc_require_diff_arg "$(basename "$0")" "$1"

# kc_added_lines gives path<TAB>line<TAB>text; the awk below does the scanning.
kc_added_lines "$1" |
  KC_CODE_PATHS=$KC_CODE_PATHS KC_TEST_PATHS=$KC_TEST_PATHS awk -F '\t' '
    BEGIN {
      BACKTICK = "\140"; SINGLE_QUOTE = "\047"; DOUBLE_QUOTE = "\""
      MIN_CHAIN_LINKS = 3    # a.b().c().d(): three links
      MIN_CHAIN_CALLS = 2    # two of them calls, so a plain path never counts
      MIN_CALL_DEPTH = 3     # f(g(h(x)))
      MIN_LONG_LINE = 70     # characters of code before several parts are too many
      MIN_PARTS = 3          # calls, fallbacks, ternaries and casts in one line
      KEYWORDS = "^(if|while|for|foreach|switch|catch|return|elsif|elif|unless|until|when|in|and|or|not|await|yield|function|def|fn|func|fun|with|except|assert|print|lambda|case|match|else)$"
      KEYWORD_CALL = "(^|[^A-Za-z0-9_$])(if|while|for|foreach|switch|catch|return|elsif|elif|unless|until|when|and|or|not|await|yield|function|def|fn|func|fun|with|except|assert|print|lambda|case|match|else)[ \t]*[(]"
    }
    # Blanks string contents (keeping the quotes), keeps the expressions inside a template
    # literal, and drops a trailing comment.
    function blank_strings_and_comments(text, hash_comments,   out, i, ch, nxt, quote, brace_depth, in_template_text, in_template_code, in_plain_string, is_template_close, is_quote_start, is_slash_comment, is_hash_comment) {
      out = ""; quote = ""; brace_depth = 0
      for (i = 1; i <= length(text); i++) {
        ch = substr(text, i, 1); nxt = substr(text, i + 1, 1)
        in_template_text = (quote == BACKTICK && brace_depth == 0)
        in_template_code = (quote == BACKTICK && brace_depth > 0)
        in_plain_string = (quote != "" && quote != BACKTICK)
        if (ch == "\\" && (in_template_text || in_plain_string)) { i++; continue }
        if (in_template_text && ch == BACKTICK) { quote = ""; out = out "\"\""; continue }
        if (in_template_text && ch == "$" && nxt == "{") { brace_depth = 1; out = out " + ("; i++; continue }
        if (in_plain_string && ch == quote) { quote = ""; out = out "\"\""; continue }
        if (in_template_text || in_plain_string) continue
        is_template_close = (in_template_code && ch == "}" && brace_depth == 1)
        if (is_template_close) { brace_depth = 0; out = out ")"; continue }
        if (in_template_code && ch == "{") brace_depth++
        if (in_template_code && ch == "}") brace_depth--
        if (in_template_code) { out = out ch; continue }
        is_quote_start = (ch == DOUBLE_QUOTE || ch == SINGLE_QUOTE || ch == BACKTICK)
        if (is_quote_start) { quote = ch; continue }
        is_slash_comment = (!hash_comments && ch == "/" && nxt == "/")
        is_hash_comment = (hash_comments && ch == "#" && (i == 1 || substr(text, i - 1, 1) ~ /[ \t]/))
        if (is_slash_comment || is_hash_comment) break
        out = out ch
      }
      return out
    }
    # Highest number of calls open at once: a name or a closing bracket directly followed by "(".
    function get_call_depth(code,   i, ch, before, word, depth, max_depth, kinds, top, follows_name_char, has_no_space_before, is_keyword, is_call, is_close_of_open) {
      depth = 0; max_depth = 0; top = 0
      for (i = 1; i <= length(code); i++) {
        ch = substr(code, i, 1)
        if (ch == "(") {
          before = substr(code, 1, i - 1)
          sub(/[ \t]+$/, "", before)
          word = before; sub(/^.*[^A-Za-z0-9_$?!]/, "", word)
          follows_name_char = (substr(before, length(before)) ~ /[A-Za-z0-9_$?!)\]]/)
          has_no_space_before = (substr(code, i - 1, 1) !~ /[ \t]/)
          is_keyword = (word ~ KEYWORDS)
          is_call = (follows_name_char && has_no_space_before && !is_keyword)
          top++; kinds[top] = is_call
          if (is_call) depth++
          if (depth > max_depth) max_depth = depth
        }
        is_close_of_open = (ch == ")" && top > 0)
        if (is_close_of_open) { if (kinds[top]) depth--; top-- }
      }
      return max_depth
    }
    # The code with every bracket pair emptied: "(...)" becomes "()", "{...}" "{}".
    function outline(code,   i, ch, level, out) {
      level = 0; out = ""
      for (i = 1; i <= length(code); i++) {
        ch = substr(code, i, 1)
        if (ch ~ /[(\[{]/) { if (level == 0) out = out ch; level++; continue }
        if (ch ~ /[)\]}]/) { if (level > 0) level--; if (level == 0) out = out ch; continue }
        if (level == 0) out = out ch
      }
      return out
    }
    function has_chain(code,   rest, chain_span, links, calls, probe, is_dense_chain) {
      rest = outline(code)
      while (match(rest, /(([.]|[?][.]|&[.])[A-Za-z_$][A-Za-z0-9_$]*[?!]?([(][)]|[{][}])?)+/)) {
        chain_span = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        probe = chain_span; links = gsub(/[.][A-Za-z_$]/, "&", probe)
        probe = chain_span; calls = gsub(/[(][)]|[{][}]/, "&", probe)
        is_dense_chain = (links >= MIN_CHAIN_LINKS && calls >= MIN_CHAIN_CALLS)
        if (is_dense_chain) return 1
      }
      return 0
    }
    function count_matches(code, pattern,   probe) { probe = code; return gsub(pattern, "&", probe) }
    function count_parts(code,   total, probe, is_conditional_statement, is_import_like) {
      probe = code
      gsub(KEYWORD_CALL, "", probe)
      total = count_matches(probe, "[A-Za-z0-9_$?!)\\]][(]")
      is_conditional_statement = (code ~ /^[ \t]*(if|elsif|elif|unless|while|until|when)[ \t(]/)
      total += count_matches(code, "[?][?]")
      if (!is_conditional_statement) { probe = code; gsub(/[|][|]=/, "", probe); total += count_matches(probe, "[|][|]") }
      if (code ~ /[ )][?] .* : /) total++
      is_import_like = (code ~ /^[ \t]*(import|from|with|except|using)[ \t]/)
      if (!is_import_like) total += count_matches(code, "[)A-Za-z0-9_\\]] as [A-Za-z_]")
      return total
    }
    {
      path = $1
      is_skipped_path = (path !~ ENVIRON["KC_CODE_PATHS"] || path ~ ENVIRON["KC_TEST_PATHS"])
      if (is_skipped_path) next
      text = $0; sub(/^[^\t]*\t[^\t]*\t/, "", text)
      is_block_comment = (text ~ /^[ \t]*(\*|\/\*)/)
      if (is_block_comment) next
      code = blank_strings_and_comments(text, path ~ /\.(rb|py|sh|bash)$/)
      if (code ~ /^[ \t]*$/) next
      is_import = (code ~ /^[ \t]*(import|from|using|package|require|require_relative|include|use)[ \t(]/ || code ~ /^[ \t]*(const|let|var)[ \t].*=[ \t]*require[(]/)
      is_declaration = (code ~ /^[ \t]*(export[ \t]+)?(async[ \t]+)?(function|def|fn|func|fun|class)[ \t*]/)
      if (is_import || is_declaration) next
      trimmed = code; sub(/^[ \t]+/, "", trimmed); sub(/[ \t]+$/, "", trimmed)
      has_dense_chain = has_chain(code)
      is_deeply_nested = (get_call_depth(code) >= MIN_CALL_DEPTH)
      is_long_and_busy = (length(trimmed) >= MIN_LONG_LINE && count_parts(code) >= MIN_PARTS)
      if (has_dense_chain || is_deeply_nested || is_long_and_busy) printf "%s:%s: %s\n", $1, $2, text
    }
  '
