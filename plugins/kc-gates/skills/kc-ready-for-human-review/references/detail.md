# Ready for human review detail

The wording behind each step of `SKILL.md`. Read the section a step or box points to.

- This skill answers one question: is this change ready for a human reviewer? It does not review the code or decide when it runs. `kc-gates:kc-self-correct` reviews and fixes the change and records the content it reviewed; this one confirms that record matches the content being handed over, grades what a human reviewer reads first (the hand-off checklist, the PR description, the Risk section, CI's commands) and writes the receipt the guards check. A PR merges only on a clean receipt (the last round found nothing and nothing is left open), which `guard-merge.sh` enforces.

- **Not for a small, safe change:** one `change-class.sh` classes `prose_small` or `code_small` (`pass-size.sh` small with no `risk:` line, so no auth, security, permissions, payments, deletion, migration or other sensitive path) needs no record and no receipt: the hand-off and merge guards let it through.

### Confirm the review

- **The record is keyed on content.** `tree-hash.sh HEAD` is the tree of the commit being handed over; `self-correct-record.sh check <tree>` finds the record `kc-self-correct` wrote for that content, whether it was reviewed before or after the commit existed. A record for other content (the content changed since) does not match: run `kc-self-correct` on the delta.
- **A record with open findings** goes to the person as decisions, with each finding's one-line fix; the receipt can still be written (`--open <n>`), but it is not clean and `guard-merge.sh` will not merge it.

### Hand-off

- **Write the PR's title and body,** to `.git/kc-pr/<branch>.md` (first line the title, a blank line, then the body), so the hand-off checklist grades the description as it will be read. Opening the PR uses that file's title and body.
- **Check the hand-off:** grade every box in the repo's `.claude/hand-off-checklist.md` against the PR as it will be read, not the diff: its title and description (the body file), the linked ticket, the paired or stacked PRs, the flags and tasks it names. No such file: check the description against the repo's PR template and say so. **Record a verdict per box** in the pass folder's `checklist.md`: the checklist's box lines copied as they are, each `[ ]` replaced by `[PASS]`, `[FAIL]` or `[N/A: reason]`. A FAIL is fixed (through `kc-self-correct`) or goes to the user; a box you know is unmet is never left as "still to do" while a hand-off action runs.
   - **Merge risk.** Whatever the checklist says, the description carries a short **Risk** section, written from the diff you already have, with no agent dispatched for it:
     - **Impact:** what the change reaches, starting from `pass-size.sh`'s `risk:` lines, and naming any sensitive path (authentication, permissions, payments, a shared contract or public API, data deletion).
     - **Rollback:** a two-way door (reverting the PR undoes it) or a one-way door (a column or table dropped, data backfilled or deleted, messages or charges sent), with what undoing a one-way door takes.
     - **Detection:** how a failure would show (error reporting, logs, a failing job), or that nothing would.

     High impact with a one-way door, or a new path whose failure nothing would report, goes to the user before the pass ends, with the fix: split the risky part into its own stacked PR, add error reporting on the new path, or drop changes the issue didn't ask for. Example: a migration that drops a column shipped in the same PR as the code that stops reading it, so a revert of the code finds the column gone.
- **CI's commands, locally.** Run them here, so a failure is fixed before a reviewer or CI sees it: the commands in `.claude/ci-commands` when the repo has that file (one per line, optional), otherwise the test command plus the project's lint and typecheck. A failure is fixed like a finding, through `kc-self-correct`. Say in the report which ran.

#### Receipt

6. Write the receipt for the commit (command in SKILL.md), then open the PR from the body file (`--title` its first line, `--body-file` the rest; draft or ready, as the repo wants), and check that the PR's head is the commit (`gh pr view --json headRefOid`). When the branch on the remote has moved but the pull request still shows the old head after a minute, the forge didn't apply the push to the pull request: save its base again unchanged (`gh api -X PATCH repos/<owner>/<repo>/pulls/<n> -f base=<base>`) and check again, rather than waiting it out. A push refused with a server-side error, not a rejection of the commits, is retried once.

   `--verdicts` records the checklist's per-box verdicts for the commit (a repo with `.claude/hand-off-checklist.md` needs them: the guard blocks a hand-off while any box lacks one, is FAIL or is N/A with no reason); `--task` also records them under a tracker issue key, so the tracker guard finds them with no repo.

   Run it from the repo root. It refuses, and says every item that is missing, unless `self-correct-record.sh` has a record for the commit's tree; `round-1/` has a block for every gate `select-gates.sh` lists for its diff (a working-tree round keeps its saved diff; project-conventions only when the repo had `.claude/review-conventions.md` at that head), a verification block and a `SCOPE:` block marking §G1 to §G5 once each with evidence; `fixes.txt` has a line for each finding when the content changed after round 1 or findings are open, each fix naming a test file that change added or changed; the person's words approve fixes that touch a file outside round 1's diff that isn't a test, or bring a kind of risk it didn't have; and the commit descends from round 1's head. It refuses `--rounds 4`. It writes the receipt as `<sha>` and as `tree-<tree>`, so a later commit of the same content (an amend, a rebase) finds it. It checks that the records are there and well formed, not that they are right. Never write a block yourself to get past it: run what is missing.

7. **Changes after the receipt,** the ones the person picks from the open list or a reviewer's comments ask for: run `kc-self-correct` on them (uses checked, a test that fails when it is broken, lint and types), then write `ready-receipt.sh write <new-sha> --rounds <k>`, within the three-round limit. `--after <receipt-sha>` only keeps the PR in review; it never makes a fix commit clean, so `guard-merge.sh` will not merge it. A merge of the default branch into a clean head that adds nothing of its own (only a manifest version or CHANGELOG order resolved) is clean with no new pass. Fix or answer every comment on the PR, bot reviewers included (they post when it goes ready); `ready-receipt.sh` refuses while one has no reply from the author.

### Gate checklist

- What the hand-off must show before its receipt. Each box is held by a script or a check lists what breaks it.

- [ ] §H11 A `kc-self-correct` record exists for the content being handed over (its tree hash) and the receipt names that tree; content that changed since the record was reviewed on the delta first. Held by `ready-receipt.sh` (it refuses without the record) and `guard-hand-off.sh` (it names the missing record or receipt). (N/A: a small change needing no receipt)
- [ ] §H7 Every box of the hand-off checklist has a verdict recorded with `--verdicts` (PASS, or N/A with a reason), and no hand-off action (opening or readying the PR, a reviewer, moving the ticket to its review status) was done while a box was FAIL or unrecorded. Held by the guard: `guard-hand-off.sh` and `guard-tracker-transition.sh` block it. (N/A: the repo has no hand-off checklist)
- [ ] §H5 Changes after the receipt (the user's picks, a reviewer's comments) went through `kc-self-correct` on the delta, within the three-round limit. A change a reviewer asked for was checked like your own before it was written (its placement, its scope and what it breaks, against the rules and the code), not followed word for word, and every PR comment, bot reviewers included, has a reply (held by `ready-receipt.sh`). Merging the default branch in to clear a conflict is not a fix and needs no round: the merge stays clean when it adds nothing beyond what either parent had (held by `ready-receipt.sh` and `tests/ready-receipt-merge.test.sh`). (N/A: nothing changed since the receipt)
- [ ] §H10 The PR description reads in under a minute: what changed and why, how to test it, the evidence. It holds no process notes (rounds, gates, receipts), no word counts and no restatement of the diff. (N/A: never)
- [ ] §H9 Screenshots and any walkthrough video are in the PR description itself, uploaded with `gh pr create --attach <file>` or `gh pr edit <n> --attach <file>` (gh 2.101+; `'<file>#<alt text>'` sets the alt text; an image reference to the local file in the body is rewritten to the uploaded asset). Run `gh --version` first and update gh when it is older. (N/A: no visual change)

### The guard

- `scripts/guard-hand-off.sh` blocks the first `git push` of a branch (its target isn't on the remote yet), every `gh pr create`, draft or not, `gh pr ready`, `gh pr edit --add-reviewer` and a write to a PR's `requested_reviewers`, until the commit, or another commit with the same content (its tree), has a pass or `--after` receipt. A deny names what is missing: a `kc-self-correct` record for the content, or only the receipt. Pushes to a branch the remote already has (fix rounds, rebases), to the default branch, tags and deletes are not blocked. A hand-off checklist's `drafts: true` front matter is not needed: the guard blocks every `gh pr create`. A push, PR or hand-off done in a browser or through another tool isn't seen; write the receipt for those too.

- In a repo with `.claude/hand-off-checklist.md`, the same commands also need the checklist's verdicts (`--verdicts` above): every box PASS or N/A with a reason, else the block names each unmet box, one line each, and gives the command to record them.

- `scripts/guard-tracker-transition.sh` guards the same hand-off through a tracker: an MCP call that transitions an issue (a tool named like `transition…Issue`, a generic execute tool running one, or a save or update call on an issue such as `save_issue` whose state or status field is set) to a status matching `review` (`KC_REVIEW_STATUS_REGEX` in the settings `env` changes it) is blocked until the checklist has verdicts: those of the session repo's HEAD, or, outside a repo, the ones recorded with `--task <KEY>` for the issue. A call naming only a transition id can't be read and isn't blocked.

- A small change asks less of the user (`scripts/change-class.sh` classes the branch from the default branch). `prose_small`, a few prose lines (Markdown and the like, at most 30 changed lines, plus files the repo lists in `.claude/generated-paths.txt` as regenerated from them and version bumps), needs no pass receipt and no `approve rework`, and merges with no receipt once its checks pass. `code_small` (`pass-size.sh` small, no risk line) needs no pass receipt either, and merges once its checks pass; any `risk:` line makes it `full`. The loop-stop guard leaves out lines the branch's own earlier commits wrote. When a guard still needs the user's words, its block lists every phrase the steps ahead need (`approvals-needed.sh`): ask for them in one message and run those steps in that turn, since each guard reads only the latest message.

- When the user says to skip the pass for a PR, prefix that command with `KC_READY_SKIP=1`. Never add it on your own, and never to get past a pass that found something. The tracker guard takes the same token in the call (a comment field) or the environment, on the same terms.


### Report

- Chat, short:

```
#### Ready for human review: <PR title>
**Head:** `<short-sha>` · **Content:** `<short tree hash>` · **Size:** <small|full> · **Rounds:** <k> · **Open:** <n>
**Risk:** <impact> · <two-way|one-way door> · <how a failure shows>

| Check | Result |
|-------|--------|
| Self-correct record | <clean | open findings> for this content |
| Hand-off checklist | <n> PASS · <n> N/A · <n> FAIL |
| CI's commands | <which ran, passing or not> |
| Receipt | <written | refused: why> |
```

### After the reviewer comments

- Sort each comment the reviewer makes:

- **Covered:** a rule already said it. The pass missed it, so fix the check that should have caught it: a sweep that didn't list the construct, a fix whose test passed with the fix broken, a vague box, a rule with no box, a checklist item that wasn't walked. Don't add a second rule.
- **New:** no rule said it. It becomes a lesson in the rules, with a box on their checklist.
- **Disagreement:** runs or gates decided it both ways. It is settled once (by the user only when it is a product, scope or irreversible call), and it becomes a rule in the repo's `.claude/review-conventions.md` (kc-code-review's rule for contested calls).

- [ ] Check a requested change like your own before writing it: where it puts code or a test, what it widens, and what it breaks (a rename colliding with an existing name, a guard that blocks a valid state, a "next to X" when X is misplaced). Following a comment word for word is not a defence, and a request that fails the check is answered with why and what you did instead.

- The goal is that "covered" stays at zero. Keep the count so a slipping pass shows as a number: after sorting a reviewer's round, record it with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-tally.sh" add <pr-url> <covered> <new> <disagreement>`, and `review-tally.sh report` gives the totals per month. A month whose "covered" rises means the pass is missing what its rules already say; fix the checks before adding rules. A revert is the plainest miss of all: `review-tally.sh reverts <repo-dir> [<since>]` lists the merged PRs reverted on the default branch, and the look-back sorts each one like a reviewer comment (covered, new or disagreement) before it is counted.