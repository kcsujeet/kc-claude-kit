#!/usr/bin/env bash
# testing §T3: breaks each condition and early exit the diff adds, one at a time, runs the tests,
# and prints every break no test noticed: a branch no test covers, or code that changes nothing.
#
# Usage: surviving-mutants.sh <diff-file> --test <command> [--setup <command>] [--paths <regex>]
#                             [--runs <n>] [--max-minutes <n>]
#
#   <diff-file>        The diff under review, of the commit checked out here (HEAD).
#   --test <command>   The specs that cover the changed files, run with `bash -c` from the root of
#                      a throwaway checkout of HEAD. Exit 0 means they passed.
#   --setup <command>  Run once in that checkout before the tests, when a fresh one needs it (an
#                      install).
#   --paths <regex>    Mutate only files whose path matches this extended regex, when a slow suite
#                      covers some paths and a fast one the rest (one run per suite).
#   --runs <n>         Baseline runs before any mutant (default 10). One failure stops the run: the
#                      tests are flaky or broken, and every mutant would read as caught.
#   --max-minutes <n>  The whole run's budget (default 8). Lines it does not reach are printed as
#                      not mutated, never dropped. KC_MUTANTS_BUDGET_SECONDS, when set, replaces it
#                      with a budget in seconds (the tests use it).
#
# The checkout is a `git worktree add --detach` of HEAD in a temporary directory, removed on exit,
# so the working tree is never edited and a run killed outright leaves nothing in it.
# Mutated: the diff's added lines in code files outside test paths (`KC_CODE_PATHS` and
# `KC_TEST_PATHS` in lib/diff-lines.sh), comment lines skipped. One mutant per kind a line holds,
# never inside quotes: `&&` and `||` swapped (Python's `and` and `or`), equality and its strict
# forms flipped, `<=` and `>=` made strict and ` < ` and ` > ` not, a negating `!` or `not`
# removed, `true` and `false` swapped, bash's test flags flipped (`-n`/`-z`, `-eq`/`-ne`,
# `-lt`/`-ge`, `-gt`/`-le`, `=`/`!=`), Ruby's `if` and `unless` swapped, and a one-line guard
# (an exit and its condition on one line) deleted. Outside shell and Python, also: each plain
# operand of `&&` and `||` dropped, the two sides of a value fallback (`||` or `??` between two
# member reads, `user?.nickname || user?.name`) swapped, a ternary forced to each branch, and a regex literal
# weakened (`^` or `$` removed, `\w` widened to `.`). A mutant that a syntax check rejects
# (`bash -n`, `node --check`, `ruby -c`, Python's parser, each used only when the original file
# passes it) is unviable and not run.
# Each test run gets three times the slowest baseline run plus ten seconds, in its own process
# group, killed at the deadline (the timer kc-autopilot's scripts/guard.sh uses). A mutant whose
# run timed out counts as caught. After each run, any process still running from the throwaway
# checkout (a server the tests started and a timeout left behind) is stopped, so the next run
# can't reuse it.
#
# Prints a summary line, then `path:line: <break>: text` per surviving mutant, then
# `path:line: not mutated (time budget): text` per line the budget did not reach.
# Exits 0 when the mutants ran, 1 when they could not (`mutation: not run: <reason>`), 2 on a
# usage error.
set -uo pipefail

script_name=$(basename "$0")
script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../../scripts/lib/diff-lines.sh
. "$script_dir/../../../scripts/lib/diff-lines.sh"

usage() {
  echo "usage: $script_name <diff-file> --test <command> [--setup <command>] [--paths <regex>] [--runs <n>] [--max-minutes <n>]" >&2
  exit 2
}

if [ "$#" -lt 1 ] || [ "$1" = "-" ]; then usage; fi
kc_require_diff_arg "$script_name" "$1"
diff_file="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
shift
test_command=""
setup_command=""
path_filter=""
baseline_runs=10
max_minutes=8
while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || usage
  case "$1" in
    --test) test_command=$2 ;;
    --setup) setup_command=$2 ;;
    --paths) path_filter=$2 ;;
    --runs) baseline_runs=$2 ;;
    --max-minutes) max_minutes=$2 ;;
    *) usage ;;
  esac
  shift 2
done
[ -n "$test_command" ] || usage
case "$baseline_runs" in '' | *[!0-9]* | 0) usage ;; esac
case "$max_minutes" in '' | *[!0-9]* | 0) usage ;; esac

started_at=$(date +%s)
budget_seconds=${KC_MUTANTS_BUDGET_SECONDS:-$((max_minutes * 60))}
case "$budget_seconds" in '' | *[!0-9]*) usage ;; esac
tmp_root=${TMPDIR:-/tmp}
work_dir=$(mktemp -d "${tmp_root%/}/kc-mutants.XXXXXX")
tree="$work_dir/tree"
repo_root=""
job=""
timer=""
# A process started from the checkout carries its path in its arguments. Matched by the unique
# part, since a tool may print it through a symlink (/var and /private/var on macOS).
tree_pattern="$(basename "$work_dir" | sed 's/\./\\./g')/tree/"

# Invoked by the EXIT trap. ShellCheck 0.11 reports that as SC2329; older versions as SC2317.
# shellcheck disable=SC2317,SC2329
cleanup() {
  if [ -n "$job" ]; then kill -KILL -- "-$job" 2>/dev/null || kill -KILL "$job" 2>/dev/null; fi
  if [ -n "$timer" ]; then kill -KILL -- "-$timer" 2>/dev/null || kill -KILL "$timer" 2>/dev/null; fi
  pkill -KILL -f -- "$tree_pattern" 2>/dev/null
  if [ -n "$repo_root" ]; then
    git -C "$repo_root" worktree remove --force "$tree" >/dev/null 2>&1
    rm -rf "$work_dir"
    git -C "$repo_root" worktree prune >/dev/null 2>&1
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

not_run() {
  echo "mutation: not run: $1; test: $test_command"
  exit 1
}

seconds_left() {
  echo $((budget_seconds - ($(date +%s) - started_at)))
}

# Runs <command> from the checkout's root, in its own process group, and kills the group at the
# deadline (set -m gives each background job its own group). Output goes to <log-file>.
# Returns the command's status, or 137 when the timer killed it. Each job is forked with stderr
# closed to the terminal: bash 3.2 sometimes reports a harmless `child setpgid` failure there,
# and a kill falls back to the process itself when its group is missing.
run_in_tree() {
  local limit_seconds=$1 log_file=$2 command=$3 job_status
  set -m
  { ( trap - EXIT INT TERM; set +m; cd "$tree" && exec bash -c "$command" ) < /dev/null > "$log_file" 2>&1 & } 2>/dev/null
  job=$!
  { ( trap - EXIT INT TERM; set +m; sleep "$limit_seconds"; kill -KILL -- "-$job" || kill -KILL "$job" ) > /dev/null 2>&1 & } 2>/dev/null
  timer=$!
  wait "$job" 2>/dev/null
  job_status=$?
  kill -KILL -- "-$job" 2>/dev/null || kill -KILL "$job" 2>/dev/null
  kill -KILL -- "-$timer" 2>/dev/null || kill -KILL "$timer" 2>/dev/null
  wait "$timer" 2>/dev/null
  job=""
  timer=""
  set +m
  pkill -KILL -f -- "$tree_pattern" 2>/dev/null
  return "$job_status"
}

# Exits 0 when <file> parses, or when no checker for its language is installed.
passes_syntax_check() {
  case "$1" in
    *.sh | *.bash) bash -n "$1" ;;
    *.js | *.mjs | *.cjs) ! command -v node >/dev/null 2>&1 || node --check "$1" ;;
    *.rb) ! command -v ruby >/dev/null 2>&1 || ruby -c "$1" ;;
    *.py) ! command -v python3 >/dev/null 2>&1 || python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' "$1" ;;
    *) true ;;
  esac
} < /dev/null > /dev/null 2>&1

# Prints position, length, replacement and the break, separated by the unit separator, per mutant
# of the line in KC_LINE; position 0 deletes the whole line. Positions count bytes (LC_ALL=C).
list_mutants() {
  KC_LINE=$2 LC_ALL=C awk -v path="$1" '
    # True when position at of s lies outside quotes. A backslash escapes the next character.
    function outside_quotes(s, at,    i, c, single, double, back) {
      single = 0; double = 0; back = 0
      for (i = 1; i < at; i++) {
        c = substr(s, i, 1)
        if (c == "\\" && !single) { i++; continue }
        if (c == "\"" && !single && !back) double = !double
        else if (c == "\047" && !double && !back) single = !single
        else if (c == "`" && !single && !double) back = !back
      }
      return !(single || double || back)
    }
    # The first position of token outside quotes, as a whole word when is_word, else 0.
    function find_token(s, token, is_word,    offset, at, before, after) {
      offset = 0
      while ((at = index(substr(s, offset + 1), token)) > 0) {
        at += offset
        before = substr(s, at - 1, 1)
        after = substr(s, at + length(token), 1)
        if (outside_quotes(s, at) && (!is_word || (before !~ /[A-Za-z0-9_$]/ && after !~ /[A-Za-z0-9_$]/))) return at
        offset = at
      }
      return 0
    }
    function emit(at, from, to, label) { printf "%d\037%d\037%s\037%s\n", at, length(from), to, label }
    # The first token found of the pairs (`from@to`, space-separated, `_` for a space in a token)
    # becomes its pair.
    function flip_first(s, pairs, is_word,    n, list, i, parts, at) {
      n = split(pairs, list, " ")
      for (i = 1; i <= n; i++) {
        split(list[i], parts, "@")
        gsub(/_/, " ", parts[1]); gsub(/_/, " ", parts[2])
        at = find_token(s, parts[1], is_word)
        if (at > 0) { emit(at, parts[1], parts[2], "`" trim(parts[1]) "` to `" trim(parts[2]) "`"); return }
      }
    }
    function trim(s) { gsub(/^ +| +$/, "", s); return s }
    # Drops the left, then the right, operand of the first op outside quotes, each only when it
    # is a plain operand: a name or member chain, optionally negated or compared with one value.
    function drop_operand(s, op,    at, operand, before, after, start, spaces, size) {
      at = find_token(s, op, 0)
      if (at == 0) return
      operand = "!?" MEMBER_CHAIN "( *(===|!==|==|!=|<=|>=|<|>) *([A-Za-z0-9_$.]+|\047[^\047]*\047|\"[^\"]*\"))?"
      before = substr(s, 1, at - 1)
      after = substr(s, at + length(op))
      if (match(before, operand " *$")) {
        start = RSTART
        match(after, /^ */)
        spaces = RLENGTH
        if (substr(s, start - 1, 1) !~ /[A-Za-z0-9_$.?)\]]/)
          printf "%d\037%d\037\037left of `%s` dropped\n", start, at + length(op) + spaces - start, op
      }
      if (match(after, "^ *" operand)) {
        size = RLENGTH
        if (substr(after, size + 1, 1) !~ /[A-Za-z0-9_$.?(\[]/) {
          match(before, / *$/)
          printf "%d\037%d\037\037right of `%s` dropped\n", RSTART, length(before) - RSTART + 1 + length(op) + size, op
        }
      }
    }
    # True when the `(` that opens s is still open at its end: depth never falls back to zero,
    # and brackets inside quoted text are not counted.
    function is_paren_still_open(s,    i, c, depth, quote) {
      depth = 0
      quote = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (quote != "") {
          if (c == "\\") i++
          else if (c == quote) quote = ""
          continue
        }
        # A double quote, a single quote or a backtick opens quoted text.
        if (index("\"\047`", c)) quote = c
        else if (c == "(") depth++
        else if (c == ")") {
          depth--
          if (depth == 0) return 0
        }
      }
      return depth > 0
    }
    # Swaps the two sides of the first op outside quotes when both are member reads (`a.b`,
    # `a?.b.c`), the shape of a value fallback (`user?.nickname || user?.name`). A test whose
    # fixture leaves one side empty passes either way round, so the order it guards goes untested.
    # Skipped when either side reads as a boolean (`order.isPaid`), when an operator that binds
    # tighter sits beside a side (`a && b.c || d.e`, `b.c || d.e + 1`: that read is its operand),
    # or when the op sits inside an `if (`, `while (` or `until (` condition still open at it:
    # there only truth counts. An unparenthesised condition (as in Ruby, `if a.b || c.d`) is not seen.
    function swap_operands(s, op,    at, boolean_read, condition_start, tighter_operator, before, after, rest, condition, left, right, start, size, text_before_left, text_after_right, left_is_boolean, right_is_boolean) {
      at = find_token(s, op, 0)
      boolean_read = "[.](is|has|can|should|was|did|will)[A-Z_][A-Za-z0-9_$]*$"
      condition_start = "(^|[^A-Za-z0-9_$])(if|while|until)[[:space:]]*[(]"
      tighter_operator = "(&&|==|!=|<=|>=|[-+*/%<>])"
      before = substr(s, 1, at - 1)
      after = substr(s, at + length(op))
      rest = before
      condition = ""
      while (match(rest, condition_start)) {
        condition = substr(rest, RSTART + RLENGTH - 1)
        rest = substr(rest, RSTART + RLENGTH)
      }
      if (condition != "" && is_paren_still_open(condition)) return
      if (!match(before, MEMBER_READ " *$")) return
      start = RSTART
      left = substr(before, RSTART); sub(/ +$/, "", left)
      # A read that is the tail of a longer expression (after a name, a member access, a call or
      # index, or a `!`) or the head of one (before a call or index) is no side of its own.
      if (substr(s, start - 1, 1) ~ /[A-Za-z0-9_$.?)\]!]/) return
      if (!match(after, "^ *" MEMBER_READ)) return
      size = RLENGTH
      if (substr(after, size + 1, 1) ~ /[A-Za-z0-9_$.?(\[]/) return
      right = substr(after, 1, size); sub(/^ +/, "", right)
      # An arrow (`=>`) ends in `>` but binds looser than any op, so it is no tighter operator.
      text_before_left = substr(s, 1, start - 1); sub(/[[:space:]]+$/, "", text_before_left)
      text_after_right = substr(after, size + 1)
      if (text_before_left !~ /=>$/ && text_before_left ~ tighter_operator "$") return
      if (text_after_right ~ "^[[:space:]]*" tighter_operator) return
      left_is_boolean = left ~ boolean_read
      right_is_boolean = right ~ boolean_read
      if (left_is_boolean || right_is_boolean) return
      printf "%d\037%d\037%s %s %s\037sides of `%s` swapped\n", start, at + length(op) + size - start, right, op, left, op
    }
    BEGIN {
      MEMBER_NAME = "[A-Za-z_$][A-Za-z0-9_$]*"
      MEMBER_CHAIN = MEMBER_NAME "([?]?[.]" MEMBER_NAME ")*"
      MEMBER_READ = MEMBER_NAME "([?]?[.]" MEMBER_NAME ")+"
      text = ENVIRON["KC_LINE"]
      is_shell = path ~ /\.(sh|bash)$/
      is_python = path ~ /\.py$/
      is_ruby = path ~ /\.rb$/
      if (is_python) {
        flip_first(text, "and@or", 1)
        flip_first(text, "or@and", 1)
      } else {
        flip_first(text, "&&@||", 0)
        flip_first(text, "||@&&", 0)
      }
      if (is_shell) {
        flip_first(text, "_-n_@_-z_ _-z_@_-n_ _-eq_@_-ne_ _-ne_@_-eq_ _-lt_@_-ge_ _-ge_@_-lt_ _-gt_@_-le_ _-le_@_-gt_", 0)
        if (text ~ /\[/) flip_first(text, "_!=_@_=_ _==_@_!=_ _=_@_!=_", 0)
      } else {
        flip_first(text, "===@!== !==@=== ==@!= !=@==", 0)
        flip_first(text, "<=@< >=@> _<_@_<=_ _>_@_>=_", 0)
      }
      if (is_shell) {
        at = find_token(text, "! ", 0)
        if (at > 0 && substr(text, 1, at - 1) ~ /(^|\[|\[\[|if|&&|\|\||;|while|until|elif)[[:space:]]*$/) emit(at, "! ", "", "`!` removed")
      } else if (is_python) {
        at = find_token(text, "not", 1)
        if (at > 0 && substr(text, at + 3, 1) == " ") emit(at, "not ", "", "`not` removed")
      } else {
        offset = 0
        while ((at = index(substr(text, offset + 1), "!")) > 0) {
          at += offset
          if (substr(text, at + 1, 1) ~ /[A-Za-z_($]/ && outside_quotes(text, at)) { emit(at, "!", "", "`!` removed"); break }
          offset = at
        }
      }
      if (!is_shell && !is_python) {
        drop_operand(text, "&&")
        drop_operand(text, "||")
        swap_operands(text, "||")
        swap_operands(text, "??")
        at = find_token(text, " ? ", 0)
        if (at > 0 && text !~ /[[:space:]]extends[[:space:]]/) {
          emit(at, " ? ", " || true ? ", "ternary forced to its first branch")
          emit(at, " ? ", " && false ? ", "ternary forced to its second branch")
        }
        at = find_token(text, "/^", 0)
        if (at > 0) emit(at + 1, "^", "", "regex `^` removed")
        at = find_token(text, "$/", 0)
        if (at > 0) emit(at, "$", "", "regex `$` removed")
        if (find_token(text, "/^", 0) || find_token(text, "$/", 0)) {
          at = find_token(text, "\\w", 0)
          if (at > 0) emit(at, "\\w", ".", "regex `\\w` widened to `.`")
        }
      }
      if (is_python) flip_first(text, "True@False False@True", 1)
      else flip_first(text, "true@false false@true", 1)
      if (is_ruby) flip_first(text, "unless@if if@unless", 1)
      if (find_token(text, "return", 1) || find_token(text, "exit", 1) || find_token(text, "continue", 1) ||
          find_token(text, "break", 1) || find_token(text, "throw", 1) || find_token(text, "raise", 1)) {
        if (find_token(text, "if", 1) || find_token(text, "unless", 1) || find_token(text, "&&", 0) || find_token(text, "||", 0))
          printf "0\0370\037\037line deleted\n"
      }
    }
  '
}

# Writes <file> as <pristine> with line <n> mutated at <position> (0: the line deleted).
apply_mutant() {
  KC_REPLACEMENT=$6 LC_ALL=C awk -v n="$3" -v at="$4" -v len="$5" '
    NR == n && at == 0 { next }
    NR == n { $0 = substr($0, 1, at - 1) ENVIRON["KC_REPLACEMENT"] substr($0, at + len) }
    { print }
  ' "$2" > "$1"
}

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || not_run "not inside a git work tree"
git -C "$repo_root" worktree add --quiet --detach "$tree" HEAD >/dev/null 2>&1 \
  || not_run "could not check out HEAD into a temporary worktree"

# Candidate lines as path, line and text, separated by the unit separator so `read` keeps the
# text's own tabs and spaces.
separator=$(printf '\037')
kc_added_lines "$diff_file" | KC_PATH_FILTER=$path_filter awk -F '\t' -v sep="$separator" -v code="$KC_CODE_PATHS" -v tests="$KC_TEST_PATHS" '
  $1 ~ code && $1 !~ tests && (ENVIRON["KC_PATH_FILTER"] == "" || $1 ~ ENVIRON["KC_PATH_FILTER"]) {
    text = $0; sub(/^[^\t]*\t[^\t]*\t/, "", text)
    if (text ~ /^[[:space:]]*(\/\/|#|\*|\/\*|<!--)/ || text ~ /^[[:space:]]*$/) next
    printf "%s%s%s%s%s\n", $1, sep, $2, sep, text
  }
' > "$work_dir/candidates"
while IFS="$separator" read -r path line text; do
  [ "$(sed -n "${line}p" "$tree/$path" 2>/dev/null)" = "$text" ] || not_run "the diff does not match HEAD at $path:$line"
done < "$work_dir/candidates"

if [ -n "$setup_command" ]; then
  run_in_tree "$(seconds_left)" "$work_dir/setup.log" "$setup_command" || {
    echo "mutation: not run: the setup command failed; test: $test_command"
    tail -n 20 "$work_dir/setup.log"
    exit 1
  }
fi

failed_runs=0
slowest_seconds=0
for _ in $(seq 1 "$baseline_runs"); do
  [ "$(seconds_left)" -gt 0 ] || not_run "the time budget ran out during the baseline runs"
  run_started_at=$(date +%s)
  if ! run_in_tree "$(seconds_left)" "$work_dir/baseline.log" "$test_command"; then
    [ "$failed_runs" -gt 0 ] || cp "$work_dir/baseline.log" "$work_dir/first-failure.log"
    failed_runs=$((failed_runs + 1))
  fi
  run_seconds=$(($(date +%s) - run_started_at))
  [ "$run_seconds" -le "$slowest_seconds" ] || slowest_seconds=$run_seconds
done
if [ "$failed_runs" -gt 0 ]; then
  echo "mutation: not run: the tests failed $failed_runs of $baseline_runs baseline runs; test: $test_command"
  tail -n 20 "$work_dir/first-failure.log"
  exit 1
fi
deadline_seconds=$((slowest_seconds * 3 + 10))

mutant_count=0
line_count=0
caught_count=0
timed_out_count=0
unviable_count=0
: > "$work_dir/survivors"
: > "$work_dir/unreached"
while IFS="$separator" read -r path line text <&3; do
  if [ "$(seconds_left)" -le 0 ]; then
    printf '%s:%s: not mutated (time budget): %s\n' "$path" "$line" "$text" >> "$work_dir/unreached"
    continue
  fi
  file="$tree/$path"
  list_mutants "$path" "$text" > "$work_dir/mutants"
  [ -s "$work_dir/mutants" ] || continue
  line_count=$((line_count + 1))
  cp "$file" "$work_dir/pristine"
  is_checked=false
  if passes_syntax_check "$file"; then is_checked=true; fi
  while IFS="$separator" read -r position length replacement label <&4; do
    if [ "$(seconds_left)" -le 0 ]; then
      printf '%s:%s: not mutated (time budget): %s\n' "$path" "$line" "$text" >> "$work_dir/unreached"
      break
    fi
    apply_mutant "$file" "$work_dir/pristine" "$line" "$position" "$length" "$replacement"
    mutant_count=$((mutant_count + 1))
    if [ "$is_checked" = true ] && ! passes_syntax_check "$file"; then
      unviable_count=$((unviable_count + 1))
    elif run_in_tree "$deadline_seconds" "$work_dir/mutant.log" "$test_command"; then
      printf '%s:%s: %s: %s\n' "$path" "$line" "$label" "$text" >> "$work_dir/survivors"
    else
      [ "$?" -ne 137 ] || timed_out_count=$((timed_out_count + 1))
      caught_count=$((caught_count + 1))
    fi
    cp "$work_dir/pristine" "$file"
  done 4< "$work_dir/mutants"
done 3< "$work_dir/candidates"

survivor_count=$(wc -l < "$work_dir/survivors" | tr -d ' ')
unreached_count=$(wc -l < "$work_dir/unreached" | tr -d ' ')
echo "mutation: $mutant_count mutants on $line_count lines: $caught_count caught ($timed_out_count timed out), $unviable_count unviable, $survivor_count survived, $unreached_count lines not mutated; baseline runs: $baseline_runs, slowest ${slowest_seconds}s; test: $test_command"
cat "$work_dir/survivors" "$work_dir/unreached"
exit 0
