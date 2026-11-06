#!/usr/bin/env bash
# Runs every eval case a change since <base> adds or changes, once with its plugin and once in the
# eval runner's baseline arm without it, and fails unless each case passes with the plugin and fails
# without it. So a lesson's case is shown to catch what the kit teaches and what Claude misses
# alone: the run is the proof, not a file naming the rule. A case tagged `negative` (the plugin must
# leave an unrelated request alone) needs only the first, since the baseline passes it by design.
# Cases the change doesn't touch aren't run, so a change to no case costs nothing.
#
# In CI (GITHUB_ACTIONS=true) the runs need ANTHROPIC_API_KEY: a change to a case with no key fails
# and says so, never skips. Elsewhere claude runs on your own login.
#
# Usage: scripts/run-changed-evals.sh <base-ref> [--list]
#   <base-ref>  the branch the change merges into
#   --list      print the changed cases, one `plugins/<plugin>/evals/<case>` per line, and run none
#
# Needs jq. Run it from the repo root.
set -euo pipefail

usage() { echo "usage: scripts/run-changed-evals.sh <base-ref> [--list]" >&2; exit 2; }
[ "$#" -ge 1 ] || usage
base=$1
shift
list_only=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --list) list_only=true; shift ;;
    *) usage ;;
  esac
done

merge_base=$(git merge-base "$base" HEAD) || {
  echo "$base and HEAD share no commit, so there is no change to check; check the base branch" >&2
  exit 2
}

# A case is a folder under a plugin's evals/ holding case.yaml or prompt.md at HEAD; results/ and
# mocks/ are the runner's, and a case the change deletes has nothing left to run.
changed_cases=$(git -c core.quotePath=false diff --name-only "$merge_base" HEAD \
  | sed -nE 's#^(plugins/[^/]+/evals/[^/]+)/.*#\1#p' \
  | { grep -vE '/evals/(results|mocks)$' || true; } | sort -u \
  | while IFS= read -r case_dir; do
      if git cat-file -e "HEAD:$case_dir/case.yaml" 2>/dev/null || git cat-file -e "HEAD:$case_dir/prompt.md" 2>/dev/null; then
        printf '%s\n' "$case_dir"
      fi
    done)

if $list_only; then
  [ -z "$changed_cases" ] || printf '%s\n' "$changed_cases"
  exit 0
fi
if [ -z "$changed_cases" ]; then
  echo "ok   no eval case changed"
  exit 0
fi
if [ "${GITHUB_ACTIONS:-}" = true ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "FAIL these eval cases changed, and CI has no ANTHROPIC_API_KEY secret to run them with:"
  printf '%s\n' "$changed_cases" | sed 's/^/       /'
  echo "     Add the secret to the repository (Settings, Secrets and variables, Actions), then run the job again."
  exit 1
fi

results_dir=$(mktemp -d)
trap 'rm -rf "$results_dir"' EXIT
failures=0

while IFS= read -r case_dir; do
  plugin_dir=${case_dir%/evals/*}
  case_name=${case_dir##*/}
  # Its name, tags and plugins come from case.yaml or prompt.md's front matter.
  case_files=()
  for file in "$case_dir/case.yaml" "$case_dir/prompt.md"; do
    [ ! -f "$file" ] || case_files+=("$file")
  done
  name_field=$(sed -nE "s/^name:[[:space:]]*['\"]?([^'\"]+)['\"]?[[:space:]]*$/\\1/p" "${case_files[@]}" | head -n 1)
  [ -z "$name_field" ] || case_name=$name_field
  negative=false
  if grep -hE '^tags:' "${case_files[@]}" | tr -c 'a-z-' '\n' | grep -qx negative; then
    negative=true
  fi
  # A case that loads a plugin beside its own (`../../../kc-conventions`) runs from the repo root
  # with --eval-dir: the runner loads only plugins inside the directory it runs against.
  target=("$plugin_dir")
  if grep -qF '../../../' "${case_files[@]}"; then
    target=(. --eval-dir "$plugin_dir/evals")
  fi
  result=$results_dir/${case_dir//\//_}.json
  echo "run  $case_dir"
  # --allow-tools takes a list, so it stays last.
  claude plugin eval "${target[@]}" \
    --case "$case_name" \
    --runs 1 \
    --ablation with-without \
    --trust-plugin \
    --scaffold \
    --json "$result" \
    --model claude-sonnet-5 \
    --judge-model claude-haiku-4-5 \
    --no-publish \
    --max-cost-usd 10 \
    --allow-tools Bash Agent >&2 || true
  if [ ! -s "$result" ]; then
    echo "FAIL $case_dir: the eval run wrote no result"
    failures=$((failures + 1))
    continue
  fi
  verdict=$(jq -r --arg name "$case_name" --argjson negative "$negative" '
    (.cases[] | select(.name == $name)) as $case
    | ($case.arms.with // []) as $with
    | ($case.arms.without // []) as $without
    | if ($with | length) == 0 then "no run with the plugin"
      elif any($with[]; .error != null) then "the run with the plugin errored"
      elif any($with[]; any(.graders[]; .passed | not)) then
        "with the plugin, graders failed: " + ([$with[].graders[] | select(.passed | not) | .name] | unique | join(", "))
      elif $negative then "ok"
      elif ($without | length) == 0 then "no run without the plugin"
      elif any($without[]; .error != null) then "the run without the plugin errored"
      elif any($without[]; all(.graders[] | select(.scored); .passed)) then "it passes without the plugin too, so it proves nothing the kit adds"
      else "ok" end' "$result" 2>/dev/null || echo "its result has no case named $case_name")
  verdict=${verdict:-"its result has no case named $case_name"}
  if [ "$verdict" = ok ]; then
    if $negative; then
      echo "ok   $case_dir: passes with the plugin (a negative case, so the baseline may pass too)"
    else
      echo "ok   $case_dir: passes with the plugin, fails without it"
    fi
  else
    echo "FAIL $case_dir: $verdict"
    failures=$((failures + 1))
  fi
done <<< "$changed_cases"

[ "$failures" -eq 0 ]
