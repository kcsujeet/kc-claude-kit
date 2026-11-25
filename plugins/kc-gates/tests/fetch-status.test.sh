#!/usr/bin/env bash
# Tests scripts/fetch-status.sh: a status prompt gets the pull requests' current state before the
# reply (the one the session's transcript names most recently first, an unreadable one skipped),
# and any other prompt gets nothing. gh is a stub that answers from fixture JSON.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
hook="$(dirname "$tests_dir")/scripts/fetch-status.sh"
require_jq

# A gh stub: `gh pr view <url> --json ...` prints $work_dir/prs/<number>.json, or fails.
mkdir -p "$work_dir/bin" "$work_dir/prs"
cat > "$work_dir/bin/gh" <<'STUB'
#!/usr/bin/env bash
[ "$1 $2" = "pr view" ] || exit 1
number=${3##*/}
[ -f "$GH_STUB_DIR/$number.json" ] || exit 1
cat "$GH_STUB_DIR/$number.json"
STUB
chmod +x "$work_dir/bin/gh"
export GH_STUB_DIR=$work_dir/prs
PATH=$work_dir/bin:$PATH

cat > "$work_dir/prs/41.json" <<'JSON'
{"number":41,"title":"Add free shipping","state":"OPEN","isDraft":false,"reviewDecision":"APPROVED","mergeStateStatus":"BEHIND","headRefOid":"abcdef1234567","mergedAt":null,"reviewRequests":[{"login":"rev"}],"latestReviews":[{"author":{"login":"lead"},"state":"APPROVED"}],"statusCheckRollup":[{"conclusion":"SUCCESS"},{"conclusion":"FAILURE"},{"status":"IN_PROGRESS"}]}
JSON
cat > "$work_dir/prs/40.json" <<'JSON'
{"number":40,"title":"Old work","state":"MERGED","isDraft":false,"reviewDecision":"","mergeStateStatus":"UNKNOWN","headRefOid":"1111111111","mergedAt":"2026-01-02T03:04:05Z","reviewRequests":[],"latestReviews":[],"statusCheckRollup":[]}
JSON

transcript=$work_dir/session.jsonl
{
  echo '{"type":"assistant","text":"opened https://github.com/acme/shop/pull/40"}'
  echo '{"type":"assistant","text":"example https://github.com/acme/example/pull/999"}'
  echo '{"type":"assistant","text":"opened https://github.com/acme/shop/pull/41"}'
} > "$transcript"

run_hook() {
  jq -cn --arg p "$1" --arg t "$transcript" --arg c "$work_dir" '{prompt: $p, transcript_path: $t, cwd: $c, hook_event_name: "UserPromptSubmit"}' | bash "$hook"
}

output=$(run_hook "check if the pr can be merged")
expect_contains "a status prompt gets the fetched state" "fetched just now, before your reply" "$output"
expect_contains "it says to answer from it, not memory" "not from memory" "$output"
expect_contains "the newest pull request comes first, with its review" "https://github.com/acme/shop/pull/41 Add free shipping
  state OPEN; review APPROVED; pending reviewers: rev; latest reviews: lead APPROVED" "$output"
expect_contains "its merge state and checks are counted" "merge state BEHIND; head abcdef123; checks: 1 passed, 1 failed, 1 running, 3 total" "$output"
expect_contains "an older one follows, merged" "state MERGED, merged 2026-01-02T03:04:05Z; review none" "$output"
expect_not_contains "an unreadable URL is skipped" "acme/example/pull/999" "$output"
expect_eq "a pull request named twice is read once" 1 "$(printf '%s\n' "$output" | grep -c 'pull/41 ')"

expect_eq "an instruction gets nothing" "" "$(run_hook "rename the shipping helper")"
expect_contains "\"i think QA has been done?\" is a status prompt" "pull/41" "$(run_hook "i think QA has been done?")"
expect_contains "\"what next?\" is a status prompt" "pull/41" "$(run_hook "what next?")"

KC_STATUS_MAX_PRS=1
export KC_STATUS_MAX_PRS
expect_not_contains "the cap stops after the newest readable one" "pull/40" "$(run_hook "any update")"
unset KC_STATUS_MAX_PRS

: > "$transcript"
expect_contains "nothing readable: it says to read the state with a tool" "Read the state with a tool before stating it" "$(run_hook "status?")"

finish
