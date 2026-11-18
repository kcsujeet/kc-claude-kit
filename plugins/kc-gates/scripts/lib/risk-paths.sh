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
    while IFS= read -r public_pattern; do
      case "$public_pattern" in '' | '#'*) continue ;; esac
      hit=$(printf '%s\n' "$candidates" | grep -E "$public_pattern" | head -n 1 || true)
      [ -z "$hit" ] || break
    done < "$repo_root/.claude/public-paths.txt"
  fi
  printf '%s\n' "$hit"
}
