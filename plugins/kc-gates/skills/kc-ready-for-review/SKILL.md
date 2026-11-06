---
name: kc-ready-for-review
description: The one review-and-QA pass on your own PR before it goes to a human reviewer. Runs kc-code-review, the project's hand-off checklist and QA, applies the fixes the gates write, checks those fixes once, re-reviews once, and hands whatever is still open to the user instead of looping: one round for a small, low-risk change, otherwise two, with a check of round 1's fixes between them. Writes the PR's merge-risk section. Ends in a receipt for the head commit, which the kc-gates hand-off guard requires before `gh pr ready`, a ready `gh pr create` or adding a reviewer. Use when work is about to go to review ("ready for review", "send it to review", "request a review", "move the ticket to review"), or when the guard blocks a hand-off. Not after each commit or push.
---

# Ready for review

The reviewer should find nothing the project's rules already say. This pass is where those rules are applied: once per PR, right before a person reviews it, never per commit or push.

Round 2 is there to confirm, not to discover. What it used to find traces to two causes: code written while fixing round 1, which no gate had seen, and constructs round 1 sampled instead of listing. So the gates write the fixes, round 1's findings become a short list of the kinds of mistake this PR makes, which every fix is checked against and the rest of the diff is searched for, one check reviews the fixes before round 2, and scripts list what a gate would otherwise sample (the sweeps, and the testing gate's mutation run).

## When it runs

- **Once, at hand-off:** before marking a PR ready, opening it ready, requesting a reviewer, or moving its ticket to review. For a stack, once per PR, each against its own base.
- **Not before:** commits and pushes on the way there run nothing, and neither does showing the person the change for approval: no `kc-code-review` fan-out and no QA walk while the code is still being built, since this pass repeats both. Run tests, lint and types as you work, as always. The order of work is in the working agreement's "Order of work on a task": assess, approval, build, draft PR, this pass, ready.
- **Again only after a reviewer's round** that changed the code, on the new head.

## The pass

### Before round 1

- **Size the pass, by script, never by judgment.** Multi-round review pays off on large changes; on a small one it costs more than it finds. Gather the diff (`gather-review.sh --branch <base> --out-dir <dir>`) and run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/pass-size.sh" <dir>/review.diff <dir>/changed-files.txt` from the repo root. Follow its `SIZE=` and `MUTATION=` lines and copy its reasons into the report; never override them. A repo lists paths it treats as sensitive beyond the built-in ones in `.claude/sensitive-paths.txt`, one extended regex per line.
  - **Small** (`SIZE=small`): at most 5 changed files and 200 changed lines, counting neither tests nor generated or locale files, and no sensitive path: no schema change or data migration, nothing in authentication, permissions, payments or a shared contract, nothing that deletes a file or data. It runs round 1 only: steps 1, 2, 3 and 6, with step 5's list written but no agent dispatched to find the rest, then the typecheck, lint and specs, and QA on what the fixes changed. No fix check and no round 2; the receipt says `--rounds 1 --size small`.
  - **Full** (`SIZE=full`): anything else, the pass as written below, and the receipt says `--size full`.

  Example: a two-file fix to a form's validation that went through four review rounds and two app walks, two-thirds of the task's time, when one round would have caught everything they found.
- **The mutation sweep runs once,** in round 1, and only when `pass-size.sh` says `MUTATION=run` (an added code line has a condition or branch); a diff with no new branch has nothing for it to break. The fix check runs it again only when step 6 added or changed a test, and round 2 doesn't run it.
- The tree is clean and HEAD is the branch's last commit, the one the PR shows or will show. Every review in the pass reads the local head in branch mode against the PR's base, each into its own directory (`gather-review.sh --branch <base> --out-dir <dir>`), and nothing is pushed until round 2 is done.
- **Keep the pass folder.** The receipt (step 11) is written only when it shows the pass ran. Make one folder for the pass and gather each review into its own folder in it: `round-1/`, `fix-check/` and `round-2/`, each a `gather-review.sh --out-dir`. Save every block a review's agents return, verbatim (never a summary), to that review's `verdicts/` folder, one file per gate (`verdicts/<gate>.txt`), and your `SCOPE:` block to `verdicts/scope.txt`. A block sent back for its per-box breakdown is replaced by the one that came back.
- The test command: the specs that cover the changed files, as the project runs them, narrowed so one run takes seconds where it can (a page only an end-to-end spec covers takes that spec), plus the install command when a fresh checkout needs one. A review that runs the mutation sweep (see above) starts it with this command (`surviving-mutants.sh` on the whole diff, one run per area) before dispatching its gates, and dispatches the testing gate with the output when the sweep is done. The sweep runs in a throwaway checkout and the gates run no end-to-end specs, so nothing else holds the suite's port meanwhile.

### Round 1

1. **Review the code:** run `kc-gates:kc-code-review` on the whole diff, gathered into the pass folder's `round-1/`, with its optional inputs, edits and, when the sweep ran, the mutation output (its Step 3). It includes the project-conventions gate, which grades the repo's own `.claude/review-conventions.md`, its `SCOPE:` block and the verification gate: none is skipped to save time, and the receipt checks that each is saved. Note round 1's head, `HEAD_SHA` in its `meta.env`.
2. **Check the hand-off:** grade every box in the repo's `.claude/hand-off-checklist.md` against the PR as it will be read, not the diff: its title and description, the linked ticket, the paired or stacked PRs, the flags and tasks it names. No such file: check the description against the repo's PR template and say so.
   - **Merge risk.** Whatever the checklist says, the description carries a short **Risk** section, written from the diff you already have, with no agent dispatched for it:
     - **Impact:** what the change reaches, starting from `pass-size.sh`'s `risk:` lines, and naming any sensitive path (authentication, permissions, payments, a shared contract or public API, data deletion).
     - **Rollback:** a two-way door (reverting the PR undoes it) or a one-way door (a column or table dropped, data backfilled or deleted, messages or charges sent), with what undoing a one-way door takes.
     - **Detection:** how a failure would show (error reporting, logs, a failing job), or that nothing would.

     High impact with a one-way door, or a new path whose failure nothing would report, goes to the user before the pass ends, with the fix: split the risky part into its own stacked PR, add error reporting on the new path, or drop changes the issue didn't ask for. Example: a migration that drops a column shipped in the same PR as the code that stops reading it, so a revert of the code finds the column gone.
3. **QA:** for a change a person sees, walk it in the running app with `kc-verify:kc-ui` (how it looks), `kc-verify:kc-ux` (whether a person can use it) and the project's QA rules, every state the change reaches. For one nobody sees, run the specs that cover it and exercise the endpoint, job or admin screen it changed.
   - **Evidence for the reviewer.** For a change a person sees, keep one "after" screenshot per distinct flow the change reaches (not one per state walked), and a "before" one where the change alters an existing screen and the issue's own report doesn't already show it. Give them to the user for the description, and say which flow each shows; a recording only when the issue or the repo asks for one.
4. **Settle the approach first.** A finding that changes the shape of the change (scope §G5, simplicity §P16) is the user's call. If they take it, drop every other edit, since each was written against the old shape, make the change, and run round 1 again on the new code, once.
5. **Turn the findings into lessons.** The findings are instances; what the PR gets wrong is a short list of kinds. Write that list before anything is fixed, and use it for the rest of the pass:
   - One line per kind of mistake, as a do or don't that holds beyond the line it was found on: "a comment that says what another unit does is checked against that unit", "both sides of every condition have a test", "a test helper's name says which session it fakes". Several findings of one kind are one line.
   - **Find the rest of each kind.** Dispatch one agent with the lessons, the whole diff and the repo root, under the gates' rules (it changes nothing in the checkout and runs no end-to-end specs). For each lesson it lists every other line of the diff of that kind as a finding with edits in kc-code-review's format. Verify them as gate findings; they join round 1's.
   - **Check every edit against the lessons before it lands.** This is yours, since you have read every finding. An edit that repeats a listed kind (a comment about another unit that the unit doesn't bear out, a test of one side of a condition, a helper the list rules out) is rewritten or asked about, not applied. So are two gates' edits that repeat a kind together, such as the same setup written into two tests.
   - Every later review in the pass gets the list as kc-code-review's lessons input, and a new kind any of them finds adds a line.

   Example: a pass whose round 2 found a false comment, a one-sided test and an ambiguous helper name, each a kind round 1 had flagged on other lines.
6. **Apply the fixes as the gates wrote them,** once they pass the lessons. Apply each verified finding's edits (kc-code-review's lead-not-fact check), all of a finding's edits or none.
   - **Ask in round 1, don't pick,** when a finding needs a decision: two gates' edits touch the same lines (kc-code-review's rule for conflicting fixes), the fix changes behaviour the ticket didn't ask for, the fix reaches past the change (a file round 1's diff doesn't touch, a shared helper or script other code uses, or a kind of risk `pass-size.sh` lists that round 1's diff didn't have), or the rule looks wrong for this case. A wider fix goes to the user with the files it adds and the other way that stays inside the diff; keep their answer word for word, since the receipt asks for it (`--scope-approved`). Example: a fix to one receipt's date format rewritten into the formatter every page of the shop shares, which changed pages no finding had asked about. Each answer to a conflict becomes a rule in the repo's `.claude/review-conventions.md`, created when missing, before the edits are applied. The question names what is missing for the decision: the product call the issue leaves open, or the two rules that disagree, citing both. It carries only checked facts: what it says the person will see is measured as kc-code-review's lead-not-fact box (c) asks, in the running app or against the real formatting code, and the question's own wording is checked like a report line, since the user decides on it. Example: a gate's "a free item will show $0.00" put to the user as a choice, when the formatter printed nothing for 0, so the approved edit changed nothing on screen.
   - An edit whose text is no longer in the file is not sent back: apply what it meant by hand, or ask, and list it either way.
   - A pre-existing finding isn't fixed in this PR. A hand-off or QA finding is fixed as it says.
   - Then run the project's typecheck, lint and the specs the fixes touch. A finding whose edits break them goes to the user as a decision. Commit, and check that HEAD moved and the tree is clean.
7. **Check the fixes once,** before round 2. They are new code that no gate has seen.
   - Gather the fix delta into the pass folder, `gather-review.sh --branch <round-1 head> --out-dir <pass>/fix-check`, and save its gates' blocks to `fix-check/verdicts/`. Don't rebase or reset the branch during the pass: the receipt reads the fixes as the commits since round 1's head, and refuses a head that doesn't descend from it. If the base must come in, merge it and run round 1 again.
   - Run kc-code-review's phase-1 gates on it with the whole diff beside it, the lessons and its optional inputs; when step 6 added or changed a test, the mutation sweep runs on the whole diff, so that test is shown to catch its mutant. Of the scope checks only §G2 applies, read as "the fixes do only what round 1's findings asked"; the verification phase doesn't run.
   - Grade the hand-off checklist again if round 1 changed the PR's text or ticket, and walk QA on what the fixes changed that a person sees.
   - Apply what it finds as in steps 5 and 6, each edit checked against the lessons, run the checks and commit. It runs once: round 2 reviews what it applied.

   Example: a pass whose round 2 raised 19 items, 16 of them on lines the author wrote while fixing round 1, and none on lines a gate wrote that the author applied as written.

When round 1 finds nothing, there is no fix check and no round 2.

### Round 2

8. **Re-review once:** run steps 1 and 2 again on the whole diff at the new head, gathered into `round-2/`, with the lessons, and QA again what the fixes touched.
9. **Settle disagreements.** A round-2 finding that reverses a call made earlier in the pass on the same construct (a gate passed it, wrote it or asked for it the other way), or two gates' findings that pull one construct opposite ways, is not an open finding. Put both sides to the user as one choice and record the answer in the repo's `.claude/review-conventions.md`, creating the file when the repo has none (kc-code-review's rule for contested calls), so later runs hold the code to it instead of judging it afresh.

   Example: a pass where one gate split a request-body read into steps, the next asked for the one-line form back, and a third run asked for a literal union that an earlier run had praised.
10. **Stop.** Fix nothing further in this pass. Each finding still open goes to the user as one line with its proposed fix, whether its kind is on the lessons list, and where it sits: on a line round 1's fixes or the fix check changed (the added lines of the delta from round 1's head, `added-lines.sh`), on a line round 1 passed, or in pre-existing code. The user picks.

### Receipt

11. Push, check that the PR's head is HEAD (`gh pr view --json headRefOid`), then write the receipt for it. When the branch on the remote has moved but the pull request still shows the old head after a minute, the forge didn't apply the push to the pull request: save its base again unchanged (`gh api -X PATCH repos/<owner>/<repo>/pulls/<n> -f base=<base>`) and check again, rather than waiting it out. A push refused with a server-side error, not a rejection of the commits, is retried once.

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/ready-receipt.sh" write <full-sha> --rounds <1|2> --open <count> --size <small|full> --pass <pass-folder> [--scope-approved "<the user's words>"]
   ```

   Run it from the repo root. It refuses, and says what is missing, unless each round's folder has a block for every gate `select-gates.sh` lists for its diff, which it makes again from git as `BASE...HEAD_SHA` in the round's `meta.env` (project-conventions only when the repo had `.claude/review-conventions.md` at that round's head, since a pass can add the file), a verification block and a `SCOPE:` block marking §G1 to §G5 once each with evidence, and the fix check's folder (two rounds) a block for every gate it lists; unless the user's words approve fixes that touch a file outside round 1's diff or bring a kind of risk it didn't have; and unless the receipt's commit descends from round 1's head and, after two rounds, is round 2's head. It checks that the pass's records are there and well formed, not that they are right. Never write a block yourself to get past it: run what is missing.

12. **Fixes the user picks** from the open list: apply their edits, check them against the lessons and as in step 7 against the pass's head, run the specs and lint they touch, push, and write `ready-receipt.sh write <new-sha> --after <pass-sha>`, which refuses a commit that doesn't descend from the pass. That is not a third round. Any other change after the pass needs a new pass.

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

| Check | Round 1 | Fix check | Round 2 |
|-------|---------|-----------|---------|
| Code review | <n> found · <n> applied as written · <n> by hand · <n> asked | <n> found, applied | PASS · <n> open |
| Lessons | <n> kinds · <n> more found · <n> edits held back | <n> new kinds | <n> open of a listed kind |
| Mutation | <n> mutants · <n> survived · or "no new branch" | <n> survived · or "no test changed" | — |
| Hand-off checklist | … | … | … |
| QA | <what was walked> | … | … |

**Open (your call):**
- `<file>:L<n>` <finding> (<on a fix line | missed by round 1 | pre-existing>; <a listed kind | a new kind>). Fix: <one line>.
```

## After the reviewer comments

Sort each comment the reviewer makes, and each finding round 2 left open:

- **Covered:** a rule already said it. The pass missed it, so fix the check that should have caught it: the lessons step, for a kind it listed but didn't find everywhere or let through in an edit, the fix check, a sweep that didn't list the construct, a vague box, a rule with no box, a checklist item that wasn't walked. Don't add a second rule.
- **New:** no rule said it. It becomes a lesson in the rules, with a box on their checklist.
- **Disagreement:** runs or gates decided it both ways. The user settles it once, and it becomes a rule in the repo's `.claude/review-conventions.md` (step 9).

The goal is that "covered" stays at zero, and that round 2 leaves at most two items, none 🟠 or 🔴. Keep the count so a slipping pass shows as a number: after sorting a reviewer's round, record it with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-tally.sh" add <pr-url> <covered> <new> <disagreement>`, and `review-tally.sh report` gives the totals per month. A month whose "covered" rises means the pass is missing what its rules already say; fix the checks before adding rules. A revert is the plainest miss of all: `review-tally.sh reverts <repo-dir> [<since>]` lists the merged PRs reverted on the default branch, and the look-back sorts each one like a reviewer comment (covered, new or disagreement) before it is counted.
