# shellcheck shell=bash
# Path and added-line rules shared by pass-size.sh and select-gates.sh, so the two never disagree
# about what counts. Sourced, never executed.

# Mirrors KC_TEST_PATHS in kc-conventions' scripts/lib/diff-lines.sh.
KC_RISK_TEST_PATHS='(\.(test|spec)\.[A-Za-z0-9]+$|_(test|spec)\.[A-Za-z0-9]+$|(^|/)test_[^/]*\.py$|(^|/)(test|tests|spec|__tests__|e2e)/)'
KC_RISK_LOCALE_PATHS='((^|/)(locales?|i18n|translations|lang)/|\.(po|pot|xlf|xliff)$)'
KC_RISK_GENERATED_PATHS='((^|/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|Gemfile\.lock|Cargo\.lock|poetry\.lock|composer\.lock)$|\.snap$|\.min\.(js|css)$|(^|/)(dist|build|generated|__generated__)/)'
# Source files in the languages the conventions cover.
KC_RISK_SOURCE_PATHS='\.(sh|bash|js|jsx|ts|tsx|mjs|cjs|rb|erb|py|swift|go|java|kt|php|cs|rs|vue|svelte|html)$'
# Width a line is cut to when a script quotes it as the reason for a verdict.
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

# kc_public_path_hit <changed-files> <diff-file>: the first thing in the change that puts code on
# a path a signed-out visitor reaches (a changed file under public/, guest/ or anonymous/, or an
# added line naming a public or guest flag or skipping the authentication filter), or nothing.
# Tests, locale and generated files are not checked, and added lines are read from source files
# only (kc_added_code with KC_RISK_SOURCE_PATHS): a doc or skill that mentions a guest flag puts no code anywhere.
kc_public_path_hit() {
  local changed_files=$1 diff_file=$2 public_path public_code
  public_path=$(grep -vE "$KC_RISK_UNCOUNTED_PATHS" "$changed_files" | grep -E '(^|/)(public|guests?|anonymous)/.*\.(ts|tsx|js|jsx|vue|svelte|rb|erb|py|go|php|html)$' | head -n 1)
  public_code=$(kc_added_code "$diff_file" "$KC_RISK_SOURCE_PATHS" | grep -E '\b(is_?[Pp]ublic|is_?[Gg]uest|guest_?[Tt]oken|[Aa]nonymous|[Uu]nauthenticated|[Ss]igned_?[Oo]ut|AllowAnonymous|permitAll)\b|skip_before_action[[:space:]]+:authenticate|/public/' | head -n 1 | sed -E 's/^[[:space:]]+//' | cut -c1-"$KC_SNIPPET_WIDTH")
  printf '%s\n' "${public_path:-$public_code}"
}
