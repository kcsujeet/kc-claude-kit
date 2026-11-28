# Self-correct detail

The wording behind each step of `SKILL.md`. Read the section a step or box points to.

- The reviewer should find nothing the project's rules already say. This skill applies those rules to your own change: one review and QA of the whole change, then fixes in rounds, and nothing in between. An expensive check whose result later edits would throw away runs on the finished work.

- The rounds converge or stop. Round 1 reviews the whole change. Each later round reviews only the fixes since the round before, plus every use of what those fixes changed (`trace-uses.sh`), so lines a round passed are not read again and each round has less to read. Each round's fixes must be smaller than the round before's, and past round 3 the approach goes back to the person. Scripts still list what a gate would otherwise sample, one writer (you) writes every fix that isn't mechanical, and each fix is held by a test that fails when it is broken. Code-review findings and QA-walk findings are fixed the same way.

### Before round 1

- **Size the pass, by script, never by judgment.** Gather the diff (`gather-review.sh --worktree origin/<base> --out-dir <dir>`, after `git fetch origin`: the working tree, untracked files included, against the remote-tracking ref of the PR's base, never a local branch that may be behind it; a clean tree gives the branch's diff) and run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/pass-size.sh" <dir>/review.diff <dir>/changed-files.txt` from the repo root. Follow its `MUTATION=` line, copy its `SIZE=` line and reasons into the report and the record (`--size`), and its `risk:` lines into the report (the Risk section of the description is `kc-ready-for-human-review`'s); never override them. A repo lists paths it treats as sensitive beyond the built-in ones in `.claude/sensitive-paths.txt`, one extended regex per line. Every size gets the same rounds: round 1 on the whole diff, later rounds only on the fixes. A `BASE_STALE=` line in `meta.env` means the local base is behind its remote: throw that gather away and run it again against the ref the line names before anything is sized (a local default branch weeks behind its remote sized a two-file change as a few hundred files, with risk lines for areas the change never touched). Example: a two-file fix to a form's validation that went through four review rounds and two app walks, two-thirds of the task's time, when one round would have caught everything they found.
- **The mutation sweep runs once,** in round 1, and only when `pass-size.sh` says `MUTATION=run` (an added code line has a condition or branch); a diff with no new branch has nothing for it to break.
- **The content is what is reviewed, not a commit.** `gather-review.sh --worktree` hashes the working tree through a temporary index (`tree-hash.sh`) and writes the hash to `meta.env` as `TREE=`. Uncommitted edits and untracked files are read; nothing is staged, stashed or committed, and fixes stay in the working tree. The record is keyed on that hash, so committing the same content later, amending it or rebasing it leaves the record valid, and changing it makes the record not match until the delta is reviewed.
- **Keep the pass folder.** The record is written only when it shows the rounds ran. Make one folder for the pass, outside any checkout (`${TMPDIR:-/tmp}/kc-pass-<tree>`, never under the repo or its `.git`: the first Read of a file in a folder loads that folder's CLAUDE.md and path-scoped rules, a second copy of the repo's), and gather the review into `round-1/` in it, a `gather-review.sh --out-dir` (it warns when the folder is inside a checkout). Save every block its agents return, verbatim (never a summary), to `round-1/verdicts/`, one file per gate (`verdicts/<gate>.txt`), and your `SCOPE:` block to `verdicts/scope.txt`. A block sent back for its per-box breakdown is replaced by the one that came back.
- The test command: the specs that cover the changed files, as the project runs them, narrowed so one run takes seconds where it can (a page only an end-to-end spec covers takes that spec), plus the install command when a fresh checkout needs one. A review that runs the mutation sweep (see above) starts it with this command (`surviving-mutants.sh` on the whole diff, one run per area) before dispatching its gates, and dispatches the testing gate with the output when the sweep is done. The sweep runs in a throwaway checkout and the gates run no end-to-end specs, so nothing else holds the suite's port meanwhile.



### Round 1

1. **Review the code and walk it:** run `kc-gates:kc-code-review` on the whole diff, gathered into the pass folder's `round-1/`, with its optional inputs, fixes and, when the sweep ran, the mutation output (its Step 3). It includes the project-conventions gate, which grades the repo's own `.claude/review-conventions.md`, its `SCOPE:` block and the verification step (`verify-gate-blocks.sh`, then the verification gate for what it can't judge): none is skipped to save time, and the receipt checks that each is saved. Note round 1's content, `TREE` in its `meta.env`.

   - **QA is `kc-code-review`'s walk** (see its "only QA" rule): every state, every audience, one "after" screenshot per flow, saved as its `walk-receipt.tsv`. Give the screenshots to the person for the description. Nothing is walked here twice; a QA finding is a finding like any other and is fixed in the same rounds.
2. **Settle the approach first.** A finding that changes the shape of the change (scope §G5, simplicity §P16) is the user's call. If they take it, drop every other edit, since each was written against the old shape, make the change, and run round 1 again on the new code, once.

3. **Turn the findings into lessons.** The findings are instances; what the PR gets wrong is a short list of kinds. Write that list before anything is fixed: one line per kind of mistake, as a do or don't that holds beyond the line it was found on ("a comment that says what another unit does is checked against that unit", "both sides of every condition have a test"). Several findings of one kind are one line. Every fix you write is checked against it, so a fix doesn't repeat a kind the PR already makes. No agent is sent to find the rest of a kind: the sweeps list what a script can find, and the gates judged every item on them.

4. **Write the fixes yourself.** You have read every finding and the code; a gate has read one topic. Before writing anything, sort the findings:
   - **Fix only what lets something wrong through:** a wrong result or state, data lost or exposed, a crash, a use the change breaks, or a rule of the checklist broken in code that ships. A finding kc-code-review marks `(fails safe)`, one that only refuses too much (a guard that blocks an input nobody sends, an extra check whose worst outcome is an error message or a no-op), goes on the open list unfixed, with its reason. Example: a pass that hardened a guard script against path shapes no caller produces, and each hardening refused a real command the next round had to fix.
   - **Code a gate calls dead is proven dead before it goes.** A guard, fallback or branch a finding says nothing reaches is removed only after every input state its type admits (null, undefined, empty, zero) has been run through the code without it: a removed `!value` guard that had only been checked against an empty string crashed on `undefined`. A finding that says "unused" or "can't happen" is a claim, and the run is its check.
   - **A duplication finding is fixed by consolidating to one copy,** not by tidying each copy: one shared unit, every use pointed at it, the extra copies deleted. Tidying each leaves the next edit to drift them apart again.
   - **Mechanical fixes as written:** a gate's edit that only renames, deletes or moves lines is applied as written, all of a finding's edits or none. `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-gate-fixes.sh" <pass>/round-1/verdicts` lists every edit that is more than that; each one it lists is read as a description of the fix, never applied.
   - **Every other fix is yours to write,** from the finding's `FIX:` line (what must be true after it, and every place), checked against the lessons. Before writing it, run `trace-uses.sh --symbols <the names the fix changes>` (with `--also` for a sibling repo), give each use a verdict (breaks, behaviour changes, fine), and fix or ask about each one the fix breaks: a fix's damage lands where the changed thing is used.
   - **A test per fix that changes behaviour,** one that fails when the fix is broken: put the old line back, run the test, see it fail, restore the fix. A test that still passes doesn't hold the fix; rewrite it. A rename or deletion is held by lint and types.
   - **Record what became of each finding** in the pass folder's `fixes.txt`, one tab-separated line each: `fixed<TAB><finding><TAB><test file>`, `mechanical<TAB><finding>` (a fix that changes no behaviour: a rename, deletion, move or comment), or `open<TAB><finding><TAB><fails safe | needs a decision | pre-existing>`. The receipt reads it: a fix must name a test file added or changed since round 1's content, and the open lines must number `--open`.
   - **Ask in round 1 only a product, scope or irreversible call; settle the rest yourself.** Ask when the fix changes behaviour the ticket didn't ask for (what users see) or reaches past the change (a file round 1's diff doesn't touch, a shared helper or script other code uses, or a kind of risk `pass-size.sh` lists that round 1's diff didn't have). Two findings asking for conflicting code-style fixes, or a rule that looks wrong for this case, are yours: take the fewest-moving-parts fix and record it (kc-code-review's rule for contested calls). `guard-ask-product-only.sh` denies a question with code or review words or no stated kind (`Product:`, `Scope:`, `Irreversible:`, `Intent:`). A wider fix goes to the user with the files it adds and the other way that stays inside the diff; keep their answer word for word, since the receipt asks for it (`--scope-approved`). Example: a fix to one receipt's date format rewritten into the formatter every page of the shop shares, which changed pages no finding had asked about. Each settled conflict becomes a rule in the repo's `.claude/review-conventions.md`, created when missing, before the edits are applied. The question names the product or scope call the issue leaves open, in words that stand alone: what the person will see, never a rule id, file or gate. It carries only checked facts: what it says the person will see is measured as kc-code-review's lead-not-fact box (c) asks, in the running app or against the real formatting code, and the question's own wording is checked like a report line, since the user decides on it. Example: a gate's "a free item will show $0.00" put to the user as a choice, when the formatter printed nothing for 0, so the approved edit changed nothing on screen.
   - A finding that reverses a call the repo or an earlier run settled is handled by kc-code-review's rule for contested calls (settled by you unless it is a product call), not an open finding.
   - A pre-existing finding isn't fixed in this PR. A QA finding is fixed as it says, held the same way.
   - Then run the project's typecheck, lint, each fix's test and the tests of the files its uses are in. A fix that breaks them is rewritten once; still broken, it goes to the user as a decision. The fixes stay in the working tree: check that the content hash moved (`tree-hash.sh`). The next `kc-code-review` round walks what the fixes changed.

   Don't rebase or reset the branch during the rounds: each round reads the content since the round before's `TREE`.

5. **Review the fixes as the next round, until one finds nothing.** Gather only the fixes since the last round's content (`gather-review.sh --worktree origin/<base> --since-tree <its TREE> --out-dir <pass>/round-<k>`), run `kc-code-review` on that diff with `select-gates.sh --later-round` (a delta of tests only runs the testing gate, a delta of renames only the naming gate, as its Step 2 says) and no verification agent: `verify-gate-blocks.sh --later-round <pass>/round-<k> <repo>` is the round's verification record (save its output to `verdicts/verification.txt`; put the lines `<n> fixes re-checked`, `<n> rewrites checked`, `<n> rename-only lines kept` and a `Walk:` line per walk-item in `verdicts/checklist.txt`). Save `trace-uses.sh`'s output on it as `uses.txt` with a verdict per listed use in `uses-verdicts.txt` (`<use line><TAB>fine|breaks|changes`), run the tests of those uses, and fix what the round finds as step 6 does. The receipt refuses a round whose fixes are not smaller than the round before's. When round 3 still finds something, no fourth round runs: settle each finding in the pass folder's `final.txt` (`fixed<TAB><finding><TAB><test file>`, `dismissed<TAB><finding><TAB><reason>`, or `asked<TAB><finding><TAB><the user's words>` for a product or design call you can't make), with final fixes smaller than round 3's diff. The receipt prints every dismissal; list them in the report. A finding you can't settle that way goes to the user with the approach.

   Example: a pass whose round 2 re-read the whole diff and raised 19 items, 16 of them on lines round 1 had passed; reading only the fixes and their uses keeps each round smaller than the last.



### Record

6. Write the record (command below) when a round found nothing, or when the open list is what is left.

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/self-correct-record.sh" write --rounds <1-3> --open <count> --size <small|full> --pass <pass-folder>
   ```

   It refuses, and says every item missing, unless each round has verdict blocks, rounds after the first (or an open finding) have `fixes.txt`, and the last round's `TREE` is the content being recorded. It says `clean=yes` only when nothing is open and the last round found nothing (or `final.txt` settles what round 3 found). It checks that the rounds' records are there, not that they are right; `ready-receipt.sh` reads the same pass folder in full when the receipt is written. `self-correct-record.sh check <tree>` prints a record.
7. The content changes later (a reviewer's comment, a fix after the person's look, a squash that alters it): run the skill again on the delta, as a later round within the three-round limit, and write the record for the new content. A change of only the commit (a message amend, a rebase that leaves the tree alone) needs nothing.
8. Leftovers go to the person: each open finding with its reason and a one-line fix, in the report.

### Gate checklist

- What the rounds must show before the record. Each box is held by a script or a check lists what breaks it.

- [ ] §SC1 Rounds converge: round 1 reviewed the whole diff; each later round reviewed only the fixes since the round before and every use of what they changed; each round's fixes were smaller than the round before's; there were at most 3 rounds; and the last found nothing (`clean=yes`), or the open list went to the person. Held by `self-correct-record.sh` (`--rounds <1-3>`), `ready-receipt.sh` and `guard-merge.sh`. (N/A: never)
- [ ] §SC2 One writer: only a gate's mechanical edits (a rename, a deletion, a move) were applied as written, the ones `check-gate-fixes.sh` prints as `apply`; every edit it prints as `write` was written by you from the finding. (N/A: round 1 found nothing, or the gates wrote no edits)
- [ ] §SC3 Only what lets something wrong through was fixed: each finding that only refuses too much or fails safe is an `open` line in `fixes.txt` with its reason (fails safe, needs a decision, pre-existing), and the open lines number the receipt's `--open`. A finding is called pre-existing (or "already covered", "unchanged", "not ours") only when the base shows the same thing, and the reason names the check run on the base; a gap the pull request itself caused (a test it deleted, a caller it broke) is not pre-existing, and a claim with no search behind it ("unused", "no tests") is not either. (N/A: round 1 found nothing)
- [ ] §SC4 Each fix that changes behaviour has a test that fails when the fix is broken, and its `fixed` line in `fixes.txt` names that test file, one added or changed since round 1's content; a fix that changes no behaviour is a `mechanical` line. A fix that removes code a finding called dead was checked first against every input state its type admits (null, undefined, empty), and a duplication finding was fixed by consolidating to one copy, not by tidying each. (N/A: no fix commits)
- [ ] §SC5 The record names the content reviewed (its tree hash), not a commit, and the last round read that content: a record for other content is not accepted. A QA-walk finding was fixed like a code-review one. Held by `self-correct-record.sh`, `tree-hash.sh` and `gather-review.sh --worktree`. (N/A: never)

### Report

- Chat, short:

```
#### Self-correct: <change title>
**Content:** `<short tree hash>` · **Size:** <small|full> · **Rounds:** <k> · **Open:** <n>

| Check | Round 1 | Fixes |
|-------|---------|-------|
| Code review | <n> found · <n> fails safe · <n> asked | <n> mechanical · <n> written · <n> open |
| QA walk | <what was walked> | <what the fixes changed> |
| Proof | — | <n> tests, each failed with its fix broken · lint · types |
| Lessons | <n> kinds | <n> fixes rewritten to avoid a kind |
| Mutation | <n> mutants · <n> survived · or "no new branch" | — |

**Open (your call):**
- `<file>:L<n>` <finding> (<fails safe | needs a decision | pre-existing>). Fix: <one line>.
```
