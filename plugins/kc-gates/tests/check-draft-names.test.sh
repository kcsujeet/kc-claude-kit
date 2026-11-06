#!/usr/bin/env bash
# Tests scripts/check-draft-names.sh against a throwaway repo: a suggested name one letter from an
# existing one, the names it lets through, the "names" reason, and drafts checked away from a repo.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
names_script="$(dirname "$tests_dir")/scripts/check-draft-names.sh"
require_jq

repo="$work_dir/shop"
mkdir -p "$repo/src" "$repo/locales" "$repo/docs"
cat > "$repo/src/receipt.ts" <<'EOF'
export const customerEmail = (order) => order.customer.email
export const giftMessage = (order) => order.gift?.message
export const customerEmails = (orders) => orders.map(customerEmail)
export const tax = 0
export const shippingAddress = (order) => order.shipping.address
EOF
cat > "$repo/locales/en.json" <<'EOF'
{ "receipt": { "customerEmail": "Customer · {email}", "giftMessage": "Gift message" } }
EOF
echo "Receipts list each order's items." > "$repo/docs/receipts.md"
git -C "$repo" init -q
git -C "$repo" add -A
git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q -m base
head_sha=$(git -C "$repo" rev-parse HEAD)

# Writes one draft with <body> (and an optional "names" reason) to <file>.
write_draft() {
  local file=$1 body=$2 names=${3:-}
  if [ -n "$names" ]; then
    jq -n --arg body "$body" --arg names "$names" '[{path: "src/receipt.ts", line: 1, body: $body, names: $names}]' > "$file"
  else
    jq -n --arg body "$body" '[{path: "src/receipt.ts", line: 1, body: $body}]' > "$file"
  fi
}

# Runs the check from <dir> on <file>; prints its output, or "clean" when it passes.
run_names_check() {
  local dir=$1 file=$2 output status=0
  output=$(cd "$dir" && bash "$names_script" "$file" "$head_sha") || status=$?
  if [ "$status" -eq 0 ]; then echo clean; else printf '%s\n' "$output"; fi
}

# --- a suggestion that reads as a typo ---------------------------------------------------------
write_draft "$work_dir/plural.json" $'**suggestion**:\nThe template label needs its own key. Maybe `receipt.customersEmail`?'
expect_eq "a key one letter from an existing key is flagged" \
  "draft 1 (src/receipt.ts:1): suggests \`customersEmail\`, one letter from \`customerEmail\` already in the repo; pick a name that differs more, or say why in \"names\"" \
  "$(run_names_check "$repo" "$work_dir/plural.json")"

write_draft "$work_dir/repeated.json" $'**suggestion**:\nMaybe `customersEmail`, so `customersEmail` reads like the template?'
expect_eq "a name the draft repeats is reported once" 1 "$(run_names_check "$repo" "$work_dir/repeated.json" | grep -c customersEmail)"

write_draft "$work_dir/swapped.json" $'**suggestion**:\n`giftMassage` would match the other getters.'
expect_eq "it prints nothing on stderr, warnings included" "" "$(cd "$repo" && bash "$names_script" "$work_dir/plural.json" "$head_sha" 2>&1 >/dev/null || true)"

expect_contains "a changed letter is flagged too" "suggests \`giftMassage\`, one letter from \`giftMessage\`" \
  "$(run_names_check "$repo" "$work_dir/swapped.json")"

# --- names it lets through ---------------------------------------------------------------------
write_draft "$work_dir/existing.json" $'**question**:\nIs `customerEmail` meant to skip `giftMessage` here, when `customerEmails` reads both?'
expect_eq "names already in the repo are references, not suggestions" clean "$(run_names_check "$repo" "$work_dir/existing.json")"

write_draft "$work_dir/short.json" $'**nitpick**:\nMaybe `tag` here?'
expect_eq "a name under four letters is too short to tell from a typo" clean "$(run_names_check "$repo" "$work_dir/short.json")"

write_draft "$work_dir/distinct.json" $'**suggestion**:\nMaybe `customerWithEmail` for the label that shows the address?'
expect_eq "a new name that differs by more than a letter is clean" clean "$(run_names_check "$repo" "$work_dir/distinct.json")"

write_draft "$work_dir/two-letters.json" $'**suggestion**:\nMaybe `giftMassaga`, to match the template?'
expect_eq "two changed letters are a different name, not a typo" clean "$(run_names_check "$repo" "$work_dir/two-letters.json")"

write_draft "$work_dir/fenced.json" $'**suggestion**:\nThis could read the shared getter:\n```ts\n// was `customersEmail` before the rename\nconst email = customerEmail(order)\n```'
expect_eq "names inside a code block are left to the reader" clean "$(run_names_check "$repo" "$work_dir/fenced.json")"

write_draft "$work_dir/reason.json" $'**chore**:\nThis should be `customerEmail`, not `customersEmail`.' "a rename fixing the typo"
expect_eq "a draft that says why in \"names\" is skipped" clean "$(run_names_check "$repo" "$work_dir/reason.json")"

expect_contains "run from a folder below the top, it still reads the whole repo" "one letter from \`customerEmail\`" \
  "$(run_names_check "$repo/docs" "$work_dir/plural.json")"

mkdir -p "$work_dir/elsewhere"
expect_eq "away from the repo there is nothing to compare, so it passes" clean \
  "$(run_names_check "$work_dir/elsewhere" "$work_dir/plural.json")"

status=0
(cd "$repo" && bash "$names_script" "$work_dir/plural.json") >/dev/null 2>&1 || status=$?
expect_eq "a missing head SHA is a usage error" 2 "$status"

status=0
unreadable_error=$(cd "$repo" && bash "$names_script" "$work_dir/no-such.json" "$head_sha" 2>&1 >/dev/null) || status=$?
expect_eq "an unreadable drafts file exits 2" 2 "$status"
expect_contains "and says it can't read it" "cannot read $work_dir/no-such.json" "$unreadable_error"
status=0
(cd "$work_dir/elsewhere" && bash "$names_script" "$work_dir/no-such.json" "$head_sha") >/dev/null 2>&1 || status=$?
expect_eq "it exits 2 even where the head SHA is no commit" 2 "$status"

printf '{"body": "not a list"}' > "$work_dir/object.json"
status=0
(cd "$repo" && bash "$names_script" "$work_dir/object.json" "$head_sha") >/dev/null 2>&1 || status=$?
expect_eq "a drafts file that isn't a JSON array exits 2" 2 "$status"

finish
