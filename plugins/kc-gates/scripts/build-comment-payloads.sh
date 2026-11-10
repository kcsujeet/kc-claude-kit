#!/usr/bin/env bash
# Turns drafted review comments into one GitHub review payload, after checking
# every draft against the diff, and prints the post command for the user to
# approve. It never posts and never runs gh.
#
# Usage: build-comment-payloads.sh <drafts.json> <diff-file> <head-sha> --pr <n> [--body-file <file>] [--out-dir <dir>]
#   <drafts.json>  a JSON array of {path, line, body}, each optionally with
#                  start_line, side and start_side
#   <diff-file>    the unified diff the comments anchor to (gather-review.sh's
#                  review.diff)
#   <head-sha>     the full 40-character head commit SHA
#   --pr <n>       the PR number the printed command posts to
#   --body-file    the review's top-level body, when it has one (omitted otherwise)
#   --out-dir      where payloads go (default: ${TMPDIR:-/tmp}/kc-review-<sha>)
#
# Validation, per the create-a-review-comment docs
# (https://docs.github.com/en/rest/pulls/comments#create-a-review-comment-for-a-pull-request):
#   - `path` is a file in the diff;
#   - `line` (and `start_line`) is a line "in the pull request diff": for side
#     RIGHT (the default) a line a hunk covers on the new side, added or
#     context; for side LEFT a line a hunk covers on the old side, removed or
#     context. `start_side` defaults to `side`;
#   - a range has start_line before line (the REST docs do not say a range must
#     stay inside one hunk, so that is not checked);
#   - `body` is not empty.
#   - the body passes kc-post-review's format rules (scripts/check-draft-format.sh);
#   - no name the body suggests is one letter from a name already in the repo
#     (scripts/check-draft-names.sh, when run from inside the repo).
# Every failing draft is listed on stderr, and nothing is written.
#
# Output: one checked comment per draft at <out-dir>/comment-<i>.json,
# {commit_id, path, line, side, body} plus start_line and start_side for a
# range, and all of them in one review at <out-dir>/review.json,
# {commit_id, event: "COMMENT", comments, body when --body-file has one}. Every
# comment of one review goes up in that one request, so GitHub shows one review:
# the single-comment endpoint wraps each comment in a review of its own. GitHub
# accepts a COMMENT review with inline comments and no body. Then the one
# command the user approves, carrying the approval token (docs/architecture.md),
# printed and not run:
#   KC_REVIEW_POST_APPROVED=1 gh api repos/{owner}/{repo}/pulls/<n>/reviews -X POST --input <review.json>
#
# Requires jq. Exits 0 when every draft is valid, 1 when any draft fails
# validation or jq is missing, 2 on a usage error or unreadable input.
set -euo pipefail

script_name=$(basename "$0")
usage() {
  echo "usage: $script_name <drafts.json> <diff-file> <head-sha> --pr <n> [--body-file <file>] [--out-dir <dir>]" >&2
  exit 2
}
input_error() {
  echo "$script_name: $1" >&2
  exit 2
}

positional=()
pr_number=""
body_file=""
out_dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --pr)
      [ "$#" -ge 2 ] || usage
      pr_number=$2
      shift
      ;;
    --body-file)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then usage; fi
      body_file=$2
      shift
      ;;
    --out-dir)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then usage; fi
      out_dir=$2
      shift
      ;;
    -*) usage ;;
    *) positional+=("$1") ;;
  esac
  shift
done
[ "${#positional[@]}" -eq 3 ] || usage
drafts_file=${positional[0]}
diff_file=${positional[1]}
head_sha=${positional[2]}
case "$pr_number" in '' | *[!0-9]*) usage ;; esac

command -v jq >/dev/null 2>&1 || {
  echo "$script_name: jq is required but not installed (https://jqlang.org/download/)" >&2
  exit 1
}
[ -r "$drafts_file" ] || input_error "cannot read drafts file: $drafts_file"
[ -r "$diff_file" ] || input_error "cannot read diff file: $diff_file"
[ -z "$body_file" ] || [ -r "$body_file" ] || input_error "cannot read body file: $body_file"
printf '%s' "$head_sha" | grep -Eq '^[0-9a-f]{40}$' || input_error "head SHA must be the full 40-character SHA: $head_sha"
jq -e 'type == "array"' "$drafts_file" >/dev/null 2>&1 || input_error "drafts file is not a JSON array: $drafts_file"

# Every line each hunk covers: `R<TAB>path<TAB>line<TAB>hunk` on the new side,
# `L<TAB>path<TAB>line<TAB>hunk` on the old side, and `P<TAB>path` per file
# (the new path, or the old one for a deletion). Hunk bodies are walked by their
# line counts, so a body line starting with `---` or `+++` is never a header.
coverage=$(awk '
  function header_path(line,    target) {
    target = substr(line, 5)
    sub(/\t.*$/, "", target)
    return target
  }
  # "12,5" or "12" -> sets span_start and span_length.
  function parse_span(spec) {
    if (index(spec, ",") > 0) {
      span_start = substr(spec, 1, index(spec, ",") - 1) + 0
      span_length = substr(spec, index(spec, ",") + 1) + 0
    } else {
      span_start = spec + 0
      span_length = 1
    }
  }
  BEGIN { old_left = 0; new_left = 0; hunk = 0 }
  old_left > 0 || new_left > 0 {
    marker = substr($0, 1, 1)
    if (marker == "+") {
      if (new_path != "") printf "R\t%s\t%d\t%d\n", new_path, new_line, hunk
      new_line++; new_left--
    } else if (marker == "-") {
      if (old_path != "") printf "L\t%s\t%d\t%d\n", old_path, old_line, hunk
      old_line++; old_left--
    } else if (marker == "\\") {
      # "\ No newline at end of file" belongs to neither side.
    } else {
      if (new_path != "") printf "R\t%s\t%d\t%d\n", new_path, new_line, hunk
      if (old_path != "") printf "L\t%s\t%d\t%d\n", old_path, old_line, hunk
      new_line++; new_left--; old_line++; old_left--
    }
    next
  }
  /^diff --git / { old_path = ""; new_path = ""; next }
  /^--- / {
    old_path = header_path($0)
    if (old_path == "/dev/null") old_path = ""
    sub(/^a\//, "", old_path)
    next
  }
  /^\+\+\+ / {
    new_path = header_path($0)
    if (new_path == "/dev/null") new_path = ""
    sub(/^b\//, "", new_path)
    printf "P\t%s\n", (new_path != "" ? new_path : old_path)
    next
  }
  /^@@ / {
    spans = $0
    sub(/^@@ -/, "", spans)
    old_spec = spans; sub(/ .*$/, "", old_spec)
    new_spec = spans; sub(/^[^ ]* \+/, "", new_spec); sub(/ .*$/, "", new_spec)
    parse_span(old_spec); old_line = span_start; old_left = span_length
    parse_span(new_spec); new_line = span_start; new_left = span_length
    hunk++
    next
  }
' "$diff_file")

# One `draft <i> (<path>:<line>): <problem>` line per problem, empty when all pass.
problems=$(jq -r --arg coverage "$coverage" '
  def positive_int: type == "number" and . == floor and . > 0;
  def side_letter: if . == "LEFT" then "L" else "R" end;
  ($coverage | split("\n") | map(select(length > 0) | split("\t"))) as $rows
  | ($rows | map(select(.[0] == "P") | {key: .[1], value: true}) | from_entries) as $paths
  | ($rows | map(select(.[0] != "P") | {key: (.[0] + "\t" + .[1] + "\t" + .[2]), value: .[3]}) | from_entries) as $hunks
  | to_entries[]
  | (.key + 1) as $number
  | .value as $draft
  | if ($draft | type) != "object" then "draft \($number): not an object"
    else
      ($draft.side // "RIGHT") as $side
      | ($draft.start_side // $side) as $start_side
      | ($draft.path | if type == "string" then . else "" end) as $path
      | "draft \($number) (\($path):\($draft.line)): " as $label
      | ($hunks[($side | side_letter) + "\t" + $path + "\t" + ($draft.line | tostring)]) as $line_hunk
      | ($hunks[($start_side | side_letter) + "\t" + $path + "\t" + ($draft.start_line | tostring)]) as $start_hunk
      | (
          (if $path == "" then "path is missing"
           elif $paths[$path] != true then "path \($path) is not in the diff"
           else empty end),
          (if ($side | IN("RIGHT", "LEFT")) then empty else "side must be RIGHT or LEFT, got \($side | tostring)" end),
          (if ($draft.line | positive_int | not) then "line must be a positive integer"
           elif $paths[$path] == true and ($side | IN("RIGHT", "LEFT")) and $line_hunk == null
           then "line \($draft.line) is not on the \($side) side of any hunk in \($path)"
           else empty end),
          (if $draft.start_line == null then empty
           elif ($draft.start_line | positive_int | not) then "start_line must be a positive integer"
           elif ($start_side | IN("RIGHT", "LEFT") | not) then "start_side must be RIGHT or LEFT, got \($start_side | tostring)"
           elif $paths[$path] == true and $start_hunk == null
           then "start_line \($draft.start_line) is not on the \($start_side) side of any hunk in \($path)"
           elif $start_side == $side and ($draft.line | positive_int) and $draft.start_line >= $draft.line
           then "start_line must come before line"
           else empty end),
          (if ($draft.body | type) != "string" or ($draft.body | test("\\S") | not) then "body is empty" else empty end)
        )
      | $label + .
    end
' "$drafts_file")

# kc-post-review's format rules (label line, no em dash, rule ids, emoji or praise opener, length).
format_problems=$(bash "$(dirname "$0")/check-draft-format.sh" "$drafts_file") || true
if [ -n "$format_problems" ]; then
  problems=$(printf '%s\n%s\n' "$problems" "$format_problems" | grep . | sort -t' ' -k2,2n -s)
fi
# A suggested name one letter from a name already in the repo (run from the repo; skipped elsewhere).
name_problems=$(bash "$(dirname "$0")/check-draft-names.sh" "$drafts_file" "$head_sha") || true
if [ -n "$name_problems" ]; then
  problems=$(printf '%s\n%s\n' "$problems" "$name_problems" | grep . | sort -t' ' -k2,2n -s)
fi

if [ -n "$problems" ]; then
  failing_count=$(printf '%s\n' "$problems" | sed 's/^draft \([0-9]*\).*/\1/' | sort -u | wc -l | tr -d ' ')
  echo "$script_name: $failing_count draft(s) failed validation; nothing written:" >&2
  printf '%s\n' "$problems" | sed 's/^/  /' >&2
  exit 1
fi

draft_count=$(jq 'length' "$drafts_file")
if [ "$draft_count" -eq 0 ]; then
  echo "$script_name: drafts file holds no drafts: $drafts_file" >&2
  exit 1
fi

[ -n "$out_dir" ] || { tmp_root=${TMPDIR:-/tmp}; out_dir="${tmp_root%/}/kc-review-$head_sha"; }
mkdir -p "$out_dir"
out_dir=$(cd "$out_dir" && pwd)

# Single-quotes a path when it holds anything a shell would split or expand.
quote_path() {
  case "$1" in
    *[!A-Za-z0-9_./:@+,-]*) printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")" ;;
    *) printf '%s' "$1" ;;
  esac
}

payload_files=()
draft_index=0
while [ "$draft_index" -lt "$draft_count" ]; do
  payload_file="$out_dir/comment-$((draft_index + 1)).json"
  jq --argjson index "$draft_index" --arg commit_id "$head_sha" '
    .[$index] as $draft
    | {commit_id: $commit_id, path: $draft.path, line: $draft.line, side: ($draft.side // "RIGHT"), body: $draft.body}
      + (if $draft.start_line == null then {}
         else {start_line: $draft.start_line, start_side: ($draft.start_side // $draft.side // "RIGHT")} end)
  ' "$drafts_file" > "$payload_file"
  location=$(jq -r '"\(.path):\(if .start_line then "\(.start_line)-" else "" end)\(.line)"' "$payload_file")
  echo "wrote $payload_file ($location)"
  payload_files+=("$payload_file")
  draft_index=$((draft_index + 1))
done

review_file="$out_dir/review.json"
review_body=""
[ -z "$body_file" ] || review_body=$(cat "$body_file")
jq -s --arg commit_id "$head_sha" --arg body "$review_body" '
  {commit_id: $commit_id, event: "COMMENT", comments: map(del(.commit_id))}
  + (if ($body | test("\\S")) then {body: $body} else {} end)
' "${payload_files[@]}" > "$review_file"
body_note=""
[ "$(jq 'has("body")' "$review_file")" = true ] && body_note=", with a body"
echo "wrote $review_file (one review, $draft_count comment(s)$body_note)"

echo
echo "Command for the user to approve (not run):"
echo "KC_REVIEW_POST_APPROVED=1 gh api repos/{owner}/{repo}/pulls/$pr_number/reviews -X POST --input $(quote_path "$review_file")"
echo
# A posted review leaves the work item it is for (a ticket, an issue) with the reviewer and
# its old status until someone moves it; the hand-back is the user's call, so it is asked.
echo "After it posts and the state is verified, ask the user whether the work item this pull request is for changes hands: back to the author when the review asks for changes, on to the next step when it approves. When the project's own rules say who moves it, do what they say and tell the user; otherwise ask, and never leave it unmentioned."
