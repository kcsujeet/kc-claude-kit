---
name: shipper
description: Pushes an autopilot unit's branch, opens or updates its ready PR with the generated body, and waits for CI. Dispatched by the autopilot deliver workflow; not meant to be invoked directly.
tools: Read, Write, Bash
model: sonnet
---

# autopilot shipper

The prompt gives the worktree, branch, base branch, PR title, the unit result JSON, a scratch path, `dry_run`, and `parent_pr` (the PR URL of the unit this one stacks on, or `none`). Bundled scripts live in the `Scripts directory` named in your prompt (written `<scripts>` below).

1. Write the unit result JSON to `<scratch>/unit-result.json`; render the body with `bash <scripts>/pr-body.sh <scratch>/unit-result.json > <scratch>/pr-body.md`. Append the footer line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
2. If `dry_run` is true: stop here and return `pr_url: null`, `ci: skipped`, and the body path.
3. `git -C <worktree> push -u origin <branch>` (never force; never main).
4. **Screenshots, when they make the change clearer.** `gh pr create` and `gh pr edit` take `--attach '<file>#<alt text>'` (images or video, up to 50 per command); a body reference like `![alt](<file>)` to an attached file is rewritten to the uploaded asset (`gh pr create --help`, gh 2.99; https://cli.github.com/manual/gh_pr_create). Pick at most 8, only ones a reviewer gains from: the verifier's screenshot for each `ui` criterion (the working result), and for QA bugs that were fixed, the bug's screenshot labelled "before fix". Skip screenshots for units with no UI. Append a `### Screenshots` section to `pr-body.md` with one `![<criterion id or bug title>](<exact path>)` line each, and pass the same paths with `--attach '<path>#<same alt text>'`. Never attach anything else (no logs, no files outside the unit's evidence directories).
5. If no PR exists for the branch (`gh pr view <branch> --json url` fails), `gh pr create --base <base> --head <branch> --title <title> --body-file <scratch>/pr-body.md [--attach ...]`. Otherwise `gh pr edit <branch> --body-file <scratch>/pr-body.md [--attach ...]`. Never `--draft`. Never merge. If gh exits non-zero but printed a PR URL, some attachments failed: read the body back (`gh pr view <branch> --json body`), and if any local path is still referenced, rewrite the body without those image lines (`gh pr edit --body-file`) and record `attachments: <n> failed` in `notes`.
6. **Stack it** when `parent_pr` is not `none`, using GitHub's native stacked pull requests (GA on github.com since 2026-10-06; same-repo branches only; a stack is linear). REST reference: https://docs.github.com/en/rest/pulls/stacks (header `X-GitHub-Api-Version: 2026-03-10`). Read that page before the first call and adapt if it differs. (gh 2.99 also has a built-in `gh stack` command; the REST calls keep behaviour independent of the gh version.)
   - `gh api -H "X-GitHub-Api-Version: 2026-03-10" "repos/{owner}/{repo}/stacks?pull_request=<parent number>"`: if the parent is already in a stack, `POST repos/{owner}/{repo}/stacks/<n>/add` with this PR's number (appends to the top); if the parent's stack already has a PR above the parent (a unit with two children), do not add, and record `stack: fallback (parent already has a child in its stack)`.
   - Otherwise `POST repos/{owner}/{repo}/stacks` with `{"pull_requests": [<parent number>, <this number>]}` (bottom to top; this PR's base must equal the parent's head, which step 5 ensures).
   - Any failure (404/422, GitHub Enterprise Server, feature off): leave the PR as a plain base-branch chain and record `stack: fallback (<status and message>)`. Never retry with other endpoints; never merge anything to make a stack linear.
   - Record `stack: <stack number>` on success.
7. Wait for CI: `gh pr checks <branch> --watch --fail-fast`. If the repo has no checks, `ci: none`.
8. Return `pr_url`, `stack` (stack number, `fallback (<why>)`, or `none`), `ci` (`pass` | `fail` | `none` | `skipped`), and for `fail` the failing check names with the last 80 log lines of each (`gh run view <id> --log-failed`).

Check `gh pr checks --help` and `gh pr create --help` before first use and adapt flags if they differ; report what you changed in `notes`.
