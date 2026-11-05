#!/usr/bin/env bash
# kc-ready-for-review's first step: sizes the pass from the diff, by script, never by judgment.
# A small, low-risk change gets round 1 only; anything else gets the full pass. Also says
# whether the mutation sweep has anything to break.
#
# Usage: pass-size.sh <diff-file> <changed-files> [<repo-root>]
#
#   <diff-file>      The unified diff (gather-review.sh's review.diff).
#   <changed-files>  One path per line (gather-review.sh's changed-files.txt).
#   <repo-root>      Where .claude/sensitive-paths.txt is read (default: the current directory).
#                    Each non-blank, non-# line in it is an extended regex for paths this repo
#                    treats as sensitive, on top of the built-in ones.
#
# Prints:
#   SIZE=small|full
#   MUTATION=run|skip
#   files: <n> counted (<n> test, locale or generated left out)
#   lines: <n> changed in counted files
#   risk: none | <reason>        one line per sensitive hit
#   mutation: <why>
#
# Small means at most KC_SMALL_FILES files (default 5) and KC_SMALL_LINES changed lines
# (default 200), counting neither tests nor locale or generated files, and no risk line.
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

max_files=${KC_SMALL_FILES:-5}
max_lines=${KC_SMALL_LINES:-200}

# Mirrors KC_TEST_PATHS in kc-conventions' scripts/lib/diff-lines.sh.
test_paths='(\.(test|spec)\.[A-Za-z0-9]+$|_(test|spec)\.[A-Za-z0-9]+$|(^|/)test_[^/]*\.py$|(^|/)(test|tests|spec|__tests__|e2e)/)'
locale_paths='((^|/)(locales?|i18n|translations|lang)/|\.(po|pot|xlf|xliff)$)'
generated_paths='((^|/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|Gemfile\.lock|Cargo\.lock|poetry\.lock|composer\.lock)$|\.snap$|\.min\.(js|css)$|(^|/)(dist|build|generated|__generated__)/)'
uncounted_paths="($test_paths|$locale_paths|$generated_paths)"

# Sensitive paths: a change here is never small, whatever its size. Tests, locale and generated
# files are not checked: a spec of the sign-in controller changes no sign-in.
sensitive_rules=(
  'schema or data migration|(^|/)(migrations?|migrate)/|(^|/)schema\.(rb|sql|prisma)$|\.sql$'
  'authentication or permissions|(^|/)[^/]*(auth|session|login|password|permission|polic(y|ies)|oauth|sso|token)[^/]*(/|$)'
  'payments|(^|/)[^/]*(payment|billing|charge|stripe|refund|payout|checkout|subscription)[^/]*(/|$)'
  'shared contract or public API|(^|/)(contracts?|openapi|graphql|proto|public[-_]?api)(/|$)|\.(proto|graphql)$|(^|/)openapi\.(ya?ml|json)$'
)
if [ -f "$repo_root/.claude/sensitive-paths.txt" ]; then
  while IFS= read -r repo_pattern; do
    case "$repo_pattern" in '' | '#'*) continue ;; esac
    sensitive_rules+=("listed in .claude/sensitive-paths.txt|$repo_pattern")
  done < "$repo_root/.claude/sensitive-paths.txt"
fi

counted_files=0
uncounted_files=0
while IFS= read -r changed_path; do
  [ -n "$changed_path" ] || continue
  if printf '%s\n' "$changed_path" | grep -qE "$uncounted_paths"; then
    uncounted_files=$((uncounted_files + 1))
  else
    counted_files=$((counted_files + 1))
  fi
done < "$changed_files"

# Changed lines (added plus removed) in counted files, and the added code lines of non-test files.
changed_lines=$(awk -v skip="$uncounted_paths" '
  /^\+\+\+ / { path = substr($0, 5); sub(/^b\//, "", path); counted = (path !~ skip); next }
  /^--- / { if ($0 ~ /^--- a\//) { path = substr($0, 7); counted = (path !~ skip) } next }
  /^[+-]/ { if (counted) n++ }
  END { print n + 0 }' "$diff_file")
added_code=$(awk -v tests="$test_paths" '
  /^\+\+\+ / { path = substr($0, 5); sub(/^b\//, "", path); code = (path !~ tests && path != "/dev/null"); next }
  /^\+/ { if (code) print substr($0, 2) }' "$diff_file")

risk_lines=()
for rule in "${sensitive_rules[@]}"; do
  label=${rule%%|*}
  pattern=${rule#*|}
  hit=$(grep -vE "$uncounted_paths" "$changed_files" | grep -E "$pattern" | head -n 1 || true)
  [ -z "$hit" ] || risk_lines+=("risk: $label ($hit)")
done
deleted_file=$(awk '/^--- a\// { from = substr($0, 7) } /^\+\+\+ \/dev\/null/ { print from; exit }' "$diff_file")
[ -z "$deleted_file" ] || risk_lines+=("risk: deletes a file ($deleted_file)")
data_delete=$(printf '%s\n' "$added_code" | grep -E -i '\b(drop_table|remove_column|drop table|drop column|delete from|truncate|destroy_all|delete_all)\b' | head -n 1 | sed -E 's/^[[:space:]]+//' | cut -c1-80 || true)
[ -z "$data_delete" ] || risk_lines+=("risk: deletes data ($data_delete)")

code_lines=$(printf '%s\n' "$added_code" | grep -vE '^[[:space:]]*(#|//|/\*|\*|--)' || true)
branch_line=$(printf '%s\n' "$code_lines" | grep -E '\b(if|elsif|elif|else|unless|case|when|switch|while|until|rescue|catch|except|guard)\b|&&|\|\||\?\?|[[:space:]]\?[[:space:]]|\b(and|or)\b[[:space:]]' | head -n 1 | sed -E 's/^[[:space:]]+//' | cut -c1-80 || true)

size=small
[ "$counted_files" -le "$max_files" ] || size=full
[ "$changed_lines" -le "$max_lines" ] || size=full
[ "${#risk_lines[@]}" -eq 0 ] || size=full

echo "SIZE=$size"
if [ -n "$branch_line" ]; then echo "MUTATION=run"; else echo "MUTATION=skip"; fi
echo "files: $counted_files counted ($uncounted_files test, locale or generated left out)"
echo "lines: $changed_lines changed in counted files"
if [ "${#risk_lines[@]}" -eq 0 ]; then
  echo "risk: none"
else
  printf '%s\n' "${risk_lines[@]}"
fi
if [ -n "$branch_line" ]; then
  echo "mutation: an added line branches: $branch_line"
else
  echo "mutation: no added line adds a condition or branch"
fi
