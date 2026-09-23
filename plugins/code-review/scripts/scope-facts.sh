#!/usr/bin/env bash
# The facts review-code's scope checks (§G1 stacking, §G2 scope, §G3 linked
# issues) need, gathered in one run. It makes no judgment: the orchestrator
# decides whether a PR is stacked or out of scope.
#
# Usage: scope-facts.sh <pr-number> [--out-dir <dir>]
#   --out-dir  where the PR description and linked issue bodies are written
#              (default: ${TMPDIR:-/tmp}/kc-review-<head-sha>, the directory
#              gather-review.sh uses)
#
# Output, three labelled sections:
#   ## PR                 number, author, base, head, head sha, commits, files,
#                         and `description: <out-dir>/pr-body.md`
#   ## Author's other open PRs
#                         `#<n> head=<branch> base=<branch> commits=<count>`
#                         per PR (at most 100), or `(none)`
#   ## Linked issues      `#<n> <title> (body: <out-dir>/issue-<n>.md)` per
#                         issue in closingIssuesReferences, or `(none)`
#
# gh fields: https://cli.github.com/manual/gh_pr_view, gh_pr_list and
# gh_issue_view. A closingIssuesReferences entry carries number and url but no
# title, so each issue is read with `gh issue view <url>`, which also works for
# an issue in another repository.
# Exits 0 on success, 1 when a gh call fails, 2 on a usage error.
set -euo pipefail

script_name=$(basename "$0")
usage() {
  echo "usage: $script_name <pr-number> [--out-dir <dir>]" >&2
  exit 2
}
fail() {
  echo "$script_name: $1" >&2
  exit 1
}

pr_number=""
out_dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --out-dir)
      [ "$#" -ge 2 ] && [ -n "$2" ] || usage
      out_dir=$2
      shift
      ;;
    '' | *[!0-9]*) usage ;;
    *)
      [ -z "$pr_number" ] || usage
      pr_number=$1
      ;;
  esac
  shift
done
[ -n "$pr_number" ] || usage

tab=$(printf '\t')

# One `pr` record, one `issue` record per linked issue (tab-separated), then a
# `body` marker line followed by the PR description, which may span lines.
pr_records=$(gh pr view "$pr_number" \
  --json number,author,baseRefName,headRefName,headRefOid,commits,changedFiles,closingIssuesReferences,body \
  --jq '"pr\t\(.author.login)\t\(.baseRefName)\t\(.headRefName)\t\(.headRefOid)\t\(.commits | length)\t\(.changedFiles)",
        (.closingIssuesReferences[] | "issue\t\(.number)\t\(.url)"),
        "body", (.body // "")') \
  || fail "gh pr view $pr_number failed"

pr_header=$(printf '%s\n' "$pr_records" | sed '/^body$/,$d')
pr_line=$(printf '%s\n' "$pr_header" | grep "^pr$tab" | head -n 1)
[ -n "$pr_line" ] || fail "gh pr view $pr_number returned no PR"
IFS="$tab" read -r _ pr_author base_branch head_branch head_sha commit_count file_count <<EOF
$pr_line
EOF

[ -n "$out_dir" ] || { tmp_root=${TMPDIR:-/tmp}; out_dir="${tmp_root%/}/kc-review-$head_sha"; }
mkdir -p "$out_dir"
out_dir=$(cd "$out_dir" && pwd)
pr_body_file="$out_dir/pr-body.md"
printf '%s\n' "$pr_records" | sed '1,/^body$/d' > "$pr_body_file"

# The list query leaves out `commits`: 100 PRs with their commits exceeds
# GitHub's GraphQL node limit (measured: "requesting up to 1,000,000 possible
# nodes which exceeds the maximum limit of 500,000"). Each other PR's commit
# count comes from its own `gh pr view`, which stays well inside the limit.
other_pr_rows=$(gh pr list --author "$pr_author" --state open --limit 100 \
  --json number,headRefName,baseRefName \
  --jq '.[] | select(.number != '"$pr_number"') | "\(.number)\t\(.headRefName)\t\(.baseRefName)"') \
  || fail "gh pr list --author $pr_author failed"
other_prs=""
while IFS="$tab" read -r other_number other_head other_base; do
  [ -n "$other_number" ] || continue
  other_commits=$(gh pr view "$other_number" --json commits --jq '.commits | length') \
    || fail "gh pr view $other_number failed"
  other_prs="$other_prs#$other_number head=$other_head base=$other_base commits=$other_commits
"
done <<EOF_ROWS
$other_pr_rows
EOF_ROWS
other_prs=${other_prs%
}

echo "## PR"
echo "number: $pr_number"
echo "author: $pr_author"
echo "base: $base_branch"
echo "head: $head_branch"
echo "head sha: $head_sha"
echo "commits: $commit_count"
echo "files: $file_count"
echo "description: $pr_body_file"
echo
echo "## Author's other open PRs"
if [ -n "$other_prs" ]; then printf '%s\n' "$other_prs"; else echo "(none)"; fi
echo
echo "## Linked issues"
issue_lines=$(printf '%s\n' "$pr_header" | grep "^issue$tab" || true)
if [ -z "$issue_lines" ]; then
  echo "(none)"
  exit 0
fi
printf '%s\n' "$issue_lines" | while IFS="$tab" read -r _ issue_number issue_url; do
  # The title, then the body; a GitHub issue title is a single line.
  issue_view=$(gh issue view "$issue_url" --json number,title,body --jq '.title, .body') \
    || fail "gh issue view $issue_url failed"
  issue_title=$(printf '%s\n' "$issue_view" | sed -n 1p)
  issue_file="$out_dir/issue-$issue_number.md"
  printf '%s\n' "$issue_view" | sed -n '2,$p' > "$issue_file"
  echo "#$issue_number $issue_title (body: $issue_file)"
done
