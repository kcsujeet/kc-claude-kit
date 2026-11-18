# shellcheck shell=bash
# The paths a check lives in: a script, hook, test, eval, CI workflow or lint-rule file. One list,
# read by feedback-ledger.sh (a lesson needs one in its diff) and guard-prose-rule.sh (a new rule
# needs one in its commit), so the two never disagree about what counts. Sourced, never executed.
# shellcheck disable=SC2034 # read by the scripts that source this file
readonly KC_CHECK_PATHS='(^|/)(tests?|evals|hooks|scripts)/|(^|/)\.github/workflows/|\.(sh|bats)$|\.(test|spec)\.[A-Za-z]+$|_(test|spec)\.[A-Za-z]+$|(^|/)(biome\.json|eslint[^/]*|\.rubocop\.yml)$'
