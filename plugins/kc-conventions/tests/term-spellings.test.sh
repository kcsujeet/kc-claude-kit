#!/usr/bin/env bash
# Tests skills/kc-i18n/scripts/term-spellings.sh on its lookup fixture (tests/lookups/kc-i18n/
# term-spellings): a word spelled two ways once case and hyphens are set aside is listed with every
# place of the less used spelling, from three unlike areas (a product noun, an email word, a setup
# word), a placeholder or ICU argument name is not read as text, and a tree with one spelling
# prints nothing. run-lookups.sh runs the same cases; this one runs them alone.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$tests_dir")
script=$plugin_dir/skills/kc-i18n/scripts/term-spellings.sh
fixture=$tests_dir/lookups/kc-i18n/term-spellings
failures=0

[ -f "$script" ] || { echo "FAIL no script at skills/kc-i18n/scripts/term-spellings.sh"; exit 1; }
actual=$(cd "$fixture/repo" && bash "$script" locales/en)
if [ "$actual" = "$(cat "$fixture/cases/two-spellings/expected.txt")" ]; then echo "ok   two spellings listed"; else echo "FAIL two spellings listed"; printf '%s\n' "$actual"; failures=$((failures + 1)); fi
actual=$(cd "$fixture/repo" && bash "$script" locales/clean)
if [ -z "$actual" ]; then echo "ok   one spelling, nothing listed"; else echo "FAIL one spelling, nothing listed: $actual"; failures=$((failures + 1)); fi
exit "$failures"
