#!/usr/bin/env bash
# Tests scripts/build-comment-payloads.sh with fixtures/build-comment-payloads/:
# valid drafts (single line, range, old side, new file, context line) become
# payloads plus approval commands; a line outside every hunk, a path not in the
# diff and an empty body each fail alone, and a mixed file lists every failing
# draft and writes nothing. No gh is on PATH: the script must never call it.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
builder="$(dirname "$tests_dir")/scripts/build-comment-payloads.sh"
fixtures="$tests_dir/fixtures/build-comment-payloads"
head_sha=1111111111111111111111111111111111111111
require_jq

# A gh that fails the test if the builder ever calls it.
trap_bin="$work_dir/trap-bin"
mkdir -p "$trap_bin"
printf '#!/usr/bin/env bash\necho called >> "%s/gh-called"\nexit 1\n' "$work_dir" > "$trap_bin/gh"
chmod +x "$trap_bin/gh"
export PATH="$trap_bin:$PATH"

# --- valid drafts ---------------------------------------------------------------
out="$work_dir/out"
bash "$builder" "$fixtures/valid.json" "$fixtures/review.diff" "$head_sha" --pr 12 --out-dir "$out" > "$work_dir/valid.txt"
sed "s|{out}|$out|g" "$fixtures/expected-valid.txt" > "$work_dir/expected-valid.txt"
expect_file "valid: one payload per draft and one approval command each" "$work_dir/expected-valid.txt" "$work_dir/valid.txt"
expect_file "valid: a range payload carries start_line and start_side" "$fixtures/expected-comment-2.json" "$out/comment-2.json"
expect_file "valid: an old-side payload keeps side LEFT" "$fixtures/expected-comment-3.json" "$out/comment-3.json"
expect_eq "valid: a single-line payload has exactly the five fields" "body,commit_id,line,path,side" \
  "$(jq -r 'keys | join(",")' "$out/comment-1.json")"

mkdir -p "$work_dir/tmp"
TMPDIR="$work_dir/tmp" bash "$builder" "$fixtures/valid.json" "$fixtures/review.diff" "$head_sha" --pr 12 > /dev/null
if [ -f "$work_dir/tmp/kc-review-$head_sha/comment-5.json" ]; then
  record "valid: default out dir is \$TMPDIR/kc-review-<sha>" ok
else
  record "valid: default out dir is \$TMPDIR/kc-review-<sha>" fail "no comment-5.json under $work_dir/tmp/kc-review-$head_sha"
fi

# --- invalid drafts -------------------------------------------------------------
# Runs the builder on <drafts> and records its status and stderr.
run_invalid() {
  local drafts=$1 out_dir=$2
  set +e
  bash "$builder" "$drafts" "$fixtures/review.diff" "$head_sha" --pr 12 --out-dir "$out_dir" > "$work_dir/stdout.txt" 2> "$work_dir/stderr.txt"
  invalid_status=$?
  set -e
}

# Checks draft <index> of invalid.json on its own: exit 1, its message, no files.
check_single_invalid() {
  local label=$1 draft_index=$2 expected_message=$3 single_out="$work_dir/out-single-$2"
  jq ".[$draft_index:$((draft_index + 1))]" "$fixtures/invalid.json" > "$work_dir/single.json"
  run_invalid "$work_dir/single.json" "$single_out"
  expect_eq "$label: exits 1" 1 "$invalid_status"
  expect_contains "$label: names the problem" "$expected_message" "$(cat "$work_dir/stderr.txt")"
  if [ -e "$single_out" ]; then
    record "$label: writes nothing" fail "$single_out exists"
  else
    record "$label: writes nothing" ok
  fi
}
check_single_invalid "line outside every hunk" 1 \
  "draft 1 (src/widgets/list.ts:10): line 10 is not on the RIGHT side of any hunk in src/widgets/list.ts"
check_single_invalid "path not in the diff" 2 \
  "draft 1 (src/other.ts:1): path src/other.ts is not in the diff"
check_single_invalid "empty body" 3 \
  "draft 1 (src/widgets/list.ts:3): body is empty"

mixed_out="$work_dir/out-mixed"
run_invalid "$fixtures/invalid.json" "$mixed_out"
expect_eq "mixed: exits 1" 1 "$invalid_status"
expect_file "mixed: every failing draft listed, the valid one not" "$fixtures/expected-invalid.txt" "$work_dir/stderr.txt"
expect_eq "mixed: nothing on stdout" "" "$(cat "$work_dir/stdout.txt")"
if [ -e "$mixed_out" ]; then
  record "mixed: writes no payload, not even for the valid draft" fail "$mixed_out exists"
else
  record "mixed: writes no payload, not even for the valid draft" ok
fi

# --- usage errors ---------------------------------------------------------------
check_status() {
  local label=$1 expected=$2 status
  shift 2
  set +e
  bash "$builder" "$@" > /dev/null 2>&1
  status=$?
  set -e
  expect_eq "$label" "$expected" "$status"
}
check_status "usage: no arguments exits 2" 2
check_status "usage: missing --pr exits 2" 2 "$fixtures/valid.json" "$fixtures/review.diff" "$head_sha"
check_status "usage: a short SHA exits 2" 2 "$fixtures/valid.json" "$fixtures/review.diff" 1111111 --pr 12
check_status "usage: a drafts file that is not an array exits 2" 2 "$fixtures/expected-comment-2.json" "$fixtures/review.diff" "$head_sha" --pr 12

if [ -e "$work_dir/gh-called" ]; then
  record "gh was never called" fail "the builder invoked gh"
else
  record "gh was never called" ok
fi

finish
