#!/usr/bin/env bash
# Tests the lint step of scripts/guard-hand-off.sh (through scripts/lint-changed-files.sh): a push
# is denied, with the lint output, when the repo's lint fails on the files changed since the push
# base. The repo declares its lint in .claude/lint-command, or has biome.json (then `npx biome
# check`, here a stub npx that fails on files holding the word BAD); with neither, nothing runs.
# Only files changed since the base are linted: a bad file the remote already has is not.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
export KC_READY_DIR="$work_dir/receipts"

# A stub npx: `npx biome check <files>` fails on a file holding BAD, and logs its call.
mkdir -p "$work_dir/bin"
cat > "$work_dir/bin/npx" <<'STUB'
#!/bin/sh
echo "npx $*" >> "$LINT_LOG"
shift 2
for file in "$@"; do
  if grep -q BAD "$file"; then echo "lint error in $file"; exit 1; fi
done
STUB
chmod +x "$work_dir/bin/npx"
export PATH="$work_dir/bin:$PATH"
export LINT_LOG="$work_dir/lint.log"

git_in() { git -C "$1" -c user.name=t -c user.email=t@example.test "${@:2}"; }

# A repo whose remote has main and `feature`; the work is more commits on feature.
make_repo() {
  local name=$1
  git init -q --bare "$work_dir/$name.git"
  git init -q -b main "$work_dir/$name"
  git_in "$work_dir/$name" remote add origin "$work_dir/$name.git"
  mkdir -p "$work_dir/$name/src"
  printf 'old BAD file the remote already has\n' > "$work_dir/$name/src/old.ts"
  git_in "$work_dir/$name" add -A
  git_in "$work_dir/$name" commit -q -m base
  git_in "$work_dir/$name" push -q origin main:main main:feature
  git_in "$work_dir/$name" fetch -q origin
  git_in "$work_dir/$name" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  git_in "$work_dir/$name" checkout -q -b feature origin/feature
}
# Commits <content> as <file> in repo <name>.
commit_file() {
  mkdir -p "$(dirname "$work_dir/$1/$2")"
  printf '%s\n' "$3" > "$work_dir/$1/$2"
  git_in "$work_dir/$1" add -A
  git_in "$work_dir/$1" commit -q -m "change $2"
}
# Pushes the repo's feature branch to its remote, as setup (no guard).
publish() { git_in "$work_dir/$1" push -q origin feature; }

push_command='git push origin feature'
build_payload() {
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"test"},"tool_use_id":"t"}' "$2" "$1"
}
LAST_OUTPUT=""
check() {
  local expectation=$1 label=$2 repo=$3 verdict
  LAST_OUTPUT=$(build_payload "$push_command" "$work_dir/$repo" | bash "$scripts/guard-hand-off.sh" 2>/dev/null)
  if [ -z "$LAST_OUTPUT" ]; then verdict=allow
  elif printf '%s' "$LAST_OUTPUT" | grep -q '"permissionDecision":"deny"'; then verdict=deny
  else verdict="unexpected output: $LAST_OUTPUT"; fi
  expect_eq "$label" "$expectation" "$verdict"
}

# biome.json at the root: lint the changed files with `npx biome check`.
make_repo biome
printf '{}\n' > "$work_dir/biome/biome.json"
git_in "$work_dir/biome" add -A && git_in "$work_dir/biome" commit -q -m biome
publish biome
: > "$LINT_LOG"
commit_file biome src/new.ts 'BAD code'
check deny "a push of a file that fails biome is denied" biome
expect_contains "the deny carries the lint output" "lint error in src/new.ts" "$LAST_OUTPUT"
expect_contains "biome ran on the changed file" "npx biome check src/new.ts" "$(cat "$LINT_LOG")"
expect_eq "the bad file the remote already has is not linted" no "$(grep -q 'old.ts' "$LINT_LOG" && echo yes || echo no)"
commit_file biome src/new.ts 'good code'
check allow "the same push once the file is fixed is allowed" biome
publish biome
commit_file biome notes.md 'BAD docs'
: > "$LINT_LOG"
check allow "a change to a file biome does not read is allowed" biome
expect_eq "and biome was not run" "" "$(cat "$LINT_LOG")"

# .claude/lint-command: the repo's own one-line command, given the changed files.
make_repo custom
mkdir -p "$work_dir/custom/.claude"
# shellcheck disable=SC2016 # the lint stub's own "$@", written as text.
printf '#!/bin/sh\nfor f in "$@"; do grep -q WRONG "$f" && echo "style: $f" && exit 1; done\nexit 0\n' > "$work_dir/custom/lint.sh"
chmod +x "$work_dir/custom/lint.sh"
printf '# how this repo lints\n./lint.sh\n' > "$work_dir/custom/.claude/lint-command"
git_in "$work_dir/custom" add -A && git_in "$work_dir/custom" commit -q -m lint
publish custom
commit_file custom src/a.rb 'WRONG style'
check deny "a push failing the repo's own lint command is denied" custom
expect_contains "the deny carries that command's output" "style: src/a.rb" "$LAST_OUTPUT"
commit_file custom src/a.rb 'fine'
check allow "a push passing the repo's own lint command is allowed" custom

# Neither a lint command nor biome.json: nothing runs.
make_repo none
commit_file none src/a.ts 'BAD code'
: > "$LINT_LOG"
check allow "with no lint declared a push is allowed" none
expect_eq "and no lint ran" "" "$(cat "$LINT_LOG")"

finish
