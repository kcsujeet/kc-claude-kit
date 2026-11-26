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
    # Blanks string contents (keeping the quotes), keeps the expressions inside a template
    # literal, and drops a trailing comment. Sets is_comment_only when nothing is left.
    function strip(text, hash_comments,   out, i, ch, nxt, quote, brace_depth) {
      out = ""; quote = ""; brace_depth = 0
      for (i = 1; i <= length(text); i++) {
        ch = substr(text, i, 1); nxt = substr(text, i + 1, 1)
        if (quote == "\140") {
          if (brace_depth == 0) {
            if (ch == "\\") { i++; continue }
            if (ch == "\140") { quote = ""; out = out "\"\""; continue }
            if (ch == "$" && nxt == "{") { brace_depth = 1; out = out " + ("; i++ }
            continue
          }
          if (ch == "{") brace_depth++
          if (ch == "}") { brace_depth--; if (brace_depth == 0) { out = out ")"; continue } }
          out = out ch
          continue
        }
        if (quote != "") {
          if (ch == "\\") { i++; continue }
          if (ch == quote) { quote = ""; out = out "\"\""; continue }
          continue
        }
        if (ch == "\"" || ch == "\047" || ch == "\140") { quote = ch; continue }
        if (!hash_comments && ch == "/" && nxt == "/") break
        if (hash_comments && ch == "#" && (i == 1 || substr(text, i - 1, 1) ~ /[ \t]/)) break
        out = out ch
      }
      return out
    }
    # Highest number of calls open at once: a name or a closing bracket directly followed by "(".
    function call_depth(code,   i, ch, before, word, depth, max_depth, kinds, top, j) {
      depth = 0; max_depth = 0; top = 0
      for (i = 1; i <= length(code); i++) {
        ch = substr(code, i, 1)
        if (ch == "(") {
          before = substr(code, 1, i - 1)
          sub(/[ \t]+$/, "", before)
          word = before; sub(/^.*[^A-Za-z0-9_$?!]/, "", word)
          is_call = (substr(before, length(before)) ~ /[A-Za-z0-9_$?!)\]]/) && substr(code, i - 1, 1) !~ /[ \t]/ \
            && word !~ /^(if|while|for|foreach|switch|catch|return|elsif|elif|unless|until|when|in|and|or|not|await|yield|function|def|fn|func|fun|with|except|assert|print|lambda|case|match|else)$/
          top++; kinds[top] = is_call
          if (is_call) { depth++; if (depth > max_depth) max_depth = depth }
        } else if (ch == ")" && top > 0) {
          if (kinds[top]) depth--
          top--
        }
      }
      return max_depth
    }
    # The code with every bracket pair'"'"'s contents emptied: "(...)" becomes "()", "{...}" "{}".
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
    function has_chain(code,   rest, run, links, calls, probe) {
      rest = outline(code)
      while (match(rest, /(([.]|[?][.]|&[.])[A-Za-z_$][A-Za-z0-9_$]*[?!]?([(][)]|[{][}])?)+/)) {
        run = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        probe = run; links = gsub(/[.][A-Za-z_$]/, "&", probe)
        probe = run; calls = gsub(/[(][)]|[{][}]/, "&", probe)
        if (links >= 3 && calls >= 2) return 1
      }
      return 0
    }
    function count_matches(code, pattern,   probe) { probe = code; return gsub(pattern, "&", probe) }
    function part_count(code,   total, probe, cond) {
      probe = code
      gsub(/(^|[^A-Za-z0-9_$])(if|while|for|foreach|switch|catch|return|elsif|elif|unless|until|when|and|or|not|await|yield|function|def|fn|func|fun|with|except|assert|print|lambda|case|match|else)[ \t]*[(]/, "", probe)
      total = count_matches(probe, "[A-Za-z0-9_$?!)\\]][(]")
      cond = (code ~ /^[ \t]*(if|elsif|elif|unless|while|until|when)[ \t(]/)
      total += count_matches(code, "[?][?]")
      if (!cond) { probe = code; gsub(/[|][|]=/, "", probe); total += count_matches(probe, "[|][|]") }
      if (code ~ /[ )][?] .* : /) total++
      if (code !~ /^[ \t]*(import|from|with|except|using)[ \t]/) total += count_matches(code, "[)A-Za-z0-9_\\]] as [A-Za-z_]")
      return total
    }
    {
      path = $1
      if (path !~ ENVIRON["KC_CODE_PATHS"] || path ~ ENVIRON["KC_TEST_PATHS"]) next
      text = $0; sub(/^[^\t]*\t[^\t]*\t/, "", text)
      code = strip(text, path ~ /\.(rb|py|sh|bash)$/)
      if (code ~ /^[ \t]*$/) next
      if (code ~ /^[ \t]*(import|from|using|package|require|require_relative|include|use)[ \t(]/ || code ~ /^[ \t]*(const|let|var)[ \t].*=[ \t]*require[(]/) next
      if (code ~ /^[ \t]*(export[ \t]+)?(async[ \t]+)?(function|def|fn|func|fun|class)[ \t*]/) next
      trimmed = code; sub(/^[ \t]+/, "", trimmed); sub(/[ \t]+$/, "", trimmed)
      if (has_chain(code) || call_depth(code) >= 3 || (length(trimmed) >= 70 && part_count(code) >= 3)) {
        printf "%s:%s: %s\n", $1, $2, text
      }
    }
  '
