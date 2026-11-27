---
name: kc-code-review
description: "Gate-based code review of a PR, branch or changes in any repo: one gate agent per convention topic, one PASSED/FAILED result in chat. Use on \"review this PR\", \"review my code\", \"review my changes\", \"review my branch\", \"is this clean\", \"good to merge\", \"code review please\", a bare PR URL or branch."
---


# Reviewing code

Orchestrate one gate agent per convention topic over a diff and report one PASSED or FAILED verdict in chat. The gates' rules live in the `kc-conventions` topic skills; the gates are this plugin's agents. Run every script from the target repo's root and read what it prints. The full wording of each step and rule is in `${CLAUDE_PLUGIN_ROOT}/skills/kc-code-review/references/detail.md`: read the matching `### ` section when a line here is unclear.

## Step 1: gather context

1. Diff: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/gather-review.sh" <num>` for a PR, or `gather-review.sh --branch [<base>]` for a local branch. It saves `review.diff` and `changed-files.txt` and prints `meta.env` (`HEAD_SHA`, `DIFF_FILE`, `CHANGED_FILES`).
2. When `meta.env` has `FETCH=`, run that command so gates can read files at the head SHA.
3. On a PR, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/scope-facts.sh" <num>`: author, other open PRs, body, linked issues.
4. On a re-review `gather-review.sh <num>` saves only the delta (`SINCE=`). Then run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-threads.sh" <num> --mine <login>` and classify each author reply: commit SHA (verify the whole class), reasoned push-back (surface it, never re-post over it), no reply (re-raise).
5. Uses: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/trace-uses.sh" "$DIFF_FILE" > <review-dir>/uses.txt` (`--also <dir>` for a sibling repo). Run the tests it lists.
6. Read the changed code yourself with Read, in chunks when the diff is large.

### Scope checks

7. Tick §G1 to §G5 yourself and write them as a `SCOPE:` block in the `BOXES:` shape of Step 2.

## Step 2: select and dispatch the gates

1. Select by script, never by judgment: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/select-gates.sh" "$DIFF_FILE" "$CHANGED_FILES"`. It prints `GATES=`, a reason per gate, and `WALK=`. On a later round of `kc-ready-for-review` add `--later-round`.
2. When `WALK=required`, this review is also the QA: walk each `walk-item` on its surface with `kc-verify:kc-ui`, `kc-verify:kc-ux` and the project's QA rules, every state, every audience, and save `walk-receipt.tsv`. Keep one "after" screenshot per flow (§G8). `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-walk-receipt.sh" <select-gates output> <walk-receipt.tsv>` must pass before any verdict.
3. Phase 1: one Agent call per listed gate, all in one message. Give each `HEAD_SHA`, `DIFF_FILE`, `CHANGED_FILES` and the repo root; add `uses.txt` for correctness.

| Gate | Agent (`subagent_type`) | Dispatch note |
|------|-------------------------|---------------|
| naming | `kc-gates:naming-gate` | always |
| clarity | `kc-gates:clarity-gate` | always |
| structure | `kc-gates:structure-gate` | always |
| simplicity | `kc-gates:simplicity-gate` | always |
| datetime | `kc-gates:datetime-gate` | an added line has date or time code |
| react | `kc-gates:react-gate` | a `.jsx`/`.tsx` file changed or a changed module imports React |
| rails | `kc-gates:rails-gate` | a Ruby, rake, Gemfile or `db/` file changed |
| i18n | `kc-gates:i18n-gate` | a locale file changed or an added line calls a translation |
| testing | `kc-gates:testing-gate` | always; PASS (N/A) when no behavior or test file changed |
| correctness | `kc-gates:correctness-gate` | always |
| security | `kc-gates:security-gate` | a handler, route, middleware, auth or token file changed, or an added line reads request input |
| project-conventions | `kc-gates:project-conventions-gate` | the repo has `.claude/review-conventions.md` |

4. Save each returned block verbatim to `verdicts/<gate>.txt`. A block with no per-box evidence goes back to the same agent.
5. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-gate-blocks.sh" [--later-round] <round-dir> <repo-root>` and `bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-gate-receipts.sh" <round-dir>`. Fix every line they print.
6. Phase 2, round 1: dispatch `kc-gates:verification-gate` with both scripts' output, `select-gates.sh`'s output, every phase-1 block verbatim, your `SCOPE:` block and your classification of carried-over findings.
7. Phase 2, later round: `verify-gate-blocks.sh`'s block is the verification record; no agent.
8. A gate agent type that does not exist: dispatch `general-purpose` told to invoke `kc-conventions:kc-<topic>` first and follow the same contract; report the fallback. A topic skill that cannot load makes the gate FAIL.

- Every gate returns `GATE:`, `STATUS: PASS | PASS (N/A) | FAIL`, `BOXES:` (one `[PASS|FAIL|N/A] <box id>: <evidence>` each) and `FINDINGS:`. Optional inputs for a caller that fixes (`FIX:` lines, `EDIT` blocks, mutation output): "### Step 3: the gate-agent contract" in detail.md.

## Step 3: verify every finding

1. Re-read each cited `file:line` at the head SHA; check every file a finding names.
2. Measure a behavior claim against the real module, not a mock.
3. Drop a finding that fails any check and list it on `Dropped:` with a one-clause reason.
4. Walk each proposed fix against every gate's checklist and its uses (`trace-uses.sh --symbols <names>`).
5. Mark a finding that only refuses too much `(fails safe)`; it still fails its gate.

## Step 4: aggregate and report

1. PASSED only when every gate is `PASS` or `PASS (N/A)` and `SCOPE:` has no FAIL box. One finding fails its gate and the review.
2. A box the project-conventions gate lists as overridden (§X3) is reported as overridden, not failed.
3. Run `check-review-report.sh` and `check-report-findings.sh` on the report; `guard-github-post.sh` runs them again on a post.
4. Report in chat, one line per finding, no em dash, no paragraphs; 🔴 must-fix, 🟠 should-address, 🟡 low (chat only).
5. Post nothing to GitHub; `/kc-gates:kc-post-review` drafts and posts on the user's signal.

```
### Review: <PR title>
**Head:** `<short-sha>` (re-review: `since <short-sha>`) · **Verdict:** ✅ PASSED | ❌ FAILED (<n> gate(s) failing)

**Does it work / what can it break**
- Measured: <before -> after>, or `not measured: <why>`.
- Uses: <n> names, <n> uses, <n> break, <n> change; <n> tests run, <n> failed.

**Approach:** <the simpler design and the findings it replaces, or "no simpler shape found: <alternative weighed>">.

**Gate status:** one row per gate, every round: | naming | ✅ PASS / ❌ FAIL / ⚪ N/A | ... clarity, structure, simplicity, datetime, react, rails, i18n, testing, correctness, security, project-conventions, verification

**<Gate>:** (only gates with findings)
- 🔴 `<file>:L<n>`: <issue>. <fix>. (non-blocking) (fails safe)

**Checklist:** Always; Scope; one line per trigger group (a receipt or `n/a, diff does not touch X`); Walk; Integrity
- Always: <files read at sha, findings cite file:line + sha, nothing posted>.
- Scope: <§G1-§G5 results>.
- Walk: <`WALK=not-required`, or one line per walk-item (states, audiences, screenshot per flow); with the public-path reason, also signed out and each replayed write>.
- Integrity: <n> fixes re-checked; <n> rewrites checked; <n> findings, <n> verified, <n> dropped, <n> fail safe.

**Dropped:** `<file>:L<n>` <finding>: <reason>.
**Overall:** <one sentence; if FAILED, what must change>.
```

- The Gate status table is mandatory. Report ✅ PASSED with one line when the whole PR is clean.

## Rules that hold in every step

- One failed box is a finding; one finding fails its gate and the review. Never "looks good with nits".
- Question the approach before the lines (§G5), and apply DRY, YAGNI and KISS to every diff.
- Check a convention against 2-3 files in the repo before citing it; drop what you cannot confirm, never what you confirmed.
- A round reviews one version of the code; fixes are the next round, on the fixes and the uses they change.
- A sweep is complete: every hit gets a `file:line` verdict, none piped through `head`.
- A fix you propose passes every gate and changes no state the fix is not for.
- A finding asks for the whole fix in one comment: every place with the same case.
- A finding about a screen is seen in the running app; a bug is reproduced.
- A contested call is settled once and written to `.claude/review-conventions.md`.
- A locale diff needs the per-key audit table; a pre-existing problem is flagged once, only when the change touches it.
- "Matches the existing pattern" is a yellow flag, not a pass.

## Checklist

- [ ] Tick each box, then say PASS, FAIL (file:line) or N/A (why).

- [ ] §G1 Not stacked: `scope-facts.sh` listed the author's other open PRs; a 30+ file diff or another branch's commits stops the review and suggests a rebase. (N/A: local diff, no other PR)
- [ ] §G2 The diff does only what its title and description say; out-of-scope work is one finding asking to split the PR. (N/A: never)
- [ ] §G3 Every linked issue was read and every linked design walked through each state the diff changes; each stated constraint is checked. (N/A: no linked issue)
- [ ] §G4 A diff of 35KB or more was read from the saved file in offset/limit chunks, every chunk. (N/A: read whole)
- [ ] §G5 The approach was questioned first: goal in one line, one other way compared; a materially simpler one leads the report. (N/A: never)
- [ ] §G6 Under the title, `**Does it work / what can it break**` has before and after numbers (or `not measured: <why>`) and the `Uses:` line. Held by `check-review-report.sh`. (N/A: never)
- [ ] §G7 Every `path:line` finding in `verdicts/*.txt` is in the report or on a `Dropped:` line. Held by `check-report-findings.sh`. (N/A: never)
- [ ] §G8 QA walked once, here: every state and audience (signed out for a `public or guest path`) via kc-ui and kc-ux; one "after" screenshot per flow. Held by `check-walk-receipt.sh`. (N/A: `WALK=not-required`)
- [ ] §G9 The PR description is short and readable: what changed and why, how to test, evidence; no process notes, no word counts, no restating the diff. (N/A: never)
- [ ] §G10 Screenshots and any video are in the PR description, uploaded with `gh pr create --attach <file>` or `gh pr edit <n> --attach <file>`; `gh --version` checked first. (N/A: no visual change)

- Full wording of each box, and the hard rules, output examples and iteration notes: `references/detail.md`.
