#!/usr/bin/env bash
# Step 2 of kc-code-review: decides which phase-1 gates a diff needs, from its
# changed files and added lines, so no gate runs on a diff it has nothing to
# grade (a React gate on a Ruby-only change) and none is left out by judgment.
#
# Usage: select-gates.sh <diff-file> <changed-files> [<repo-root>]
#
#   <diff-file>      The unified diff (gather-review.sh's review.diff).
#   <changed-files>  One path per line (gather-review.sh's changed-files.txt).
#   <repo-root>      Where the changed files and .claude/review-conventions.md
#                    are read (default: the current directory).
#
# Prints `GATES=<gate>,<gate>,...` (the ones to dispatch, in table order), then
# one line per gate: `<gate>: run (<why>)` or `<gate>: N/A (<why>)`. naming,
# clarity, structure, simplicity, testing and correctness always run; the
# verification gate is phase 2 and always runs, so it is not listed.
#
# Then `WALK=required` or `WALK=not-required` and a `walk: <why>` line. Required when the diff
# puts code on a path a signed-out visitor reaches (the same test pass-size.sh makes, from
# lib/risk-paths.sh): the review then walks the change in the running app as every audience that
# can reach it, signed out included, before its verdict.
#
# Exits 0 on success, 2 on a usage error or a missing input file.
set -euo pipefail

script_name=$(basename "$0")
usage() {
  echo "usage: $script_name <diff-file> <changed-files> [<repo-root>]" >&2
  exit 2
}
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || usage
diff_file=$1
changed_files=$2
repo_root=${3:-.}
[ -f "$diff_file" ] || { echo "$script_name: no such diff: $diff_file" >&2; exit 2; }
[ -f "$changed_files" ] || { echo "$script_name: no such file list: $changed_files" >&2; exit 2; }

plugin_root=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=lib/risk-paths.sh
. "$plugin_root/scripts/lib/risk-paths.sh"

# kc-conventions is installed beside this plugin: next to it in a checkout, or under the highest
# version of its own folder in the plugin cache (cache/<marketplace>/<plugin>/<version>).
conventions_root=$plugin_root/../kc-conventions
if [ ! -d "$conventions_root" ]; then
  conventions_root=$(find "$plugin_root/../../kc-conventions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -n 1 || true)
fi
pattern_lib=$conventions_root/scripts/lib/request-surface-pattern.sh
[ -f "$pattern_lib" ] || { echo "$script_name: kc-conventions (scripts/lib/request-surface-pattern.sh) not found beside $plugin_root" >&2; exit 2; }
# shellcheck source=../../kc-conventions/scripts/lib/request-surface-pattern.sh
. "$pattern_lib"

# The diff's added lines, without the `+++ b/path` headers or the `+`.
added_lines=$(grep -E '^\+' "$diff_file" | grep -vE '^\+\+\+ ' | sed 's/^+//' || true)

# Added lines of non-test source files, for the checks that read code and not prose.
added_source=$(kc_added_code "$diff_file" "$KC_RISK_SOURCE_PATHS")

# Prints the first changed path matching an extended regex, or nothing.
first_changed_path() {
  grep -E "$1" "$changed_files" | head -n 1 || true
}

# first_added_line <regex> [<lines>]: the first of <lines> (default: every added line) matching an
# extended regex, trimmed, or nothing. Pass "$added_source" to read code and not prose.
first_added_line() {
  printf '%s\n' "${2-$added_lines}" | grep -E "$1" | head -n 1 | sed -E 's/^[[:space:]]+//' | cut -c1-"$KC_SNIPPET_WIDTH" || true
}

# True when any package.json in the repo depends on React, so a `use…` function there is a React
# hook rather than, say, a Vue composable.
repo_uses_react() {
  local manifest
  while IFS= read -r manifest; do
    grep -qE '"react"[[:space:]]*:' "$repo_root/$manifest" && return 0
  done < <(cd "$repo_root" && { git ls-files '*package.json' 2>/dev/null || find . -name package.json -not -path '*/node_modules/*' | sed 's#^\./##'; })
  return 1
}

# Prints the first changed JS or TS file that is React code, with why, or nothing: it imports
# React or a React library (react-*, @tanstack/react-*, @scope/react*, next/*), or, in a repo
# that depends on React, defines a hook (a `use…` function), which may call only other hooks.
first_react_module() {
  local source_path uses_react=unknown
  while IFS= read -r source_path; do
    case "$source_path" in
      *.js | *.jsx | *.ts | *.tsx | *.mjs | *.cjs) ;;
      *) continue ;;
    esac
    [ -f "$repo_root/$source_path" ] || continue
    if grep -qE "(from|require\\()[[:space:]]*['\"](react|react-dom|react-[^'\"]+|@[^/'\"]+/react[^'\"]*|next/[^'\"]+)['\"]" "$repo_root/$source_path"; then
      printf '%s (imports React or a React library)\n' "$source_path"
      return
    fi
    if grep -qE "(function|const|let)[[:space:]]+use[A-Z][A-Za-z0-9_]*" "$repo_root/$source_path"; then
      [ "$uses_react" != unknown ] || { if repo_uses_react; then uses_react=yes; else uses_react=no; fi; }
      if [ "$uses_react" = yes ]; then
        printf '%s (defines a hook in a React repo)\n' "$source_path"
        return
      fi
    fi
  done < "$changed_files"
}

selected_gates=()
gate_lines=()

run_gate() {
  selected_gates+=("$1")
  gate_lines+=("$1: run ($2)")
}
skip_gate() {
  gate_lines+=("$1: N/A ($2)")
}

for always_gate in naming clarity structure simplicity; do
  run_gate "$always_gate" "always"
done

date_pattern='\b(Date|DateTime|Time|Temporal|Timecop|moment|dayjs|luxon|strftime|strptime|iso8601|timezone|time_zone|getTime|toISOString|toLocaleDateString|toLocaleTimeString|toLocaleString|DateTimeFormat)\b|date-fns|\.(ago|from_now|since|until)\b|\b[0-9]+\.(seconds?|minutes?|hours?|days?|weeks?|months?|years?)\b'
date_hit=$(first_added_line "$date_pattern")
if [ -n "$date_hit" ]; then
  run_gate datetime "an added line has date or time code: $date_hit"
else
  skip_gate datetime "no added line has date or time code"
fi

react_hit=$(first_changed_path '\.(jsx|tsx)$')
[ -n "$react_hit" ] || react_hit=$(first_react_module)
if [ -n "$react_hit" ]; then
  run_gate react "$react_hit"
else
  skip_gate react "no .jsx or .tsx file, and no changed JS or TS file imports React or a React library or defines a hook"
fi

rails_hit=$(first_changed_path '\.(rb|rake|gemspec)$|(^|/)Gemfile(\.lock)?$|(^|/)db/')
if [ -n "$rails_hit" ]; then
  run_gate rails "$rails_hit"
else
  skip_gate rails "no Ruby, rake, Gemfile or db/ file changed"
fi

locale_hit=$(first_changed_path '(^|/)(locales?|i18n|translations)/|\.(po|pot|xlf|xliff|strings|arb)$')
# shellcheck disable=SC2016 # `$t(` is a literal call, not an expansion.
translation_call_pattern='(^|[^A-Za-z0-9_.$])t\(|\$t\(|useTranslations|I18n\.t\b|i18n\.t\b|i18next|formatMessage'
if [ -n "$locale_hit" ]; then
  run_gate i18n "$locale_hit"
else
  translation_hit=$(first_added_line "$translation_call_pattern")
  if [ -n "$translation_hit" ]; then
    run_gate i18n "an added line calls a translation: $translation_hit"
  else
    skip_gate i18n "no locale file changed and no added line calls a translation"
  fi
fi

run_gate testing "always"
run_gate correctness "always"

# A request handler, or the code around one: request_surface_pattern is the pattern the security
# sweep (kc-conventions' request-surface.sh) matches request input with.
# Controllers, routes, API and route handlers, middleware, and auth, session, token and webhook code.
security_path_pattern='(^|/)(controllers?|routes?|routing|api|middleware|handlers?|endpoints?|webhooks?|callbacks?|policies|guards?)(/|\.[A-Za-z0-9]+$)|(^|/)[^/]*(_controller|[-_.]routes?|[-_.]middleware|[-_.]handler|[-_.]policy)\.[A-Za-z0-9]+$|(^|/)(routes|middleware|route)\.[A-Za-z0-9]+$|(^|/)[^/]*(auth|session|login|password|oauth|sso|jwt|webhook|permission|(access|api|refresh|bearer|csrf|id)[-_]?token)[^/]*\.(rb|erb|py|go|java|kt|php|cs|rs|js|jsx|ts|tsx|mjs|cjs|swift)$'
security_path=$(grep -vE "$KC_RISK_TEST_PATHS" "$changed_files" | grep -E '\.(sh|bash|js|jsx|ts|tsx|mjs|cjs|rb|erb|py|swift|go|java|kt|php|cs|rs)$' | grep -E "$security_path_pattern" | head -n 1 || true)
if [ -n "$security_path" ]; then
  run_gate security "$security_path"
else
  security_hit=$(first_added_line "$request_surface_pattern" "$added_source")
  if [ -n "$security_hit" ]; then
    run_gate security "an added line reads request input or declares a handler: $security_hit"
  else
    skip_gate security "no controller, route, handler, middleware or auth file changed and no added line reads request input"
  fi
fi

if [ -f "$repo_root/.claude/review-conventions.md" ]; then
  run_gate project-conventions ".claude/review-conventions.md exists"
else
  skip_gate project-conventions "the repo has no .claude/review-conventions.md"
fi

gates_csv=$(IFS=,; printf '%s' "${selected_gates[*]}")
printf 'GATES=%s\n' "$gates_csv"
printf '%s\n' "${gate_lines[@]}"

walk_hit=$(kc_public_path_hit "$changed_files" "$diff_file")
if [ -n "$walk_hit" ]; then
  echo "WALK=required"
  echo "walk: public or guest path, walk it as every audience that can reach it, signed out included ($walk_hit)"
else
  echo "WALK=not-required"
  echo "walk: no public or guest path in the diff"
fi
