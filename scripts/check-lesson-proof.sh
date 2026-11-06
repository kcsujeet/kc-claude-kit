#!/usr/bin/env bash
# Fails when a change since <base> edits a rule (a skill, a skill reference, an agent or the working
# agreement) without proof that the rule catches something: an eval case or a script test changed in
# the same change. A lesson is a checklist box (`- [ ] §X1`): every box the change adds or rewrites
# is named, by its id, in one of those eval or test files, so the proof is tied to that rule, and a
# rule file that gains lines with no box added or rewritten in it gained prose no gate walks. A file
# with no boxes at all (an agent, the working agreement) is the same. Either way, a change that only
# moves words says so in the pull request description, on a line of its own: `wording-only: <why>`.
#
# CLAUDE.md's Lessons step 4 asks for that proof; a skip has to be stated here, so the reviewer
# reads the reason.
#
# Usage: scripts/check-lesson-proof.sh <base-ref> [--body-file <file>]
#   <base-ref>    the branch the change merges into
#   --body-file   the pull request description, for its `wording-only:` line
set -euo pipefail

usage() { echo "usage: scripts/check-lesson-proof.sh <base-ref> [--body-file <file>]" >&2; exit 2; }
[ "$#" -ge 1 ] || usage
base=$1
shift
body_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --body-file) [ "$#" -ge 2 ] || usage; body_file=$2; shift 2 ;;
    *) usage ;;
  esac
done
if [ -n "$body_file" ] && [ ! -r "$body_file" ]; then
  echo "cannot read $body_file" >&2
  exit 2
fi

merge_base=$(git merge-base "$base" HEAD) || {
  echo "$base and HEAD share no commit, so there is no change to check; check the base branch" >&2
  exit 2
}
# Paths as they are, not quoted, so a non-ASCII name still matches the patterns.
changed_files=$(git -c core.quotePath=false diff --name-only "$merge_base" HEAD)

changed_rule_files=$(printf '%s\n' "$changed_files" | grep -E '^plugins/[^/]+/(skills/.+\.md|agents/[^/]+\.md|rules/kc-working-agreement\.md)$' || true)
if [ -z "$changed_rule_files" ]; then
  echo "ok   no rule changed"
  exit 0
fi

# Rule files that gain lines, blank ones aside, none of them a checklist box: prose a test changed
# elsewhere can't stand in for.
prose_rule_files=""
while IFS= read -r path; do
  added_lines=$(git -c core.quotePath=false diff --unified=0 --no-color --no-ext-diff "$merge_base" HEAD -- "$path" \
    | grep -E '^\+' | grep -vE '^\+\+\+ (b/|/dev/null)' | grep -vE '^\+[[:space:]]*$' || true)
  if [ -n "$added_lines" ] && ! printf '%s\n' "$added_lines" | grep -qE '^\+[[:space:]]*- \[[ xX]\] §[A-Z]+[0-9]'; then
    prose_rule_files="$prose_rule_files$path"$'\n'
  fi
done <<< "$changed_rule_files"

# Eval and test files the change adds lines to: one it deletes, only takes lines from or only
# renames proves nothing. With -z, numstat gives a rename's old and new path on lines of their own
# after an empty path field; the new path is the one kept.
changed_proof_files=$(git -c core.quotePath=false diff --numstat -z -M "$merge_base" HEAD | tr '\0' '\n' \
  | awk -F '\t' '
      paths_to_skip > 0 { paths_to_skip--; if (paths_to_skip == 0 && added > 0) print; next }
      { added = $1 + 0 }
      $3 == "" { paths_to_skip = 2; next }
      added > 0 { print $3 }' \
  | grep -E '^(plugins/[^/]+/(evals|tests)/|scripts/tests/)' || true)
# Of those, the ones that can name a box id as its proof: a test script, or an eval's grader,
# setup.sh or case.yaml. A fixture or other data file that only mentions the id proves nothing.
id_proof_files=$(printf '%s\n' "$changed_proof_files" \
  | grep -E '^(plugins/[^/]+/tests|scripts/tests)/[^/]+\.sh$|^plugins/[^/]+/evals/[^/]+/(graders/[^/]+|setup\.sh|case\.yaml)$' || true)

# The ids of the checklist boxes the change adds or rewrites, and those no changed eval or test
# file names. An id is letters, a number, any `.<number>` parts and an optional letter (§T1,
# §RL6.1a); one followed by a letter, a digit or `.<digit>` is another id: §T1 is not §T12, and
# §RL6 is not §RL6.1a. A period right after the id (`§B2. Text`) ends it.
if [ -n "$changed_proof_files" ]; then
  rule_paths=()
  while IFS= read -r path; do rule_paths+=("$path"); done <<< "$changed_rule_files"
  proof_paths=()
  while IFS= read -r path; do [ -z "$path" ] || proof_paths+=("$path"); done <<< "$id_proof_files"
  changed_box_ids=$(git diff --unified=0 --no-color --no-ext-diff "$merge_base" HEAD -- "${rule_paths[@]}" \
    | sed -nE 's/^\+[[:space:]]*- \[[ xX]\] (§[A-Z]+[0-9]+(\.[0-9]+)*[a-z]?)([^.0-9a-z].*|\.([^0-9].*)?)?$/\1/p' | sort -u)
  unproven_box_ids=""
  for box_id in $changed_box_ids; do
    if [ "${#proof_paths[@]}" -eq 0 ] \
      || ! git grep -qE "${box_id//./\\.}(\\.?[^.0-9a-z]|\\.?\$)" HEAD -- "${proof_paths[@]}" 2>/dev/null; then
      unproven_box_ids="$unproven_box_ids $box_id"
    fi
  done
  if [ -z "$unproven_box_ids" ] && [ -z "$prose_rule_files" ]; then
    echo "ok   rules changed with proof: $(printf '%s\n' "$changed_proof_files" | wc -l | tr -d ' ') eval or test file(s)"
    exit 0
  fi
fi

reason=""
[ -z "$body_file" ] || reason=$(sed -nE 's/^[[:space:]]*wording-only:[[:space:]]*(.*)$/\1/Ip' "$body_file" | head -n 1)
# A description edited on the web ends its lines in `\r`, and may leave trailing spaces.
reason=$(printf '%s' "$reason" | sed -E 's/[[:space:]]+$//')
# The placeholder from the checklist and this script's own hint (`<why>`) is no reason.
case "$reason" in "<"*">") reason="" ;; esac
if [ -n "$reason" ]; then
  echo "ok   rules changed, wording only: $reason"
  exit 0
fi

if [ -z "$changed_proof_files" ]; then
  echo "FAIL these rules changed with no eval case or script test beside them:"
  printf '%s\n' "$changed_rule_files" | sed 's/^/       /'
  echo "     Prove the rule catches its case (an eval under the plugin's evals/, or a script with a test),"
else
  if [ -n "${unproven_box_ids:-}" ]; then
    echo "FAIL these checklist boxes changed with no changed eval case or script test naming them:$unproven_box_ids"
    echo "     Name each box's id in the eval grader, the eval's setup.sh or the test that proves it,"
  fi
  if [ -n "$prose_rule_files" ]; then
    echo "FAIL these rule files gain lines but no checklist box:"
    printf '%s' "$prose_rule_files" | sed 's/^/       /'
    echo "     Write the lesson as a box on the file's checklist, proven by an eval or test naming its id,"
  fi
fi
echo "     or, when only the words move, add a line to the pull request description: wording-only: <why>"
exit 1
