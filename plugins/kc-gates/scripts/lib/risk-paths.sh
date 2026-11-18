# shellcheck shell=bash
# Path and added-line rules shared by pass-size.sh and select-gates.sh, so the two never disagree
# about what counts. Sourced, never executed.

# Mirrors KC_TEST_PATHS in kc-conventions' scripts/lib/diff-lines.sh.
KC_RISK_TEST_PATHS='(\.(test|spec)\.[A-Za-z0-9]+$|_(test|spec)\.[A-Za-z0-9]+$|(^|/)test_[^/]*\.py$|(^|/)(test|tests|spec|__tests__|e2e)/)'
KC_RISK_LOCALE_PATHS='((^|/)(locales?|i18n|translations|lang)/|\.(po|pot|xlf|xliff)$)'
KC_RISK_GENERATED_PATHS='((^|/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|Gemfile\.lock|Cargo\.lock|poetry\.lock|composer\.lock)$|\.snap$|\.min\.(js|css)$|(^|/)(dist|build|generated|__generated__)/)'
KC_RISK_UNCOUNTED_PATHS="($KC_RISK_TEST_PATHS|$KC_RISK_LOCALE_PATHS|$KC_RISK_GENERATED_PATHS)"

# kc_added_code <diff-file>: the added lines of files that are not tests, without the `+`.
kc_added_code() {
  awk -v tests="$KC_RISK_TEST_PATHS" '
    /^\+\+\+ / { path = substr($0, 5); sub(/^b\//, "", path); code = (path !~ tests && path != "/dev/null"); next }
    /^\+/ { if (code) print substr($0, 2) }' "$1"
}

# kc_added_source_code <diff-file>: kc_added_code limited to source files (the languages the
# conventions cover), so prose, config and data files never read as code.
kc_added_source_code() {
  awk -v tests="$KC_RISK_TEST_PATHS" -v source='\\.(sh|bash|js|jsx|ts|tsx|mjs|cjs|rb|erb|py|swift|go|java|kt|php|cs|rs)$' '
    /^\+\+\+ / { path = substr($0, 5); sub(/^b\//, "", path); code = (path !~ tests && path ~ source); next }
    /^\+/ { if (code) print substr($0, 2) }' "$1"
}

# kc_public_path_hit <changed-files> <added-code>: the first thing in the change that puts code on
# a path a signed-out visitor reaches (a changed file under public/, guest/ or anonymous/, or an
# added line naming a public or guest flag or skipping the authentication filter), or nothing.
# Tests, locale and generated files are not checked.
kc_public_path_hit() {
  local changed_files=$1 added_code=$2 public_path public_code
  public_path=$(grep -vE "$KC_RISK_UNCOUNTED_PATHS" "$changed_files" | grep -E '(^|/)(public|guests?|anonymous)/.*\.(ts|tsx|js|jsx|vue|svelte|rb|erb|py|go|php|html)$' | head -n 1 || true)
  public_code=$(printf '%s\n' "$added_code" | grep -E '\b(is_?[Pp]ublic|is_?[Gg]uest|guest_?[Tt]oken|[Aa]nonymous|[Uu]nauthenticated|[Ss]igned_?[Oo]ut|AllowAnonymous|permitAll)\b|skip_before_action[[:space:]]+:authenticate|/public/' | head -n 1 | sed -E 's/^[[:space:]]+//' | cut -c1-80 || true)
  printf '%s\n' "${public_path:-$public_code}"
}
