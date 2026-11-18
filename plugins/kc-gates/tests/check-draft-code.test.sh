#!/usr/bin/env bash
# Tests scripts/check-draft-code.sh: code a draft shows that appears nowhere in the repo is
# reported, unless the draft says why it is new; code that exists, or no code, passes.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
check="$(dirname "$tests_dir")/scripts/check-draft-code.sh"
require_jq

repo=$work_dir/repo
git init -q "$repo"
mkdir -p "$repo/src"
printf 'def total(cart)\n  cart.items.sum { |item| item.price }\nend\n' > "$repo/src/cart.rb"
git -C "$repo" add -A
git -C "$repo" -c user.email=t@example.com -c user.name=t commit -q -m one
sha=$(git -C "$repo" rev-parse HEAD)

draft() {
  local extra=${3:-'{}'}
  jq -n --arg body "$2" --argjson extra "$extra" '[{path: "src/cart.rb", line: 2, body: $body} + $extra]' > "$1"
}
result() {
  local output status=0
  output=$(cd "$repo" && bash "$check" "$1" "$sha") || status=$?
  if [ "$status" -eq 0 ]; then echo clean; else printf '%s\n' "$output"; fi
}

draft "$work_dir/exists.json" $'**suggestion**:\nThe total could use `cart.items.sum { |item| item.price }` as below.'
expect_eq "§PC5: code that is in the repo is clean" clean "$(result "$work_dir/exists.json")"
draft "$work_dir/invented.json" $'**suggestion**:\nAdd `discount(cart) { false }` to skip it.'
expect_contains "§PC5: code found nowhere in the repo is reported" "appears nowhere in the repo" "$(result "$work_dir/invented.json")"
draft "$work_dir/said-new.json" $'**suggestion**:\nA new `discount(cart) { false }` would skip it.' '{"new": "no helper does this yet; the comment says it is new"}'
expect_eq "§PC5: new code with a reason is clean" clean "$(result "$work_dir/said-new.json")"
draft "$work_dir/name-only.json" $'**suggestion**:\nThe name `orderTotal` reads better.'
expect_eq "§PC5: a plain name is left to check-draft-names.sh" clean "$(result "$work_dir/name-only.json")"
draft "$work_dir/fenced.json" $'**suggestion**:\nLike this:\n```rb\ndiscount(cart) { false }\n```'
expect_eq "§PC5: code in a fenced block is not looked up" clean "$(result "$work_dir/fenced.json")"
outside=$(cd "$work_dir" && bash "$check" "$work_dir/invented.json" "$sha"; echo "exit $?")
expect_eq "§PC5: away from the repo it checks nothing" "exit 0" "$outside"

finish
