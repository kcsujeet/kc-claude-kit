#!/usr/bin/env bash
# Tests scripts/lint-rules.sh and scripts/check-test-coverage.sh in throwaway repos shaped like the
# kit. Each failing case is a drift the kit has had or would have; each clean case is a real
# pattern of the kit's that must not be flagged.
set -euo pipefail

scripts_dir="$(cd "$(dirname "$0")/.." && pwd)"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
passes=0
failures=0

# Runs <checker> in <repo>; expects it to pass or to print a line containing <expected>.
check() {
  local label=$1 checker=$2 repo=$3 expected=$4 output status=0
  output=$(cd "$repo" && git add -A && bash "$scripts_dir/$checker" 2>&1) || status=$?
  if { [ "$expected" = clean ] && [ "$status" -eq 0 ]; } ||
    { [ "$expected" != clean ] && [ "$status" -ne 0 ] && printf '%s' "$output" | grep -qF "$expected"; }; then
    echo "ok   $label"
    passes=$((passes + 1))
  else
    echo "FAIL $label (expected: $expected; got status $status: $output)"
    failures=$((failures + 1))
  fi
}

# A repo with one topic skill (§T1 with box and detail, §RL3 served by lettered sub-boxes, and a
# reference file whose sub-checklist repeats its parent id) and one gate citing them.
new_kit() {
  local repo=$1
  mkdir -p "$repo/plugins/kit-a/skills/kc-testing/references" "$repo/plugins/kit-a/agents"
  git -C "$repo" init -q
  cat > "$repo/plugins/kit-a/skills/kc-testing/SKILL.md" <<'EOF'
## Review checklist
- [ ] §T1 Every new behavior has a test.
- [ ] §RL3a Work sits in the layer similar code uses.
- [ ] §RL3b One check, one place.
- [ ] §RL6 Stored values are renamed with a backfill; see `references/backfills.md`.
## Review detail
### §T1. New behavior has a test
### §RL3. Work in the app's own layers
EOF
  cat > "$repo/plugins/kit-a/skills/kc-testing/references/backfills.md" <<'EOF'
- [ ] §RL6 Every reader of the old value is listed.
- [ ] §RL6 The backfill runs before the old value stops being written.
EOF
  # shellcheck disable=SC2016  # backticks are literal Markdown
  printf 'Grade §T1 and §RL3a. Run `select-gates.sh`.\n' > "$repo/plugins/kit-a/agents/testing-gate.md"
  mkdir -p "$repo/plugins/kit-a/scripts" "$repo/plugins/kit-a/tests"
  printf '#!/usr/bin/env bash\necho gates\n' > "$repo/plugins/kit-a/scripts/select-gates.sh"
  printf '#!/usr/bin/env bash\nbash ../scripts/select-gates.sh\n' > "$repo/plugins/kit-a/tests/select-gates.test.sh"
}

# --- rules lint -------------------------------------------------------------------------
new_kit "$work_dir/clean"
check "lint: sub-boxes, a reference sub-checklist and resolved citations are clean" lint-rules.sh "$work_dir/clean" clean

new_kit "$work_dir/dup"
printf -- '- [ ] §T1 A value derived by convention is passed by a caller it misses.\n' >> "$work_dir/dup/plugins/kit-a/skills/kc-testing/SKILL.md"
check "lint: a new rule reusing an existing box id is flagged" lint-rules.sh "$work_dir/dup" "box id §T1 is used for more than one box"

new_kit "$work_dir/renumbered"
printf 'Also grade §T7.\n' >> "$work_dir/renumbered/plugins/kit-a/agents/testing-gate.md"
check "lint: a gate citing a rule that was renumbered away is flagged" lint-rules.sh "$work_dir/renumbered" "§T7 refers to no rule"

new_kit "$work_dir/no-box"
printf '### §T2. Exact assertions when the value is known\n' >> "$work_dir/no-box/plugins/kit-a/skills/kc-testing/SKILL.md"
check "lint: a rule added with a detail heading but no box is flagged" lint-rules.sh "$work_dir/no-box" "rule §T2 has a detail heading but no checklist box"

new_kit "$work_dir/renamed-script"
# shellcheck disable=SC2016  # backticks are literal Markdown
printf 'Enumerate with the `loose-assertions.sh` sweep.\n' >> "$work_dir/renamed-script/plugins/kit-a/skills/kc-testing/SKILL.md"
check "lint: a skill naming a script that was renamed or removed is flagged" lint-rules.sh "$work_dir/renamed-script" "names loose-assertions.sh, which is not in the repo"

# --- test coverage ----------------------------------------------------------------------
new_kit "$work_dir/covered"
mkdir -p "$work_dir/covered/plugins/kit-b/scripts" "$work_dir/covered/plugins/kit-a/scripts/lib" \
  "$work_dir/covered/plugins/kit-a/skills/kc-testing/scripts" "$work_dir/covered/plugins/kit-a/tests/sweeps/kc-testing/class-assertions" \
  "$work_dir/covered/scripts"
ln -s ../../kit-a/scripts/select-gates.sh "$work_dir/covered/plugins/kit-b/scripts/select-gates.sh"
printf '#!/usr/bin/env bash\n' > "$work_dir/covered/plugins/kit-a/skills/kc-testing/scripts/class-assertions.sh"
printf '+expect(el.className)\n' > "$work_dir/covered/plugins/kit-a/tests/sweeps/kc-testing/class-assertions/input.diff"
printf '# shellcheck shell=bash\n' > "$work_dir/covered/plugins/kit-a/scripts/lib/diff-lines.sh"
printf 'plugins/kit-a/scripts/lib/diff-lines.sh sourced by every sweep, run through their fixtures\n' > "$work_dir/covered/scripts/test-coverage-exempt.txt"
check "coverage: a tested script, its symlinked copy, a sweep fixture and an exempt library pass" check-test-coverage.sh "$work_dir/covered" clean

new_kit "$work_dir/untested"
printf '#!/usr/bin/env bash\necho size\n' > "$work_dir/untested/plugins/kit-a/scripts/pass-size.sh"
check "coverage: a new script with no test is flagged" check-test-coverage.sh "$work_dir/untested" "plugins/kit-a/scripts/pass-size.sh has no test"

new_kit "$work_dir/bare-exempt"
mkdir -p "$work_dir/bare-exempt/scripts"
printf '#!/usr/bin/env bash\n' > "$work_dir/bare-exempt/plugins/kit-a/scripts/pass-size.sh"
printf 'plugins/kit-a/scripts/pass-size.sh\n' > "$work_dir/bare-exempt/scripts/test-coverage-exempt.txt"
check "coverage: an exemption with no reason doesn't count" check-test-coverage.sh "$work_dir/bare-exempt" "plugins/kit-a/scripts/pass-size.sh has no test"

new_kit "$work_dir/dangling"
mkdir -p "$work_dir/dangling/plugins/kit-b/scripts"
ln -s ../../kit-a/scripts/gather-review.sh "$work_dir/dangling/plugins/kit-b/scripts/gather-review.sh"
check "coverage: a shared copy linked to a script that was renamed away is flagged" check-test-coverage.sh "$work_dir/dangling" "plugins/kit-b/scripts/gather-review.sh has no test"

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
