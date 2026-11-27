#!/usr/bin/env bash
# Tests scripts/guard-github-post.sh: GitHub review writes without the
# approval token are denied; everything else passes silently. Each case runs
# twice, once with jq and once through the sed fallback. The cases at the end
# give a token and a transcript: a body the user was not shown before their
# latest message is denied (they need jq, which reads the transcript).
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
guard="$(dirname "$tests_dir")/scripts/guard-github-post.sh"

passes=0
failures=0
# No saved review folder from a real session may reach these cases.
TMPDIR=$(mktemp -d)
export TMPDIR

# Wraps a shell command (no double quotes or backslashes in it) in the
# PreToolUse stdin payload.
build_payload() {
  printf '{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"test"},"tool_use_id":"t"}' "$1"
}

run_guard() {
  local command=$1 mode=$2
  if [ "$mode" = sed ]; then
    build_payload "$command" | KC_GUARD_NO_JQ=1 bash "$guard"
  else
    build_payload "$command" | bash "$guard"
  fi
}

last_output=""
check() {
  local expectation=$1 label=$2 command=$3 mode output verdict
  for mode in jq sed; do
    if [ "$mode" = jq ] && ! command -v jq >/dev/null 2>&1; then
      continue
    fi
    output=$(run_guard "$command" "$mode")
    last_output=$output
    if [ -z "$output" ]; then
      verdict=allow
    elif printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then
      verdict=deny
    else
      verdict="unexpected output: $output"
    fi
    if [ "$verdict" = "$expectation" ]; then
      echo "ok   [$mode] $label"
      passes=$((passes + 1))
    else
      echo "FAIL [$mode] $label"
      echo "     expected: $expectation"
      echo "     actual:   $verdict"
      failures=$((failures + 1))
    fi
  done
}

check deny  "blocked: gh pr comment" \
  "gh pr comment 12 --body-file /tmp/note.md"
check deny  "blocked: review POST through gh api" \
  "gh api repos/acme/widgets/pulls/12/reviews -X POST --input /tmp/review-12.json"
check deny  "blocked: gh pr review" \
  "gh pr review 12 --comment -b 'Looks off'"
check deny  "blocked: gh issue comment" \
  "gh issue comment 7 --body 'Thanks'"
check deny  "blocked: inline comment with fields and no method" \
  "gh api repos/acme/widgets/pulls/12/comments -f body='x' -F line=4"
check deny  "blocked: edit a posted comment" \
  "gh api repos/acme/widgets/pulls/comments/991 --method=PATCH --input /tmp/edit.json"
check deny  "blocked: write chained after a read" \
  "gh pr view 12 && gh api repos/acme/widgets/issues/12/comments -X POST -f body='hi'"

check allow "allowed: token in the same command" \
  "KC_REVIEW_POST_APPROVED=1 gh pr comment 12 --body-file /tmp/note.md"
check allow "allowed: gh pr create" \
  "gh pr create --title 'Add widgets' --body-file /tmp/body.md"
check allow "allowed: gh pr merge" \
  "gh pr merge 12 --squash"
check allow "allowed: gh api GET on comments" \
  "gh api 'repos/acme/widgets/pulls/12/comments?per_page=100'"
check allow "allowed: explicit GET with query fields" \
  "gh api -X GET repos/acme/widgets/pulls/12/comments -f per_page=100"
check allow "allowed: gh pr view" \
  "gh pr view 12 --json headRefOid,title,files"
check allow "allowed: non-gh command" \
  "git diff main...HEAD > /tmp/review.diff"

# --- §PC3: token present, each posted body must have been shown before the user's latest message ---

if command -v jq >/dev/null 2>&1; then
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT

  user_line() { jq -nc --arg t "$1" '{type: "user", message: {role: "user", content: $t}}'; }
  assistant_line() { jq -nc --arg t "$1" '{type: "assistant", message: {role: "assistant", content: [{type: "text", text: $t}]}}'; }
  noise_lines() {
    jq -nc '{type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: "x", content: "ok"}]}}'
    jq -nc '{type: "user", message: {role: "user", content: "<system-reminder>note</system-reminder>"}}'
  }

  # before: the drafts, then the approval. after: the approval, then the drafts.
  { user_line "reply to the review"
    assistant_line $'Drafts:\n> Fixed in 1a2b3c4d5e6f.\n> Renamed the helper.'
    noise_lines
    user_line "yes, post them"; } > "$work/before.jsonl"
  { user_line "reply to the review"
    assistant_line "Ready to commit, push and reply?"
    user_line "yes"
    assistant_line "Fixed in 1a2b3c4d5e6f."; } > "$work/after.jsonl"
  { user_line "reply to the review"
    assistant_line 'Draft: Fixed in <full SHA>. Commit, push and reply?'
    user_line "yes"; } > "$work/placeholder.jsonl"
  printf '{"body":"Renamed the helper.","comments":[{"path":"a.rb","body":"Fixed in 1a2b3c4d5e6f."},{"path":"b.rb","body":"Never shown."}]}' > "$work/review.json"
  printf '{"body":"Renamed the helper.","comments":[{"path":"a.rb","body":"Fixed in 1a2b3c4d5e6f."}]}' > "$work/review-ok.json"
  # shellcheck source=../scripts/lib/file-sha256.sh
  . "$(dirname "$guard")/lib/file-sha256.sh"
  stamp_review_checked() { print_file_sha256 "$1" > "$1.checked"; }
  stamp_review_checked "$work/review.json"
  stamp_review_checked "$work/review-ok.json"
  # Built by the payload builder and then edited by hand, or never built by it.
  cp "$work/review-ok.json" "$work/review-edited.json"
  stamp_review_checked "$work/review-edited.json"
  printf '{"body":"Renamed the helper.","comments":[{"path":"a.rb","body":"Renamed the helper."}]}' > "$work/review-edited.json"
  cp "$work/review-ok.json" "$work/review-unbuilt.json"
  printf '{"body":"Renamed the helper."}' > "$work/review-body-only.json"

  # check_with_transcript <expectation> <label> <command> <transcript>
  check_with_transcript() {
    local expectation=$1 label=$2 command=$3 transcript=$4 mode output verdict payload
    for mode in jq sed; do
      payload=$(printf '{"session_id":"s","transcript_path":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"},"tool_use_id":"t"}' "$transcript" "$command")
      if [ "$mode" = sed ]; then
        output=$(printf '%s' "$payload" | KC_GUARD_NO_JQ=1 bash "$guard")
      else
        output=$(printf '%s' "$payload" | bash "$guard")
      fi
      if [ -z "$output" ]; then
        verdict=allow
      elif printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then
        verdict=deny
      else
        verdict="unexpected output: $output"
      fi
      if [ "$verdict" = "$expectation" ]; then
        echo "ok   [$mode] $label"
        passes=$((passes + 1))
      else
        echo "FAIL [$mode] $label"
        echo "     expected: $expectation"
        echo "     actual:   $verdict $output"
        failures=$((failures + 1))
      fi
    done
  }

  token=KC_REVIEW_POST_APPROVED=1
  check_with_transcript allow "shown: body quoted in a draft before the approval" \
    "$token gh api repos/acme/widgets/issues/comments/9 -X PATCH -f body='Fixed in 1a2b3c4d5e6f.'" "$work/before.jsonl"
  check_with_transcript allow "shown: body in a --body argument" \
    "$token gh pr comment 12 --body 'Renamed the helper.'" "$work/before.jsonl"
  check_with_transcript deny  "not shown: body shown only after the latest user message" \
    "$token gh api repos/acme/widgets/issues/12/comments -X POST -f body='Fixed in 1a2b3c4d5e6f.'" "$work/after.jsonl"
  check_with_transcript deny  "not shown: draft had a placeholder, body has the real SHA" \
    "$token gh api repos/acme/widgets/issues/12/comments -X POST -F body='Fixed in 1a2b3c4d5e6f.'" "$work/placeholder.jsonl"
  check_with_transcript allow "shown: blockquoted draft posted without the marker" \
    "$token gh pr comment 12 -b 'Fixed in 1a2b3c4d5e6f. Renamed the helper.'" "$work/before.jsonl"
  # shellcheck disable=SC2016 # literal $( in the command
  check_with_transcript allow "shown: heredoc body between the delimiters" \
    "$token gh pr comment 12 --body '\$(cat <<EOF\nRenamed the helper.\nEOF\n)'" "$work/before.jsonl"
  check_with_transcript deny  "not shown: --input review with one comment never shown" \
    "$token gh api repos/acme/widgets/pulls/12/reviews -X POST --input $work/review.json" "$work/before.jsonl"
  check_with_transcript allow "shown: --input review whose bodies were all shown" \
    "$token gh api repos/acme/widgets/pulls/12/reviews -X POST --input $work/review-ok.json" "$work/before.jsonl"
  check_with_transcript deny  "unchecked: a review payload the builder never stamped" \
    "$token gh api repos/acme/widgets/pulls/12/reviews -X POST --input $work/review-unbuilt.json" "$work/before.jsonl"
  check_with_transcript deny  "unchecked: a review payload edited after the builder stamped it" \
    "$token gh api repos/acme/widgets/pulls/12/reviews -X POST --input $work/review-edited.json" "$work/before.jsonl"
  check_with_transcript allow "unchecked: a body-only review needs no stamp" \
    "$token gh api repos/acme/widgets/pulls/12/reviews -X POST --input $work/review-body-only.json" "$work/before.jsonl"
  check_with_transcript deny  "unchecked: a review payload read from stdin" \
    "$token gh api repos/acme/widgets/pulls/12/reviews -X POST --input - < $work/review-ok.json" "$work/before.jsonl"
  check_with_transcript deny  "unchecked: a review payload file that does not exist before the command" \
    "$token gh api repos/acme/widgets/pulls/12/reviews -X POST --input $work/written-later.json" "$work/before.jsonl"
  check_with_transcript deny  "unchecked: inline comments sent as fields" \
    "$token gh api repos/acme/widgets/pulls/12/reviews -X POST -f event=COMMENT -f 'comments[][path]=a.rb' -f 'comments[][body]=Renamed the helper.'" "$work/before.jsonl"
  check_with_transcript allow "unchecked: a review with only a body field needs no stamp" \
    "$token gh api repos/acme/widgets/pulls/12/reviews -X POST -f event=COMMENT -f body='Renamed the helper.'" "$work/before.jsonl"
  check_with_transcript deny  "unchecked: a new inline comment through the single-comment endpoint" \
    "$token gh api repos/acme/widgets/pulls/12/comments -X POST -f body='Fixed in 1a2b3c4d5e6f.' -F line=4" "$work/before.jsonl"
  check_with_transcript allow "unchecked: a reply in a thread is not an inline comment" \
    "$token gh api repos/acme/widgets/pulls/12/comments/55/replies -X POST -f body='Fixed in 1a2b3c4d5e6f.'" "$work/before.jsonl"
  check_with_transcript deny  "not shown: second write in a chain" \
    "$token gh pr comment 12 -b 'Fixed in 1a2b3c4d5e6f.' && $token gh pr comment 12 -b 'Never shown.'" "$work/before.jsonl"
  check_with_transcript allow "unreadable: body from a file is not checked" \
    "$token gh pr comment 12 --body-file /tmp/note.md" "$work/after.jsonl"
  check_with_transcript allow "unreadable: body from a shell substitution is not checked" \
    "$token gh pr comment 12 --body '\$(cat /tmp/note.md)'" "$work/after.jsonl"
  check_with_transcript allow "unreadable: no transcript file means no check" \
    "$token gh pr comment 12 -b 'Never shown.'" "$work/missing.jsonl"
  check_with_transcript allow "untouched: non-GitHub command carrying the token" \
    "$token git commit -m 'Never shown.'" "$work/after.jsonl"
  check_with_transcript allow "untouched: gh pr view with a body-like flag" \
    "$token gh pr view 12 -b 'Never shown.'" "$work/after.jsonl"
  check_with_transcript deny  "no token: existing deny unchanged" \
    "gh pr comment 12 -b 'Fixed in 1a2b3c4d5e6f.'" "$work/before.jsonl"
  check_with_transcript allow "non-GitHub command without token" \
    "git fetch origin" "$work/after.jsonl"
fi

# --- walk receipt: a review with walk-items cannot be posted or approved without a full receipt ---
# gather-review.sh's folders (kc-review-<sha>) are found under TMPDIR for this repo, whose origin
# the guard reads from the directory it runs in; select-gates.sh names the items.
base_tmp=$TMPDIR
walk_tmp=$(mktemp -d)
walk_repo=$(mktemp -d)
git init -q "$walk_repo"
git -C "$walk_repo" remote add origin https://github.com/acme/widgets.git
export TMPDIR=$walk_tmp
cd "$walk_repo"
# A stub gh that answers nothing by default (the head check then has nothing to compare), and
# gives the pull request's head, files and base branch from KC_STUB_HEAD, KC_STUB_FILES and
# KC_STUB_BASE when they are set.
stub_bin=$(mktemp -d)
cat > "$stub_bin/gh" <<'STUB'
#!/usr/bin/env bash
[ -n "${KC_STUB_HEAD:-}" ] || exit 1
case "$*" in
  *headRefOid*) printf '%s\n' "$KC_STUB_HEAD" ;;
  *files*) printf '%s\n' "$KC_STUB_FILES" ;;
  *baseRefName*) printf '%s\n' "${KC_STUB_BASE:-}" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$stub_bin/gh"
export PATH="$stub_bin:$PATH"
walk_token=KC_REVIEW_POST_APPROVED=1
review_folder=$walk_tmp/kc-review-abc123
# Saves a review the way gather-review.sh does: write_review <changed path> [<folder> <pr> <repo>].
write_review() {
  local folder=$walk_tmp/${2:-kc-review-abc123}
  mkdir -p "$folder"
  printf -- '--- a/%s\n+++ b/%s\n@@ -0,0 +1 @@\n+x\n' "$1" "$1" > "$folder/review.diff"
  printf '%s\n' "$1" > "$folder/changed-files.txt"
  printf 'HEAD_SHA=abc123\nPR=%s\nURL=https://github.com/%s/pull/%s\n' "${3:-12}" "${4:-acme/widgets}" "${3:-12}" > "$folder/meta.env"
}
# Makes a folder's meta.env <seconds> old, so which review is newest does not depend on timing.
age_review() { perl -e 'utime(time - $ARGV[1], time - $ARGV[1], $ARGV[0] . "/meta.env")' "$walk_tmp/$1" "$2"; }
expect_last_reason() {
  case "$last_output" in
    *"$2"*) echo "ok   $1"; passes=$((passes + 1)) ;;
    *) echo "FAIL $1"; echo "     missing: $2"; echo "     in:      $last_output"; failures=$((failures + 1)) ;;
  esac
}
no_receipt_reason="no receipt line in $review_folder/walk-receipt.tsv"

write_review app/models/order.rb
rm -f "$review_folder/walk-receipt.tsv"
write_forms=(
  "gh pr review 12 --approve"
  "gh pr review --approve 12"
  "gh pr review -R acme/widgets 12 --approve"
  "gh pr review --repo acme/widgets --approve 12"
  "gh pr comment --body hi 12"
  "gh pr comment -b 'see 99 first' 12"
  "gh pr comment https://github.com/acme/widgets/pull/12 --body hi"
  "gh pr review --approve"
  "gh pr comment --body hi"
  "gh issue comment 12 --body hi"
  "gh api repos/acme/widgets/pulls/12/reviews -X POST -f event=APPROVE"
  "gh api repos/{owner}/{repo}/pulls/12/reviews -X POST -f event=APPROVE"
)
for form in "${write_forms[@]}"; do
  check deny "walk: no receipt denies: $form" "$walk_token $form"
  expect_last_reason "walk: the denial for '$form' names the item with no receipt line" "walk-item app/models/order.rb: $no_receipt_reason"
done
printf 'app/models/order.rb\tcreated an order with a free item\tno evidence\tstates: empty cart; two items\n' > "$review_folder/walk-receipt.tsv"
check deny  "walk: a receipt line with bad evidence is denied" "$walk_token gh pr review 12 --approve"
expect_last_reason "walk: the denial for bad evidence says what the evidence must be" "is a unit surface: give a run transcript"
printf 'env\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order with a free item\tPOST /orders 201\tstates: empty cart; two items\n' > "$review_folder/walk-receipt.tsv"
for form in "${write_forms[@]}"; do
  check allow "walk: a full receipt allows: $form" "$walk_token $form"
done
write_review docs/notes.md
rm -f "$review_folder/walk-receipt.tsv"
check allow "walk: WALK=not-required needs no receipt" "$walk_token gh pr review 12 --approve"
write_review app/models/order.rb
# §V11: with the review's uses.txt, a consumer the receipt does not walk denies the post; an entry allows it.
printf 'name Order (definition, app/models/order.rb): 1 uses\n  app/services/checkout.rb:12: Order.create(params)\ntests: 0\nsummary: 1 names, 1 uses, 0 test files\n' > "$review_folder/uses.txt"
printf 'env\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order with a free item\tPOST /orders 201\tstates: empty cart; two items\n' > "$review_folder/walk-receipt.tsv"
check deny  "walk: a consumer with no entry denies the approval" "$walk_token gh pr review 12 --approve"
expect_last_reason "walk: the denial names the consumer" "consumer app/services/checkout.rb"
printf 'env\tbin/review-env up\tGET /health 200\napp/models/order.rb\tcreated an order with a free item\tPOST /orders 201\tstates: empty cart; two items\tconsumers: app/services/checkout.rb: omitted the discount; before on; after off\n' > "$review_folder/walk-receipt.tsv"
check allow "walk: an entry for the consumer allows the approval" "$walk_token gh pr review 12 --approve"
rm -f "$review_folder/uses.txt" "$review_folder/walk-receipt.tsv"
check deny  "walk: the denial returns when a source change is back" "$walk_token gh pr review 12 --approve"
check deny  "walk: no token is still the old deny" "gh pr review 12 --approve"
expect_last_reason "walk: no token gives the approval-token deny, not the receipt one" "without the approval token"
check allow "walk: a review of another pull request needs no receipt" "$walk_token gh pr review 99 --approve"

# KC_REVIEW_DIR names the review whatever pull request the command names.
export KC_REVIEW_DIR=$review_folder
check deny  "walk: KC_REVIEW_DIR is checked for a command naming another pull request" "$walk_token gh pr review 99 --approve"
export KC_REVIEW_DIR=$walk_tmp/kc-review-missing
check allow "walk: a KC_REVIEW_DIR with no review in it means no check" "$walk_token gh pr review 12 --approve"
unset KC_REVIEW_DIR

# Two saved reviews of one pull request (a re-review of a newer head): the newest decides.
write_review app/models/order.rb kc-review-old
write_review docs/notes.md kc-review-new
rm -rf "$review_folder"
age_review kc-review-old 7200
check allow "walk: the newer review (docs only) decides over an older one with a source change" "$walk_token gh pr review 12 --approve"
write_review docs/notes.md kc-review-old
write_review app/models/order.rb kc-review-new
age_review kc-review-old 7200
check deny  "walk: the newer review (source change) decides over an older docs-only one" "$walk_token gh pr review 12 --approve"
rm -rf "$walk_tmp"/kc-review-*

# A newer folder gather-review.sh has not finished (no diff yet) is not the review.
write_review app/models/order.rb kc-review-complete
age_review kc-review-complete 7200
mkdir "$walk_tmp/kc-review-partial"
printf 'PR=12\nURL=https://github.com/acme/widgets/pull/12\n' > "$walk_tmp/kc-review-partial/meta.env"
check deny  "walk: a newer folder with no diff is skipped for the complete review" "$walk_token gh pr review 12 --approve"
rm -rf "$walk_tmp"/kc-review-*

# Another repository's review of the same pull request number is not this review.
write_review app/models/order.rb kc-review-other 12 acme/other
check allow "walk: another repo's review of the same pull request number is ignored" "$walk_token gh pr review 12 --approve"
write_review docs/notes.md kc-review-own
age_review kc-review-own 7200
check allow "walk: a newer unwalked review of another repo does not decide over this repo's" "$walk_token gh pr review 12 --approve"
age_review kc-review-other 14400
write_review app/models/order.rb kc-review-other 12 acme/other
check allow "walk: a newer unwalked review of another repo is ignored, without a number too" "$walk_token gh pr review --approve"
check deny  "walk: -R names the other repo, whose review is the one checked" "$walk_token gh pr review -R acme/other 12 --approve"
rm -rf "$walk_tmp"/kc-review-*

# select-gates.sh cannot read the review: the guard never blocks what it can't check.
write_review app/models/order.rb
if [ "$(id -u)" -ne 0 ]; then
  chmod 000 "$review_folder/review.diff"
  check allow "walk: a review whose diff cannot be read means no check" "$walk_token gh pr review 12 --approve"
  chmod 644 "$review_folder/review.diff"
fi
rm -rf "$review_folder"
check allow "walk: no saved review folder means no check" "$walk_token gh pr review 12 --approve"
# --- an approval is of the head the review walked ------------------------------------------------
# A head that moved only by commits touching none of the pull request's files (the default branch
# merged in) still stands; a head that moved in a file of the pull request does not.
git -C "$walk_repo" config user.email test@example.com
git -C "$walk_repo" config user.name Test
mkdir -p "$walk_repo/app/models"
printf 'one\n' > "$walk_repo/app/models/order.rb"
git -C "$walk_repo" add -A && git -C "$walk_repo" commit -q -m walked
walked_sha=$(git -C "$walk_repo" rev-parse HEAD)
printf 'unrelated\n' > "$walk_repo/README.md"
git -C "$walk_repo" add -A && git -C "$walk_repo" commit -q -m "merge of the default branch"
merged_sha=$(git -C "$walk_repo" rev-parse HEAD)
printf 'two\n' > "$walk_repo/app/models/order.rb"
git -C "$walk_repo" add -A && git -C "$walk_repo" commit -q -m "more work on the order"
moved_sha=$(git -C "$walk_repo" rev-parse HEAD)
rm -rf "$walk_tmp"/kc-review-*
write_review docs/notes.md
printf 'HEAD_SHA=%s\nPR=12\nURL=https://github.com/acme/widgets/pull/12\n' "$walked_sha" > "$review_folder/meta.env"
export KC_STUB_FILES=$'app/models/order.rb\ndocs/notes.md'
approve_forms=(
  "gh pr review 12 --approve"
  "gh pr review --approve 12"
  "gh api repos/acme/widgets/pulls/12/reviews -X POST -f event=APPROVE"
)

export KC_STUB_HEAD=$walked_sha
for form in "${approve_forms[@]}"; do
  check allow "head: the head the review walked allows: $form" "$walk_token $form"
done

export KC_STUB_HEAD=$moved_sha
for form in "${approve_forms[@]}"; do
  check deny "head: a new commit in a file of the pull request denies: $form" "$walk_token $form"
  expect_last_reason "head: the denial for '$form' names the file" "app/models/order.rb"
  expect_last_reason "head: the denial for '$form' says to review the new commits first" "Review the new commits first"
done
check allow "head: a comment is not an approval, whatever the head" "$walk_token gh pr comment 12 --body hi"
check allow "head: a review that only comments is not an approval" "$walk_token gh pr review 12 --comment --body hi"

export KC_STUB_HEAD=$merged_sha

note_output=$(build_payload "$walk_token gh pr review 12 --approve" | bash "$guard")
last_output=$note_output
expect_last_reason "head: the merge-only approval prints one line saying so" "touch none of its files"
case "$note_output" in
  *permissionDecision*) echo "FAIL head: the merge-only approval is not denied"; failures=$((failures + 1)) ;;
  *) echo "ok   head: the merge-only approval is not denied"; passes=$((passes + 1)) ;;
esac

export KC_STUB_HEAD=$moved_sha KC_STUB_FILES=
check allow "head: a pull request file list gh gives empty means no check" "$walk_token gh pr review 12 --approve"
export KC_STUB_FILES=$'app/models/order.rb\ndocs/notes.md'
unset KC_STUB_HEAD
check allow "head: a head gh can't give means no check" "$walk_token gh pr review 12 --approve"
export KC_STUB_HEAD=0000000000000000000000000000000000000000
check allow "head: a head this clone doesn't have means no check" "$walk_token gh pr review 12 --approve"
unset KC_STUB_HEAD KC_STUB_FILES

# --- a rebase that left the reviewed commits unchanged still stands --------------------------------
# A pull request of two commits, reviewed at one head, then rebased onto a base that moved in a file
# the pull request also changes: the files differ, but git range-diff pairs every commit with "=".
rb_repo=$(mktemp -d)
git init -q -b main "$rb_repo"
git -C "$rb_repo" remote add origin https://github.com/acme/widgets.git
git -C "$rb_repo" config user.email test@example.com
git -C "$rb_repo" config user.name Test
cd "$rb_repo"
mkdir -p app/models docs
printf '%s\n' a b c d e f g h i j > app/models/order.rb
git add -A && git commit -q -m "initial shop"
git checkout -q -b feature
sed -i.bak 's/^a$/A/' app/models/order.rb && rm app/models/order.rb.bak
git commit -q -am "add order total"
printf 'notes\n' > docs/notes.md
git add -A && git commit -q -m "document orders"
rb_walked=$(git rev-parse HEAD)
git checkout -q main
sed -i.bak 's/^j$/J/' app/models/order.rb && rm app/models/order.rb.bak
git commit -q -am "base moves in the order file"
git update-ref refs/remotes/origin/main main
git checkout -q -b rebased "$rb_walked"
git rebase -q main
rb_rebased=$(git rev-parse HEAD)
git checkout -q -b rebased-edit main
git cherry-pick "$rb_walked~1" >/dev/null
printf 'extra\n' >> app/models/order.rb
git commit -q -a --amend --no-edit
git cherry-pick "$rb_walked" >/dev/null
rb_edited=$(git rev-parse HEAD)
git checkout -q -b rebased-added "$rb_rebased"
printf 'more\n' >> docs/notes.md
git commit -q -am "add a late commit"
rb_added=$(git rev-parse HEAD)
git checkout -q -b rebased-dropped main
git cherry-pick "$rb_walked~1" >/dev/null
rb_dropped=$(git rev-parse HEAD)

rm -rf "$walk_tmp"/kc-review-*
write_review docs/notes.md
printf 'HEAD_SHA=%s\nPR=12\nURL=https://github.com/acme/widgets/pull/12\n' "$rb_walked" > "$review_folder/meta.env"
export KC_STUB_FILES=$'app/models/order.rb\ndocs/notes.md' KC_STUB_BASE=main

export KC_STUB_HEAD=$rb_rebased
note_output=$(build_payload "$walk_token gh pr review 12 --approve" | bash "$guard")
last_output=$note_output
expect_last_reason "head: a rebase with the reviewed commits unchanged prints one line saying so" "range-diff shows every reviewed commit unchanged"
case "$note_output" in
  *permissionDecision*) echo "FAIL head: the unchanged-commits rebase is not denied"; failures=$((failures + 1)) ;;
  *) echo "ok   head: the unchanged-commits rebase is not denied"; passes=$((passes + 1)) ;;
esac

export KC_STUB_HEAD=$rb_edited
check deny "head: a rebase that also edits a reviewed commit denies" "$walk_token gh pr review 12 --approve"
expect_last_reason "head: the denial for an edited commit names it" "add order total"
export KC_STUB_HEAD=$rb_added
check deny "head: a commit added after the rebase denies" "$walk_token gh pr review 12 --approve"
expect_last_reason "head: the denial for an added commit names it" "add a late commit"
export KC_STUB_HEAD=$rb_dropped
check deny "head: a commit dropped by the rebase denies" "$walk_token gh pr review 12 --approve"
expect_last_reason "head: the denial for a dropped commit names it" "document orders"

export KC_STUB_HEAD=$rb_rebased KC_STUB_BASE=release
check deny "head: a base branch this clone doesn't have keeps the denial" "$walk_token gh pr review 12 --approve"
expect_last_reason "head: the unresolved-base denial says to fetch" "fetch the pull request's base branch"
export KC_STUB_BASE=
check deny "head: a base branch gh can't give keeps the denial" "$walk_token gh pr review 12 --approve"
# Both ranges empty (the reviewed head is already in the base): nothing to compare, so the denial stays.
printf '%s\n' "HEAD_SHA=$(git rev-parse main~1)" 'PR=12' 'URL=https://github.com/acme/widgets/pull/12' > "$review_folder/meta.env"
KC_STUB_HEAD=$(git rev-parse main)
export KC_STUB_HEAD KC_STUB_BASE=main
check deny "head: no reviewed commits to compare keeps the denial" "$walk_token gh pr review 12 --approve"
expect_last_reason "head: the no-commits denial says to fetch" "fetch the pull request's base branch"
unset KC_STUB_HEAD KC_STUB_FILES KC_STUB_BASE

# --- review report: a posted verdict report keeps §G6 and §G7, and the walk is never offered ---
write_review docs/notes.md
rm -f "$review_folder/walk-receipt.tsv"
# shellcheck disable=SC2016 # backticks in the fixture text are literal
works_body='**Does it work / what can it break**\n- Measured: checkout query before 420 ms -> after 38 ms.\n- Uses: 4 traced, 3 run, 1 read.\n'
# shellcheck disable=SC2016 # backticks in the fixture text are literal
ok_report='### Review: Add free shipping\n'"$works_body"'\n`abc1234` `cart.ts`: follows existing conventions and naming. No changes.'
# shellcheck disable=SC2016 # backticks in the fixture text are literal
bare_report='### Review: Add free shipping\n**Verdict:** FAILED (1 gate failing)\n\n**Naming:**\n- 🟡 `cart.ts:L4`: `tmp` is opaque. Rename `total`.'
check allow "report: a verdict report that leads with the does-it-work section posts" "$walk_token gh pr comment 12 -b '$ok_report'"
check deny "report: a verdict report with no does-it-work section is denied" "$walk_token gh pr comment 12 -b '$bare_report'"
expect_last_reason "report: the denial says what to add" "Does it work / what can it break"
check deny "report: a verdict report in a review is denied too" "$walk_token gh pr review 12 --comment -b '$bare_report'"
check allow "report: a comment that gives no verdict is not checked" "$walk_token gh pr comment 12 -b 'Thanks, fixed in the next commit.'"
check deny "report: asking whether to QA the change in the app is denied" "$walk_token gh pr comment 12 -b 'Should I QA this change in the running app first?'"
expect_last_reason "report: the denial says the walk is never a choice" "never offered as a choice"
check allow "report: saying the walk will happen, with no question, posts" "$walk_token gh pr comment 12 -b 'I will walk it in the running app now.'"
check allow "report: an unrelated question posts" "$walk_token gh pr comment 12 -b 'Which gate do you want first?'"
check deny "report: no token still denies a verdict report first" "gh pr comment 12 -b '$ok_report'"
# Findings the gates confirmed stay in the report: with a verdicts/ folder in the review.
mkdir -p "$review_folder/verdicts"
# shellcheck disable=SC2016 # backticks in the fixture text are literal
printf 'STATUS: FAIL\nFINDINGS:\n- 🟠 src/orders/refund.ts:42@abc1234: skips archived orders.\n' > "$review_folder/verdicts/naming.txt"
check deny "report: a verdict report that leaves out a confirmed finding is denied" "$walk_token gh pr comment 12 -b '$ok_report'"
expect_last_reason "report: the denial names the missing finding" "refund.ts:42"
check allow "report: naming the finding posts" "$walk_token gh pr comment 12 -b '$ok_report\n- 🟠 refund.ts:42: skips archived orders. (non-blocking)'"
check allow "report: a Dropped: line with a reason posts" "$walk_token gh pr comment 12 -b '$ok_report\nDropped: refund.ts:42 (the author already fixed it)'"
check allow "report: a comment with no verdict is not held to the findings" "$walk_token gh pr comment 12 -b 'Thanks.'"
rm -rf "$review_folder/verdicts"
check allow "report: no verdicts folder, nothing to check" "$walk_token gh pr comment 12 -b '$ok_report'"

# §PC13: a reply that ends on a softener or carries an emoji is denied, whatever a repo's example shows.
check deny "tone: a softener close is denied" "$walk_token gh api -X POST repos/acme/shop/pulls/12/comments/9/replies -f body='I kept the whole sentence as one key, if that is okay.'"
expect_last_reason "tone: the denial names the softener" "stock softener"
check deny "tone: an emoji is denied" "$walk_token gh pr comment 12 -b 'Fixed in abc1234 🙂'"
expect_last_reason "tone: the denial names the emoji" "an emoji"
check deny "tone: hope this helps is denied" "$walk_token gh pr comment 12 -b 'Renamed it. Hope this helps.'"
check allow "tone: a plain reply posts" "$walk_token gh api -X POST repos/acme/shop/pulls/12/comments/9/replies -f body='Done in abc1234.'"
check allow "tone: okay in another sense posts" "$walk_token gh pr comment 12 -b 'The okay button now closes the dialog.'"

cd "$tests_dir"
rm -rf "$rb_repo"
TMPDIR=$base_tmp
rm -rf "$walk_tmp" "$walk_repo" "$stub_bin"

echo "$passes passed, $failures failed"
[ "$failures" -eq 0 ]
