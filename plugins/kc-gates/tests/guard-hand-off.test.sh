#!/usr/bin/env bash
# Tests scripts/guard-hand-off.sh: the first push of a branch, opening a PR
# (draft or not) and handing one to review are denied unless the commit has a
# ready-receipt.sh receipt, against the stub gh in lib/
# answering from fixtures/guard-hand-off/ (PR 12 and the --head branch
# `feature` are at the reviewed commit, PR 13 is not). Each guard case
# runs twice, once with jq and once through the sed fallback.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
scripts="$(dirname "$tests_dir")/scripts"
require_jq
use_gh_fixtures "$tests_dir/fixtures/guard-hand-off"
export KC_READY_DIR="$work_dir/receipts"

reviewed=$(printf 'a%.0s' {1..40})
# Two local repos for `gh pr create` without --head: one whose HEAD has a
# receipt, one whose HEAD has none.
make_repo() {
  git init -q "$1"
  git -C "$1" -c user.name=t -c user.email=t@example.test commit -q --allow-empty -m "$2"
}
make_repo "$work_dir/ready-repo" ready
make_repo "$work_dir/draft-repo" draft
# Two repos with a hand-off checklist: one opts drafts in, one doesn't.
make_checklist_repo() {
  git init -q "$1"
  mkdir -p "$1/.claude"
  printf '%b' "$2" > "$1/.claude/hand-off-checklist.md"
  git -C "$1" add .claude
  git -C "$1" -c user.name=t -c user.email=t@example.test commit -q -m checklist
}
make_checklist_repo "$work_dir/lesson-repo" '---\ndrafts: true\n---\n\n# Hand-off checklist\n'
make_checklist_repo "$work_dir/plain-repo" '# Hand-off checklist\n\n- [ ] drafts: true is not front matter here\n'

# A bare remote holding `main` and `existing`; the work repos push to it, as
# origin, from a new branch `feature-new`. ready-repo's HEAD has a receipt,
# draft-repo's has none; offline-repo's remote can't be reached.
git init -q --bare "$work_dir/remote.git"
git -C "$work_dir/ready-repo" -c user.name=t -c user.email=t@example.test branch -m main
git -C "$work_dir/ready-repo" remote add origin "$work_dir/remote.git"
git -C "$work_dir/ready-repo" push -q origin main:main main:existing
git -C "$work_dir/ready-repo" checkout -q -b feature-new
for repo in draft-repo offline-repo; do
  [ "$repo" = draft-repo ] || make_repo "$work_dir/$repo" offline
  git -C "$work_dir/$repo" checkout -q -b feature-new
done
git -C "$work_dir/draft-repo" remote add origin "$work_dir/remote.git"
git -C "$work_dir/lesson-repo" checkout -q -b feature-new
git -C "$work_dir/lesson-repo" remote add origin "$work_dir/remote.git"
git -C "$work_dir/draft-repo" tag v1.0
git -C "$work_dir/offline-repo" remote add origin "$work_dir/missing.git"
mkdir "$work_dir/not-a-repo"
# Empty remotes: one for a repo that doesn't know the remote's default branch
# (main and master are taken as default), one that does (trunk).
git init -q --bare "$work_dir/empty.git"
git clone -q "$work_dir/empty.git" "$work_dir/fresh-repo" 2>/dev/null
git -C "$work_dir/fresh-repo" -c user.name=t -c user.email=t@example.test commit -q --allow-empty -m fresh
git -C "$work_dir/fresh-repo" checkout -q -b feature-new
git -C "$work_dir/fresh-repo" tag v2.0
git init -q --bare "$work_dir/empty-trunk.git"
git -C "$work_dir/empty-trunk.git" symbolic-ref HEAD refs/heads/trunk
git clone -q "$work_dir/empty-trunk.git" "$work_dir/trunk-repo" 2>/dev/null
git -C "$work_dir/trunk-repo" -c user.name=t -c user.email=t@example.test commit -q --allow-empty -m trunk
git -C "$work_dir/trunk-repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
git -C "$work_dir/trunk-repo" branch -q -m main
# ready-repo's HEAD is reviewed; unreviewed-side is a branch one commit past it.
git -C "$work_dir/ready-repo" -c user.name=t -c user.email=t@example.test commit -q --allow-empty -m side
git -C "$work_dir/ready-repo" branch unreviewed-side
git -C "$work_dir/ready-repo" reset -q --hard HEAD~1

# The guard reads receipts through `ready-receipt.sh check`; how a pass earns
# one is ready-receipt.test.sh's to test, so these pass receipts are written
# by hand.
mkdir -p "$KC_READY_DIR"
printf 'rounds=2\n' > "$KC_READY_DIR/$reviewed"
printf 'rounds=2\n' > "$KC_READY_DIR/$(git -C "$work_dir/ready-repo" rev-parse HEAD)"

# Wraps a shell command (no double quotes or backslashes in it) and a working
# directory in the PreToolUse stdin payload.
build_payload() {
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s","description":"test"},"tool_use_id":"t"}' "$2" "$1"
}

check() {
  local expectation=$1 label=$2 command=$3 cwd=${4:-$work_dir/ready-repo} mode output verdict
  for mode in jq sed; do
    if [ "$mode" = sed ]; then
      output=$(build_payload "$command" "$cwd" | KC_GUARD_NO_JQ=1 bash "$scripts/guard-hand-off.sh" 2>/dev/null)
    else
      output=$(build_payload "$command" "$cwd" | bash "$scripts/guard-hand-off.sh" 2>/dev/null)
    fi
    if [ -z "$output" ]; then
      verdict=allow
    elif printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then
      verdict=deny
    else
      verdict="unexpected output: $output"
    fi
    expect_eq "[$mode] $label" "$expectation" "$verdict"
  done
}

check deny  "blocked: gh pr ready on an unreviewed PR" \
  "gh pr ready 13"
check deny  "blocked: adding a reviewer to an unreviewed PR" \
  "gh pr edit 13 --repo acme/widgets --add-reviewer ana"
check deny  "blocked: opening a ready PR from an unreviewed HEAD" \
  "gh pr create --title 'Add widgets' --body-file /tmp/body.md" "$work_dir/draft-repo"
check deny  "blocked: cd into an unreviewed repo, then gh pr create" \
  "cd $work_dir/draft-repo && gh pr create --fill"
check deny  "blocked: reviewer request through gh api" \
  "gh api repos/acme/widgets/pulls/13/requested_reviewers -X POST -f 'reviewers[]=ana'"
check deny  "blocked: head commit cannot be found" \
  "gh pr ready 99"

check allow "allowed: gh pr ready on a reviewed PR" \
  "gh pr ready 12 --repo acme/widgets"
check allow "allowed: current branch's PR is reviewed" \
  "gh pr edit --add-reviewer ana"
check allow "allowed: reviewer request on a reviewed PR" \
  "gh api repos/acme/widgets/pulls/12/requested_reviewers -X POST -f 'reviewers[]=ana'"
check allow "allowed: ready PR whose --head branch is reviewed" \
  "gh pr create --repo acme/widgets --head feature --fill"
check allow "allowed: ready PR whose --head branch is reviewed, repo from the directory" \
  "gh pr create --head=feature --fill"
check allow "allowed: ready PR from a reviewed HEAD" \
  "gh pr create --title 'Add widgets' --body-file /tmp/body.md"
check allow "allowed: cd into a reviewed repo, then gh pr create" \
  "cd $work_dir/ready-repo && gh pr create --fill" "$work_dir/draft-repo"
check deny  "blocked: draft PR from an unreviewed HEAD" \
  "gh pr create --draft --fill" "$work_dir/draft-repo"
check deny  "blocked: draft PR from an unreviewed HEAD, checklist without drafts front matter" \
  "gh pr create --draft --fill" "$work_dir/plain-repo"
check deny  "blocked: draft PR, short flag, checklist with drafts front matter" \
  "gh pr create -d --fill" "$work_dir/lesson-repo"
check deny  "blocked: draft PR whose --head branch has no receipt" \
  "gh pr create --draft --repo acme/widgets --head lesson --fill"
check allow "allowed: draft PR from a reviewed HEAD" \
  "gh pr create --draft --fill" "$work_dir/ready-repo"
check allow "allowed: draft PR whose --head branch is reviewed" \
  "gh pr create --draft --repo acme/widgets --head feature --fill"
check allow "allowed: back to draft" \
  "gh pr ready 13 --undo"
check deny  "blocked: --undo=false marks the PR ready" \
  "gh pr ready 13 --undo=false"
check deny  "blocked: --draft=false opens a ready PR" \
  "gh pr create --draft=false --fill" "$work_dir/draft-repo"
check deny  "blocked: --draft=true opens a draft from an unreviewed HEAD" \
  "gh pr create --draft=true --fill" "$work_dir/draft-repo"
check deny  "blocked: a draft that requests a reviewer" \
  "gh pr create --draft --reviewer ana --fill" "$work_dir/draft-repo"
check deny  "blocked: a draft that requests a reviewer, short flags" \
  "gh pr create -d -r ana --fill" "$work_dir/draft-repo"
check allow "allowed: edit without a reviewer" \
  "gh pr edit 13 --title 'Add widgets'"
check allow "allowed: user said to skip the pass" \
  "KC_READY_SKIP=1 gh pr ready 13"
check allow "allowed: reading reviewers" \
  "gh api repos/acme/widgets/pulls/13/requested_reviewers"
check allow "allowed: gh pr view" \
  "gh pr view 13 --json headRefOid"
check allow "allowed: non-gh command" \
  "git status"

# The first push of a branch.
check deny  "blocked: git push -u origin <new branch>, no receipt" \
  "git push -u origin feature-new" "$work_dir/draft-repo"
check deny  "blocked: git push origin <new branch>" \
  "git push origin feature-new" "$work_dir/draft-repo"
check deny  "blocked: git push --set-upstream origin HEAD" \
  "git push --set-upstream origin HEAD" "$work_dir/draft-repo"
check deny  "blocked: git push origin HEAD:<new branch>" \
  "git push origin HEAD:feature-new" "$work_dir/draft-repo"
check deny  "blocked: bare git push of a new current branch" \
  "git push" "$work_dir/draft-repo"
check deny  "blocked: git -C <repo> push from elsewhere" \
  "git -C $work_dir/draft-repo push -u origin feature-new" "$work_dir/not-a-repo"
check deny  "blocked: cd into the repo, then push" \
  "cd $work_dir/draft-repo && git push -u origin feature-new" "$work_dir/not-a-repo"
check allow "allowed: first push of a reviewed HEAD" \
  "git push -u origin feature-new" "$work_dir/ready-repo"
check allow "allowed: push to a branch the remote has (HEAD:existing)" \
  "git push origin HEAD:existing" "$work_dir/draft-repo"
check allow "allowed: force push to a branch the remote has" \
  "git push --force-with-lease origin existing" "$work_dir/draft-repo"
check allow "allowed: push to the default branch" \
  "git push origin HEAD:main" "$work_dir/draft-repo"
check allow "allowed: push --delete" \
  "git push origin --delete feature-new" "$work_dir/draft-repo"
check allow "allowed: push :branch deletes" \
  "git push origin :feature-new" "$work_dir/draft-repo"
check allow "allowed: first push of main to an empty remote" \
  "git push -u origin main" "$work_dir/fresh-repo"
check deny  "blocked: first push of a feature branch to an empty remote" \
  "git push -u origin feature-new" "$work_dir/fresh-repo"
check allow "allowed: first push of the remote's own default branch (trunk)" \
  "git push origin trunk:trunk" "$work_dir/trunk-repo"
check deny  "blocked: main is not the default when the remote's default is trunk" \
  "git push origin main" "$work_dir/trunk-repo"
check allow "allowed: push a tag by its full ref" \
  "git push origin refs/tags/v2.0:refs/tags/v2.0" "$work_dir/fresh-repo"
check deny  "blocked: the pushed branch is checked, not HEAD" \
  "git push origin unreviewed-side:feature-x" "$work_dir/ready-repo"
check allow "allowed: git fetch is not a push" \
  "git fetch origin feature-new" "$work_dir/draft-repo"
check allow "allowed: push a tag" \
  "git push origin v1.0" "$work_dir/draft-repo"
check allow "allowed: push --tags" \
  "git push --tags" "$work_dir/draft-repo"
check allow "allowed: push outside a git repo" \
  "git push -u origin feature-new" "$work_dir/not-a-repo"
check allow "allowed: remote cannot be reached" \
  "git push -u origin feature-new" "$work_dir/offline-repo"
expect_contains "an unreachable remote is noted on stderr" "could not reach remote" \
  "$(build_payload 'git push -u origin feature-new' "$work_dir/offline-repo" | bash "$scripts/guard-hand-off.sh" 2>&1 >/dev/null)"
expect_eq "a push outside a git repo prints no note" "" \
  "$(build_payload 'git push -u origin feature-new' "$work_dir/not-a-repo" | bash "$scripts/guard-hand-off.sh" 2>&1)"
check allow "allowed: user said to skip the pass, first push" \
  "KC_READY_SKIP=1 git push -u origin feature-new" "$work_dir/draft-repo"
check allow "allowed: git commit is not a push" \
  "git commit -m 'git push later'" "$work_dir/draft-repo"

# Written from the work dir: a checklist receipt reads the checklist of the repo it runs in.
(cd "$work_dir" && bash "$scripts/ready-receipt.sh" write "$(git -C "$work_dir/lesson-repo" rev-parse HEAD)" --checklist >/dev/null)
(cd "$work_dir" && bash "$scripts/ready-receipt.sh" write "$(printf 'd%.0s' {1..40})" --checklist >/dev/null)
check deny  "blocked: a draft PR whose head has only the checklist's receipt" \
  "gh pr create --draft --fill" "$work_dir/lesson-repo"
check deny  "blocked: a draft PR from GitHub whose head has only the checklist's receipt" \
  "gh pr create --draft --repo acme/widgets --head lesson --fill"
check deny  "blocked: first push whose head has only the checklist's receipt" \
  "git push -u origin feature-new" "$work_dir/lesson-repo"
check deny  "blocked: a ready PR whose head has only the checklist's receipt" \
  "gh pr create --repo acme/widgets --head lesson --fill"

finish
