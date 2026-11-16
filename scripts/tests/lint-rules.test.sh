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
# shellcheck disable=SC2016  # backticks are literal Markdown
printf 'Enumerate with the `loose-assertions.sh` sweep.\n' >> "$work_dir/renamed-script/plugins/kit-a/skills/kc-testing/SKILL.md"
check "lint: a skill naming a script that was renamed or removed is flagged" lint-rules.sh "$work_dir/renamed-script" "names loose-assertions.sh, which is not in the repo"

new_kit "$work_dir/links-ok"
mkdir -p "$work_dir/links-ok/docs"
printf '# Architecture\n' > "$work_dir/links-ok/docs/architecture.md"
# shellcheck disable=SC2016  # backticks are literal Markdown
printf 'Attach with ![alt](<file>). See [layout](docs/architecture.md#layout), [site](https://example.com/x.md), [here](#top) and [skill](plugins/kit-a/skills/kc-testing/SKILL.md). Also `docs/architecture.md`.\n' > "$work_dir/links-ok/README.md"
printf 'See [back](../README.md) and [sibling](architecture.md).\n' >> "$work_dir/links-ok/docs/architecture.md"
check "lint: resolving links, anchors, http links and docs paths are clean" lint-rules.sh "$work_dir/links-ok" clean

new_kit "$work_dir/stale-link"
printf 'More in [the reference](docs/reference.md#install).\n' > "$work_dir/stale-link/README.md"
check "lint: a README link to a file that does not exist is flagged" lint-rules.sh "$work_dir/stale-link" "README.md: links to docs/reference.md, which is not in the repo"

new_kit "$work_dir/stale-relative-link"
printf 'See [other](../missing.md).\n' >> "$work_dir/stale-relative-link/plugins/kit-a/agents/testing-gate.md"
check "lint: a relative link in a plugin file is resolved from that file" lint-rules.sh "$work_dir/stale-relative-link" "links to ../missing.md"

new_kit "$work_dir/stale-docs-path"
# shellcheck disable=SC2016  # backticks are literal Markdown
printf 'Details in `docs/reference.md`.\n' > "$work_dir/stale-docs-path/CLAUDE.md"
check "lint: a backticked docs path that does not exist is flagged" lint-rules.sh "$work_dir/stale-docs-path" "CLAUDE.md: links to docs/reference.md"

new_kit "$work_dir/plugin-docs-path"
# shellcheck disable=SC2016  # backticks are literal Markdown
printf 'Use the repo template in `docs/pull_request_template.md`.\n' >> "$work_dir/plugin-docs-path/plugins/kit-a/agents/testing-gate.md"
check "lint: a docs path in plugin text names the installing repo's file and is not flagged" lint-rules.sh "$work_dir/plugin-docs-path" clean

new_agreement() {
  mkdir -p "$1/plugins/kc-conventions/rules"
  printf '## Order of work on a task\n\n1. **Assess.** x\n2. **Build.** y\n3. **Look back.** z\n\n## Report honestly\n\n4. not a step\n' > "$1/plugins/kc-conventions/rules/kc-working-agreement.md"
}

new_kit "$work_dir/step-ok"
new_agreement "$work_dir/step-ok"
printf 'Passes the working agreement'"'"'s step 3 bar; see Order of work on a task, step 2.\n' > "$work_dir/step-ok/CLAUDE.md"
check "lint: citations of steps the working agreement has are clean" lint-rules.sh "$work_dir/step-ok" clean

new_kit "$work_dir/step-stale"
new_agreement "$work_dir/step-stale"
printf 'Passes the working agreement'"'"'s step 6 bar.\n' > "$work_dir/step-stale/CLAUDE.md"
check "lint: a citation of a step the working agreement no longer has is flagged" lint-rules.sh "$work_dir/step-stale" "cites the working agreement's step 6, but its Order of work on a task has 3 steps"

new_kit "$work_dir/step-stale-heading"
new_agreement "$work_dir/step-stale-heading"
printf 'See Order of work on a task, step 4.\n' > "$work_dir/step-stale-heading/CLAUDE.md"
check "lint: a step past the end of the list is flagged even when a later list numbers it" lint-rules.sh "$work_dir/step-stale-heading" "step 4"

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
