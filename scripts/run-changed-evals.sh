#!/usr/bin/env bash
# Runs every eval case a change since <base> adds or changes, once with its plugin and once in the
# eval runner's baseline arm without it, on your own Claude login, and writes the outcome to the
# case's proof.json for the pull request to carry. A case passes when it passes every grader with
# the plugin and fails every scored grader without it, so each grader is shown to catch what the
# kit teaches and Claude misses alone. A grader the baseline passes too proves nothing the kit adds,
# even beside one it fails (a verdict format). A case tagged `negative` (the plugin must leave an
# unrelated request alone) needs only the first, since the baseline passes it by design.
#
# When the change also edits rules (a skill, an agent or a rule file) in a plugin the case loads,
# the case runs a third time, with the plugin as it is at HEAD except those rule files, which are
# put back as the base has them. It must fail a scored grader there: a case that passes with the
# rule edits taken out shows what the kit already did, not what this change adds. A case tagged
# `guard` says so itself (it holds behaviour the kit already has, against a later regression) and
# skips that run; it can't stand as the proof of a box, which a test or another case then names.
#
# With --check, which CI runs, nothing is run and no key is needed: each changed case must carry a
# proof.json whose run passed, made from the case's files and the code of every plugin it loads as
# they are at HEAD. A later edit to either makes the record stale, and the case runs again. The
# record shows the run happened, as a receipt does; it can't show it wasn't edited by hand.
#
# Usage: scripts/run-changed-evals.sh <base-ref> [--check]
#   <base-ref>  the branch the change merges into
#   --check     check each changed case's proof.json instead of running it
#
# Needs jq. Run it from the repo root, with the change committed.
set -euo pipefail

readonly PROOF_FILE=proof.json
# Model names, not versions: the run uses whichever version the name points at when it runs, and
# the record says which claude ran it.
readonly MODEL=sonnet
readonly JUDGE_MODEL=haiku

usage() { echo "usage: scripts/run-changed-evals.sh <base-ref> [--check]" >&2; exit 2; }
[ "$#" -ge 1 ] || usage
base=$1
shift
check_only=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) check_only=true; shift ;;
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

if [ -z "$changed_cases" ]; then
  echo "ok   no eval case changed"
  exit 0
fi

# Prints <case_dir>'s case.yaml and prompt.md as they are at HEAD, the files its name, tags and
# plugins come from.
print_case_files() {
  local file
  for file in case.yaml prompt.md; do
    git show "HEAD:$1/$file" 2>/dev/null || true
  done
}

# Prints the plugin folders <case_dir> loads: its own, and each one beside it it names
# (`../../../kc-conventions`).
list_case_plugins() {
  local case_dir=$1
  {
    printf '%s\n' "${case_dir%/evals/*}"
    print_case_files "$case_dir" | grep -oE '\.\./\.\./\.\./[A-Za-z0-9._-]+' | sed 's#^\.\./\.\./\.\./#plugins/#' || true
  } | sort -u
}

# Hashes what git holds at HEAD under <case_dir>, its proof.json aside.
hash_case() {
  git -c core.quotePath=false ls-tree -r HEAD -- "$1/" | { grep -vF "	$1/$PROOF_FILE" || true; } | git hash-object --stdin
}

# Hashes what git holds at HEAD under each plugin folder given, its evals/ aside.
hash_plugins() {
  local plugin_dir
  for plugin_dir in "$@"; do
    git -c core.quotePath=false ls-tree -r HEAD -- "$plugin_dir/" | { grep -vF "	$plugin_dir/evals/" || true; }
  done | git hash-object --stdin
}

# Prints the rule files the change edits under the plugin folders given.
list_changed_rules() {
  git -c core.quotePath=false diff --name-only "$merge_base" HEAD -- "$@" \
    | grep -E '^plugins/[^/]+/(skills/.+\.md|agents/[^/]+\.md|rules/[^/]+\.md)$' || true
}

# True when <case_dir>'s tags hold <tag>.
has_tag() {
  print_case_files "$1" | grep -E '^tags:' | tr -c 'a-z-' '\n' | grep -qx "$2"
}

if $check_only; then
  failures=0
  while IFS= read -r case_dir; do
    plugin_dirs=()
    while IFS= read -r plugin_dir; do plugin_dirs+=("$plugin_dir"); done < <(list_case_plugins "$case_dir")
    if ! record=$(git show "HEAD:$case_dir/$PROOF_FILE" 2>/dev/null) || ! printf '%s' "$record" | jq -e 'type == "object"' >/dev/null 2>&1; then
      problem="no local run recorded"
    elif [ "$(printf '%s' "$record" | jq -r '.case_hash')" != "$(hash_case "$case_dir")" ]; then
      problem="its record was made from other case files"
    elif [ "$(printf '%s' "$record" | jq -r '.plugins_hash')" != "$(hash_plugins "${plugin_dirs[@]}")" ]; then
      problem="its record was made from other code in ${plugin_dirs[*]}"
    elif [ "$(printf '%s' "$record" | jq -r '.verdict')" != ok ]; then
      problem="its recorded run failed: $(printf '%s' "$record" | jq -r '.verdict')"
    else
      echo "ok   $case_dir: its recorded run passed ($(printf '%s' "$record" | jq -r '.commit[0:7]'))"
      continue
    fi
    echo "FAIL $case_dir: $problem"
    failures=$((failures + 1))
  done <<< "$changed_cases"
  if [ "$failures" -gt 0 ]; then
    echo "     Run bash scripts/run-changed-evals.sh $base on the head commit and commit the $PROOF_FILE it writes."
    exit 1
  fi
  exit 0
fi

# The record names the commit it ran on, so the change is committed first; a proof.json written by
# an earlier run may be left over.
if [ -n "$(git status --porcelain --untracked-files=no -- . ":(exclude,glob)**/$PROOF_FILE")" ]; then
  echo "commit or stash your changes first: each case's record names the commit it ran on" >&2
  exit 2
fi

results_dir=$(mktemp -d)
trap 'rm -rf "$results_dir"' EXIT
failures=0
claude_version=$(claude --version 2>/dev/null | head -n 1 || true)

while IFS= read -r case_dir; do
  plugin_dir=${case_dir%/evals/*}
  case_name=${case_dir##*/}
  name_field=$(print_case_files "$case_dir" | sed -nE "s/^name:[[:space:]]*['\"]?([^'\"]+)['\"]?[[:space:]]*$/\\1/p" | head -n 1)
  [ -z "$name_field" ] || case_name=$name_field
  negative=false
  if has_tag "$case_dir" negative; then negative=true; fi
  plugin_dirs=()
  while IFS= read -r loaded_dir; do plugin_dirs+=("$loaded_dir"); done < <(list_case_plugins "$case_dir")
  # A case that loads a plugin beside its own runs from the repo root with --eval-dir: the runner
  # loads only plugins inside the directory it runs against.
  target=("$plugin_dir")
  if [ "${#plugin_dirs[@]}" -gt 1 ]; then
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
    --model "$MODEL" \
    --judge-model "$JUDGE_MODEL" \
    --no-publish \
    --max-cost-usd 10 \
    --allow-tools Bash Agent >&2 || true
  if [ ! -s "$result" ]; then
    verdict="the eval run wrote no result"
    printf '{}\n' > "$result"
  else
    verdict=$(jq -r --arg name "$case_name" --argjson negative "$negative" '
      (.cases[] | select(.name == $name)) as $case
      | ($case.arms.with // []) as $with
      | ($case.arms.without // []) as $without
      | if ($with | length) == 0 then "no run with the plugin"
        elif any($with[]; .error != null) then "the run with the plugin errored"
        elif any($with[]; (.graders // []) | length == 0) then "the run with the plugin has no graders, so it checks nothing"
        elif any($with[]; any(.graders[]; .passed | not)) then
          "with the plugin, graders failed: " + ([$with[].graders[] | select(.passed | not) | .name] | unique | join(", "))
        elif $negative then "ok"
        elif ($without | length) == 0 then "no run without the plugin"
        elif any($without[]; .error != null) then "the run without the plugin errored"
        elif any($without[]; ([.graders[] | select(.scored)] | length) == 0) then "the run without the plugin has no scored grader"
        elif any($without[]; any(.graders[] | select(.scored); .passed)) then
          "without the plugin, graders passed too, so they prove nothing the kit adds: " + ([$without[].graders[] | select(.scored and .passed) | .name] | unique | join(", "))
        else "ok" end' "$result" 2>/dev/null || true)
    verdict=${verdict:-"its result has no case named $case_name"}
  fi
  # The third run: the same case with this change's rule edits taken out.
  base_result=$results_dir/${case_dir//\//_}.base.json
  printf '{}\n' > "$base_result"
  changed_rules=$(list_changed_rules "${plugin_dirs[@]}")
  proves="fails without it"
  if [ "$verdict" = ok ] && ! $negative && [ -n "$changed_rules" ]; then
    if has_tag "$case_dir" guard; then
      proves="fails without it (a guard case: it holds what the kit already did, and proves no rule this change edits)"
    else
      base_tree=$results_dir/base-rules
      git worktree add -q --detach "$base_tree" HEAD
      while IFS= read -r rule_path; do
        if git cat-file -e "$merge_base:$rule_path" 2>/dev/null; then
          git -C "$base_tree" checkout -q "$merge_base" -- "$rule_path"
        else
          rm -f "$base_tree/$rule_path"
        fi
      done <<< "$changed_rules"
      echo "run  $case_dir, without this change's rule edits"
      ( cd "$base_tree" && claude plugin eval "${target[@]}" \
          --case "$case_name" \
          --runs 1 \
          --ablation none \
          --trust-plugin \
          --scaffold \
          --json "$base_result" \
          --model "$MODEL" \
          --judge-model "$JUDGE_MODEL" \
          --no-publish \
          --max-cost-usd 10 \
          --allow-tools Bash Agent >&2 ) || true
      git worktree remove --force "$base_tree"
      [ -s "$base_result" ] || printf '{}\n' > "$base_result"
      verdict=$(jq -r --arg name "$case_name" '
        ([(.cases // [])[] | select(.name == $name) | .arms.with // []] | first // []) as $runs
        | if ($runs | length) == 0 then "the run without this change'"'"'s rule edits wrote no result"
          elif any($runs[]; .error != null) then "the run without this change'"'"'s rule edits errored"
          elif all($runs[]; all((.graders // [])[] | select(.scored); .passed)) then
            "with this change'"'"'s rule edits taken out every grader still passes, so the case does not prove them; a case that holds what the kit already did is tagged guard"
          else "ok" end' "$base_result" 2>/dev/null || true)
      verdict=${verdict:-"the run without this change's rule edits wrote no result"}
      proves="fails without it, and fails with this change's rule edits taken out"
    fi
  fi
  jq -n \
    --arg case "$case_dir" \
    --arg name "$case_name" \
    --arg commit "$(git rev-parse HEAD)" \
    --arg case_hash "$(hash_case "$case_dir")" \
    --arg plugins_hash "$(hash_plugins "${plugin_dirs[@]}")" \
    --arg claude "$claude_version" \
    --arg model "$MODEL" \
    --arg verdict "$verdict" \
    --slurpfile result "$result" \
    --slurpfile base "$base_result" \
    '{case: $case, commit: $commit, case_hash: $case_hash, plugins_hash: $plugins_hash, claude: $claude,
      model: $model, verdict: $verdict,
      runs: (([($result[0].cases // [])[] | select(.name == $name) | .arms
              | map_values(map({error, graders: [(.graders // [])[] | {name, passed, scored}]}))] | first)
             + ([($base[0].cases // [])[] | select(.name == $name)
                 | {base_rules: (.arms.with // [] | map({error, graders: [(.graders // [])[] | {name, passed, scored}]}))}] | first // {}))}' \
    > "$case_dir/$PROOF_FILE"
  if [ "$verdict" = ok ]; then
    if $negative; then
      echo "ok   $case_dir: passes with the plugin (a negative case, so the baseline may pass too)"
    else
      echo "ok   $case_dir: passes with the plugin, $proves"
    fi
  else
    echo "FAIL $case_dir: $verdict"
    failures=$((failures + 1))
  fi
done <<< "$changed_cases"

echo "     Each case's record is in its $PROOF_FILE; commit them with the change."
[ "$failures" -eq 0 ]
