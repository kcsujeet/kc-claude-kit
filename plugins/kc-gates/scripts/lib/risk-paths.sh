# shellcheck shell=bash
# Path and added-line rules shared by pass-size.sh and select-gates.sh, so the two never disagree
# about what counts. Sourced, never executed.

# Mirrors KC_TEST_PATHS in kc-conventions' scripts/lib/diff-lines.sh.
KC_RISK_TEST_PATHS='(\.(test|spec)\.[A-Za-z0-9]+$|_(test|spec)\.[A-Za-z0-9]+$|(^|/)test_[^/]*\.py$|(^|/)(test|tests|spec|__tests__|e2e)/)'
KC_RISK_LOCALE_PATHS='((^|/)(locales?|i18n|translations|lang)/|\.(po|pot|xlf|xliff)$)'
KC_RISK_GENERATED_PATHS='((^|/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|Gemfile\.lock|Cargo\.lock|poetry\.lock|composer\.lock)$|\.snap$|\.min\.(js|css)$|(^|/)(dist|build|generated|__generated__)/)'
# shellcheck disable=SC2034 # read by select-gates.sh
KC_RISK_SOURCE_PATHS='\.(sh|bash|js|jsx|ts|tsx|mjs|cjs|rb|erb|py|swift|go|java|kt|php|cs|rs|vue|svelte|html)$'
# Width a line is cut to when a script quotes it as the reason for a verdict.
# shellcheck disable=SC2034 # read by pass-size.sh
KC_SNIPPET_WIDTH=80
# The paths a check lives in: a script, hook, test, eval, CI workflow or lint-rule file. Read by
# feedback-ledger.sh (a lesson needs one in its diff) and guard-prose-rule.sh (a new rule needs one
# in its commit), so the two never disagree about what counts.
# shellcheck disable=SC2034 # read by the scripts that source this file
KC_CHECK_PATHS='(^|/)(tests?|evals|hooks|scripts)/|(^|/)\.github/workflows/|\.(sh|bats)$|\.(test|spec)\.[A-Za-z]+$|_(test|spec)\.[A-Za-z]+$|(^|/)(biome\.json|eslint[^/]*|\.rubocop\.yml)$'
KC_RISK_UNCOUNTED_PATHS="($KC_RISK_TEST_PATHS|$KC_RISK_LOCALE_PATHS|$KC_RISK_GENERATED_PATHS)"

# kc_added_code <diff-file> [<path-ERE>]: the added lines of files that are not tests, without the `+`;
# with <path-ERE>, only those of files whose path matches it (pass KC_RISK_SOURCE_PATHS so prose,
# config and data files never read as code).
# The path patterns go through ENVIRON, not -v: -v expands backslash escapes, so GNU awk warns on
# \. (onto stderr, which select-gates.sh's callers read) and reads it as any character.
kc_added_code() {
  KC_TESTS=$KC_RISK_TEST_PATHS KC_ONLY=${2:-} awk '
    /^\+\+\+ / {
      path = substr($0, 5); sub(/^b\//, "", path)
      code = (path !~ ENVIRON["KC_TESTS"] && path != "/dev/null" && (ENVIRON["KC_ONLY"] == "" || path ~ ENVIRON["KC_ONLY"]))
      next
    }
    /^\+/ { if (code) print substr($0, 2) }' "$1"
}

# Paths a signed-out visitor reaches, built in; a repo adds its own in .claude/public-paths.txt.
# The extension list is narrower than KC_RISK_SOURCE_PATHS on purpose: a shell script serves no
# visitor.
# Source files only (a doc, an image or a stylesheet puts no code on a path), and only by where the
# file is: under app/public/, public/, guest/, anonymous/ or portal/ folders, in a public, guest,
# anonymous or portal controller, route, handler or page file, or a route file (Rails routes, a
# routes folder, a *.routes.* or route.* file). Nothing reads the text of a changed line.
KC_PUBLIC_SOURCE_EXTENSIONS='(ts|tsx|js|jsx|mjs|cjs|vue|svelte|rb|erb|py|go|php|java|kt|cs|rs|html)'
KC_PUBLIC_VISITOR_WORDS='(public|guests?|anonymous|portals?)'
KC_PUBLIC_BUILTIN_PATHS="(^|/)${KC_PUBLIC_VISITOR_WORDS}/.*\\.${KC_PUBLIC_SOURCE_EXTENSIONS}\$|(^|/)[^/]*[-_.]?${KC_PUBLIC_VISITOR_WORDS}[-_.][^/]*(controller|route|routes|handler|endpoint|page|view)[^/]*\\.${KC_PUBLIC_SOURCE_EXTENSIONS}\$|(^|/)(config/)?routes?(/.*)?\\.${KC_PUBLIC_SOURCE_EXTENSIONS}\$|(^|/)[^/]*[-_.]routes?\\.${KC_PUBLIC_SOURCE_EXTENSIONS}\$"

# kc_public_path_hit <changed-files> [<repo-root>]: the first changed path that is on a path a
# signed-out visitor reaches, or nothing. A path matches the built-in list above or an extended
# regex in <repo-root>/.claude/public-paths.txt (one per line, blank lines and # comments skipped).
# Tests, locale and generated files are never checked: a spec of a public page changes no page.
kc_public_path_hit() {
  local changed_files=$1 repo_root=${2:-.} candidates public_pattern hit
  candidates=$(grep -vE "$KC_RISK_UNCOUNTED_PATHS" "$changed_files" || true)
  hit=$(printf '%s\n' "$candidates" | grep -E "$KC_PUBLIC_BUILTIN_PATHS" | head -n 1 || true)
  if [ -z "$hit" ] && [ -f "$repo_root/.claude/public-paths.txt" ]; then
    while IFS= read -r public_pattern || [ -n "$public_pattern" ]; do
      case "$public_pattern" in '' | '#'*) continue ;; esac
      hit=$(printf '%s\n' "$candidates" | grep -E "$public_pattern" | head -n 1 || true)
      [ -z "$hit" ] || break
    done < "$repo_root/.claude/public-paths.txt"
  fi
  printf '%s\n' "$hit"
}

# kc_public_inheritor_hit <changed-files> [<repo-root>]: "<changed> is inherited by <public file>" for
# the first changed source file defining a class that a class on a public path (kc_public_path_hit)
# inherits from (Ruby `< Name`, JS/TS/Java-style `extends Name`), or nothing. A base class a guest
# page renders through its subclass reaches signed-out visitors without its own path saying so.
kc_public_inheritor_hit() {
  local changed_files=$1 repo_root=${2:-.} changed_path class_name public_hit list_file
  list_file=$(mktemp)
  while IFS= read -r changed_path; do
    [ -f "$repo_root/$changed_path" ] || continue
    while IFS= read -r class_name; do
      [ -n "$class_name" ] || continue
      grep -rlE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=tmp \
        "(<|extends)[[:space:]]*(::)?${class_name}([^A-Za-z0-9_:]|$)" "$repo_root" 2>/dev/null \
        | sed "s#^$repo_root/##" > "$list_file" || true
      [ -s "$list_file" ] || continue
      public_hit=$(kc_public_path_hit "$list_file" "$repo_root")
      if [ -n "$public_hit" ]; then
        rm -f "$list_file"
        printf '%s is inherited by %s\n' "$changed_path" "$public_hit"
        return 0
      fi
    done < <(sed -nE 's/^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?(abstract[[:space:]]+)?class[[:space:]]+([A-Z][A-Za-z0-9_:]*).*/\4/p' "$repo_root/$changed_path")
  done < <(grep -vE "$KC_RISK_UNCOUNTED_PATHS" "$changed_files" | grep -E "\.${KC_PUBLIC_SOURCE_EXTENSIONS}$" || true)
  rm -f "$list_file"
}
