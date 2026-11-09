---
name: kc-ready-for-review
description: The one review-and-QA pass on your own PR before it goes to a human reviewer. Runs kc-code-review, the project's hand-off checklist and QA once, then you write the fixes from the findings, each held by a test, lint and types, and hand whatever is still open to the user. Fix code gets no further gate round, so the pass always ends. Writes the PR's merge-risk section. Ends in a receipt for the head commit, which the kc-gates hand-off guard requires before `gh pr ready`, a ready `gh pr create` or adding a reviewer. Use when work is about to go to review ("ready for review", "send it to review", "request a review", "move the ticket to review"), or when the guard blocks a hand-off. Not after each commit or push.
---

# Ready for review

The reviewer should find nothing the project's rules already say. This pass is where those rules are applied: once per PR, right before a person reviews it, never per commit or push.

The pass runs the gates once and ends. A second round mostly found code written while fixing the first, and a fresh round of a dozen gates nearly always finds something, so review, fix, review again has no end. Each cause has its own answer here instead of another round: scripts list what a gate would otherwise sample (the sweeps, the mutation run) and the gate judges each listed item; one writer, you, writes every fix that isn't mechanical, having read every finding and the code; and each fix is held by mechanical proof (a test that fails when the fix is broken, lint, types), never by another gate round, which would find something in the fixes, ask for more fixes, and never end.

## When it runs

- **Once, at hand-off:** before marking a PR ready, opening it ready, requesting a reviewer, or moving its ticket to review. For a stack, once per PR, each against its own base.
- **Not before:** commits and pushes on the way there run nothing, and neither does showing the person the change for approval: no `kc-code-review` fan-out and no QA walk while the code is still being built, since this pass repeats both. Run tests, lint and types as you work, as always. The order of work is in the working agreement's "Order of work on a task": assess, approval, build, draft PR, this pass, ready.
- **Not again for fixes.** Fixes a reviewer's comments ask for are written as step 6 writes them and recorded with `--after` (step 9). A new pass runs only when the PR gains work it didn't have (a new feature, a new approach).

## The pass

### Before round 1

- **Size the pass, by script, never by judgment.** Gather the diff (`gather-review.sh --branch <base> --out-dir <dir>`) and run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/pass-size.sh" <dir>/review.diff <dir>/changed-files.txt` from the repo root. Follow its `MUTATION=` line, copy its `SIZE=` line and reasons into the report and the receipt (`--size`), and its `risk:` lines into the Risk section; never override them. A repo lists paths it treats as sensitive beyond the built-in ones in `.claude/sensitive-paths.txt`, one extended regex per line. Every size gets one gate round: the rounds after it found mostly code written while fixing. Example: a two-file fix to a form's validation that went through four review rounds and two app walks, two-thirds of the task's time, when one round would have caught everything they found.
- **The mutation sweep runs once,** in round 1, and only when `pass-size.sh` says `MUTATION=run` (an added code line has a condition or branch); a diff with no new branch has nothing for it to break.
- The tree is clean and HEAD is the branch's last commit, the one the PR shows or will show. The review reads the local head in branch mode against the PR's base (`gather-review.sh --branch <base> --out-dir <dir>`), and nothing is pushed until the fixes are committed.
- **Keep the pass folder.** The receipt (step 8) is written only when it shows the pass ran. Make one folder for the pass and gather the review into `round-1/` in it, a `gather-review.sh --out-dir`. Save every block its agents return, verbatim (never a summary), to `round-1/verdicts/`, one file per gate (`verdicts/<gate>.txt`), and your `SCOPE:` block to `verdicts/scope.txt`. A block sent back for its per-box breakdown is replaced by the one that came back.
- The test command: the specs that cover the changed files, as the project runs them, narrowed so one run takes seconds where it can (a page only an end-to-end spec covers takes that spec), plus the install command when a fresh checkout needs one. A review that runs the mutation sweep (see above) starts it with this command (`surviving-mutants.sh` on the whole diff, one run per area) before dispatching its gates, and dispatches the testing gate with the output when the sweep is done. The sweep runs in a throwaway checkout and the gates run no end-to-end specs, so nothing else holds the suite's port meanwhile.

### Round 1

1. **Review the code:** run `kc-gates:kc-code-review` on the whole diff, gathered into the pass folder's `round-1/`, with its optional inputs, fixes and, when the sweep ran, the mutation output (its Step 3). It includes the project-conventions gate, which grades the repo's own `.claude/review-conventions.md`, its `SCOPE:` block and the verification gate: none is skipped to save time, and the receipt checks that each is saved. Note round 1's head, `HEAD_SHA` in its `meta.env`.
2. **Check the hand-off:** grade every box in the repo's `.claude/hand-off-checklist.md` against the PR as it will be read, not the diff: its title and description, the linked ticket, the paired or stacked PRs, the flags and tasks it names. No such file: check the description against the repo's PR template and say so.
   - **Merge risk.** Whatever the checklist says, the description carries a short **Risk** section, written from the diff you already have, with no agent dispatched for it:
     - **Impact:** what the change reaches, starting from `pass-size.sh`'s `risk:` lines, and naming any sensitive path (authentication, permissions, payments, a shared contract or public API, data deletion).
     - **Rollback:** a two-way door (reverting the PR undoes it) or a one-way door (a column or table dropped, data backfilled or deleted, messages or charges sent), with what undoing a one-way door takes.
     - **Detection:** how a failure would show (error reporting, logs, a failing job), or that nothing would.

     High impact with a one-way door, or a new path whose failure nothing would report, goes to the user before the pass ends, with the fix: split the risky part into its own stacked PR, add error reporting on the new path, or drop changes the issue didn't ask for. Example: a migration that drops a column shipped in the same PR as the code that stops reading it, so a revert of the code finds the column gone.
3. **QA:** for a change a person sees, walk it in the running app with `kc-verify:kc-ui` (how it looks), `kc-verify:kc-ux` (whether a person can use it) and the project's QA rules, every state the change reaches, as every audience that reaches it: each role it serves, and signed out in a fresh browser profile for a page a visitor opens without an account. A `risk: public or guest path` line from `pass-size.sh` makes the signed-out walk required, even when the change is about something else, since a shared component that gains a public use breaks for the visitor while every signed-in walk passes. For example, a review passed a footer change made for a public order page, walked only signed in; signed-out visitors were sent to sign-in. For one nobody sees, run the specs that cover it and exercise the endpoint, job or admin screen it changed.
   - **Evidence for the reviewer.** For a change a person sees, keep one "after" screenshot per distinct flow the change reaches (not one per state walked), and a "before" one where the change alters an existing screen and the issue's own report doesn't already show it. Give them to the user for the description, and say which flow each shows; a recording only when the issue or the repo asks for one.
4. **Settle the approach first.** A finding that changes the shape of the change (scope §G5, simplicity §P16) is the user's call. If they take it, drop every other edit, since each was written against the old shape, make the change, and run round 1 again on the new code, once.
5. **Turn the findings into lessons.** The findings are instances; what the PR gets wrong is a short list of kinds. Write that list before anything is fixed: one line per kind of mistake, as a do or don't that holds beyond the line it was found on ("a comment that says what another unit does is checked against that unit", "both sides of every condition have a test"). Several findings of one kind are one line. Every fix you write is checked against it, so a fix doesn't repeat a kind the PR already makes. No agent is sent to find the rest of a kind: the sweeps list what a script can find, and the gates judged every item on them.
6. **Write the fixes yourself.** You have read every finding and the code; a gate has read one topic. Before writing anything, sort the findings:
   - **Fix only what lets something wrong through:** a wrong result or state, data lost or exposed, a crash, a use the change breaks, or a rule of the checklist broken in code that ships. A finding kc-code-review marks `(fails safe)`, one that only refuses too much (a guard that blocks an input nobody sends, an extra check whose worst outcome is an error message or a no-op), goes on the open list unfixed, with its reason. Example: a pass that hardened a guard script against path shapes no caller produces, and each hardening refused a real command the next round had to fix.
   - **Mechanical fixes as written:** a gate's edit that only renames, deletes or moves lines is applied as written, all of a finding's edits or none. `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-gate-fixes.sh" <pass>/round-1/verdicts` lists every edit that is more than that; each one it lists is read as a description of the fix, never applied.
   - **Every other fix is yours to write,** from the finding's `FIX:` line (what must be true after it, and every place), checked against the lessons. Before writing it, run `trace-uses.sh --symbols <the names the fix changes>` (with `--also` for a sibling repo), give each use a verdict (breaks, behaviour changes, fine), and fix or ask about each one the fix breaks: a fix's damage lands where the changed thing is used.
   - **A test per fix that changes behaviour,** one that fails when the fix is broken: put the old line back, run the test, see it fail, restore the fix. A test that still passes doesn't hold the fix; rewrite it. A rename or deletion is held by lint and types.
   - **Record what became of each finding** in the pass folder's `fixes.txt`, one tab-separated line each: `fixed<TAB><finding><TAB><test file>`, `mechanical<TAB><finding>` (a fix that changes no behaviour: a rename, deletion, move or comment), or `open<TAB><finding><TAB><fails safe | needs a decision | pre-existing>`. The receipt reads it: a fix must name a test file the fix commits added or changed, and the open lines must number `--open`.
   - **Ask in round 1, don't pick,** when a finding needs a decision: two findings ask for conflicting fixes (kc-code-review's rule for conflicting fixes), the fix changes behaviour the ticket didn't ask for, the fix reaches past the change (a file round 1's diff doesn't touch, a shared helper or script other code uses, or a kind of risk `pass-size.sh` lists that round 1's diff didn't have), or the rule looks wrong for this case. A wider fix goes to the user with the files it adds and the other way that stays inside the diff; keep their answer word for word, since the receipt asks for it (`--scope-approved`). Example: a fix to one receipt's date format rewritten into the formatter every page of the shop shares, which changed pages no finding had asked about. Each answer to a conflict becomes a rule in the repo's `.claude/review-conventions.md`, created when missing, before the edits are applied. The question names what is missing for the decision: the product call the issue leaves open, or the two rules that disagree, citing both. It carries only checked facts: what it says the person will see is measured as kc-code-review's lead-not-fact box (c) asks, in the running app or against the real formatting code, and the question's own wording is checked like a report line, since the user decides on it. Example: a gate's "a free item will show $0.00" put to the user as a choice, when the formatter printed nothing for 0, so the approved edit changed nothing on screen.
   - A finding that reverses a call the repo or an earlier run settled is the user's (kc-code-review's rule for contested calls), not an open finding.
   - A pre-existing finding isn't fixed in this PR. A hand-off or QA finding is fixed as it says, held the same way.
   - Then run the project's typecheck, lint, each fix's test and the tests of the files its uses are in. A fix that breaks them is rewritten once; still broken, it goes to the user as a decision. Commit, and check that HEAD moved and the tree is clean. Walk QA again on what the fixes changed that a person sees, and grade the hand-off checklist again if the fixes changed the PR's text.

   Don't rebase or reset the branch during the pass: the receipt reads the fixes as the commits since round 1's head, and refuses a head that doesn't descend from it.
7. **Stop.** The fixes get no gate round: their test, lint and types are their proof, and a gate round on them would find something in its own fixes, and so on. Each finding still open goes to the user as one line with its proposed fix and why it is open: fails safe, needs a decision, or pre-existing. The user picks.

   Example: a pass whose round 2 raised 19 items, 16 of them on lines the author wrote while fixing round 1; and a pass that ended by asking for one more round on its newest code.

### Receipt

8. Push, check that the PR's head is HEAD (`gh pr view --json headRefOid`), then write the receipt for it. When the branch on the remote has moved but the pull request still shows the old head after a minute, the forge didn't apply the push to the pull request: save its base again unchanged (`gh api -X PATCH repos/<owner>/<repo>/pulls/<n> -f base=<base>`) and check again, rather than waiting it out. A push refused with a server-side error, not a rejection of the commits, is retried once.

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/ready-receipt.sh" write <full-sha> --rounds 1 --open <count> --size <small|full> --pass <pass-folder> [--scope-approved "<the user's words>"]
   ```

   Run it from the repo root. It refuses, and says what is missing, unless `round-1/` has a block for every gate `select-gates.sh` lists for its diff, which it makes again from git as `BASE...HEAD_SHA` in its `meta.env` (project-conventions only when the repo had `.claude/review-conventions.md` at that head), a verification block and a `SCOPE:` block marking §G1 to §G5 once each with evidence; unless `fixes.txt` has a line for each finding when there are fix commits or open findings, each fix naming a test those commits changed; unless the user's words approve fixes that touch a file outside round 1's diff that isn't a test, or bring a kind of risk it didn't have; and unless the receipt's commit descends from round 1's head. It refuses `--rounds 2`. It checks that the pass's records are there and well formed, not that they are right. Never write a block yourself to get past it: run what is missing.

9. **Fixes after the pass,** the ones the user picks from the open list or a reviewer's comments ask for: write each as step 6 does (uses checked, a test that fails when it is broken, lint and types), push, and write `ready-receipt.sh write <new-sha> --after <pass-sha>`, which refuses a commit that doesn't descend from the pass. No gate round runs on them. New work after the pass needs a new pass.

## Gate checklist

What the pass must show before its receipt. Each box is held by a script: the receipt refuses a pass that breaks it, or a check lists what breaks it.

- [ ] §H1 One gate round: the pass ran `kc-code-review` once on the whole diff, and no gate ran on code written while fixing. The receipt is written with `--rounds 1`; it refuses a second round. (N/A: never)
- [ ] §H2 One writer: only a gate's mechanical edits (a rename, a deletion, a move) were applied as written, the ones `check-gate-fixes.sh` prints as `apply`; every edit it prints as `write` was written by you from the finding. (N/A: round 1 found nothing, or the gates wrote no edits)
- [ ] §H3 Only what lets something wrong through was fixed: each finding that only refuses too much or fails safe is an `open` line in `fixes.txt` with its reason (fails safe, needs a decision, pre-existing), and the open lines number the receipt's `--open`. (N/A: round 1 found nothing)
- [ ] §H4 Each fix that changes behaviour has a test that fails when the fix is broken, and its `fixed` line in `fixes.txt` names that test file, one the fix commits added or changed; a fix that changes no behaviour is a `mechanical` line. (N/A: no fix commits)
- [ ] §H6 Every audience was walked: each role the change serves, and, for each `risk: public or guest path` line, the page signed out in a fresh browser profile, with what loaded and what was asked of the visitor. (N/A: no change a person sees)
- [ ] §H5 Fixes after the pass (the user's picks, a reviewer's comments) were written the same way and recorded with `--after`, with no gate round on them; only new work got a new pass. (N/A: nothing changed after the pass)

## The guard

`scripts/guard-hand-off.sh` blocks `gh pr ready`, `gh pr create` without `--draft` or with a reviewer, `gh pr edit --add-reviewer` and a write to a PR's `requested_reviewers` until the PR's head commit has a receipt.

A repo whose hand-off checklist opens with front matter holding `drafts: true` wants it walked before any PR opens, draft or not. There, a draft `gh pr create` is blocked too until its head commit has a receipt: grade every box of the checklist alone against the PR as it will be read, fix what fails, push, and write `ready-receipt.sh write <full-sha> --checklist`. The full pass still runs before the PR is marked ready: a receipt for the checklist alone opens only a draft, and the guard wants a pass receipt for every hand-off. A hand-off done in a browser or through another tool isn't seen; run the pass before those too.

When the user says to skip the pass for a PR, prefix that command with `KC_READY_SKIP=1`. Never add it on your own, and never to get past a pass that found something.

## Report

Chat, short:

```
### Ready for review: <PR title>
**Head:** `<short-sha>` · **Size:** <small|full> · **Rounds:** <1|2> · **Open:** <n>
**Risk:** <impact> · <two-way|one-way door> · <how a failure shows>

| Check | Round 1 | Fixes |
|-------|---------|-------|
| Code review | <n> found · <n> fails safe · <n> asked | <n> mechanical · <n> written · <n> open |
| Proof | — | <n> tests, each failed with its fix broken · lint · types |
| Lessons | <n> kinds | <n> fixes rewritten to avoid a kind |
| Mutation | <n> mutants · <n> survived · or "no new branch" | — |
| Hand-off checklist | … | … |
| QA | <what was walked> | <what the fixes changed> |

**Open (your call):**
- `<file>:L<n>` <finding> (<fails safe | needs a decision | pre-existing>). Fix: <one line>.
```

## After the reviewer comments

Sort each comment the reviewer makes:

- **Covered:** a rule already said it. The pass missed it, so fix the check that should have caught it: a sweep that didn't list the construct, a fix whose test passed with the fix broken, a vague box, a rule with no box, a checklist item that wasn't walked. Don't add a second rule.
- **New:** no rule said it. It becomes a lesson in the rules, with a box on their checklist.
- **Disagreement:** runs or gates decided it both ways. The user settles it once, and it becomes a rule in the repo's `.claude/review-conventions.md` (kc-code-review's rule for contested calls).

The goal is that "covered" stays at zero. Keep the count so a slipping pass shows as a number: after sorting a reviewer's round, record it with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-tally.sh" add <pr-url> <covered> <new> <disagreement>`, and `review-tally.sh report` gives the totals per month. A month whose "covered" rises means the pass is missing what its rules already say; fix the checks before adding rules. A revert is the plainest miss of all: `review-tally.sh reverts <repo-dir> [<since>]` lists the merged PRs reverted on the default branch, and the look-back sorts each one like a reviewer comment (covered, new or disagreement) before it is counted.
