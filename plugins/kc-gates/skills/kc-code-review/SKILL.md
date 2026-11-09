---
name: kc-code-review
description: Gate-based code review for a PR, branch, or set of changes in any repo. Gathers the diff and checks its scope, dispatches one gate agent per convention topic (naming, clarity, structure, simplicity, datetime, react, i18n, testing, correctness) plus a project-conventions gate that reads the target repo's own .claude/review-conventions.md, then a verification gate that audits their receipts, and aggregates the per-box PASS/FAIL verdicts into one PASSED/FAILED result. Use when the user says "review this PR", "review my code", "review my changes", "review my branch", "is this clean", "is this good to merge", "code review please", or gives a bare PR URL or branch name. Output stays in chat; it never posts to GitHub.
---

# Reviewing code

This skill reviews a diff against a fixed set of quality gates, plus any repo-specific conventions the target project declares for itself. It is the orchestrator: it gathers the diff, checks scope, dispatches the gate agents, and aggregates their verdicts. The rules each gate grades against live in the `kc-conventions` plugin's topic skills; the gates themselves are this plugin's agents.

The correctness gate hunts bugs on every diff. The other gates catch what slips through a regular review: convention drift, code placed in the wrong layer, duplicated logic that already exists somewhere else, and code that takes three readings to understand.

## Hard rules

- **Failing even ONE checklist item is worth raising.** Many rules are expressed as a checklist of failure modes (e.g. a ternary rule listing nested / long / multi-line / non-trivial-branch as independent failure modes). A code item that trips a *single* box is a finding. Do NOT wait for two or three boxes to fail, and do NOT decide "it's only one of the conditions, that's fine." Walk each box independently and raise on the first failure. (Severity still calibrates per the rubric below; "worth raising" can be a 🟡, but it gets raised.) The recurring miss is pattern-matching a rule to its example domain, e.g. reading a "ternary" rule as "JSX ternaries only" and skipping a multi-line *value* ternary, so apply each checklist to every matching construct, not just the ones that look like the example.
- **Question the approach before the lines.** Before any line-level finding, read the goal (the linked issue, the description) and the diff as a whole, and ask whether this is the simplest way to get that result. Assume a simpler shape exists and look for it (one mechanism where the diff runs two side by side, the step that already knows a value reporting it instead of a later pass recomputing it, an existing tool, doing less). A line-by-line review of the wrong design is a polished wrong design: it hands the author fifteen fixes to code that should be deleted. See §G5.
- **Apply DRY, YAGNI, and KISS as a standing lens on every diff, not just the specific checklists.** Evaluate every change against three questions and surface a finding whenever the answer is "no", with the same any-finding-fails weight as any other rule:
  - **DRY**: is any logic, value, literal, or markup duplicated that should be a single source? A copied block, a re-declared constant, a re-implemented helper.
  - **YAGNI**: is there speculative or unused code? Unused params/props, an abstraction with a single caller built for a hypothetical second one, config options nothing passes, dead branches, a generality the diff doesn't use.
  - **KISS**: is there a materially simpler equivalent? A lookup object beating nested conditionals, an early return beating nesting, an existing util/stdlib call beating a hand-roll, fewer moving parts for the same behavior.
  These are first-class smells, not stylistic extras. Surface them with evidence and let the user judge (per the confirmed-findings rule); never withhold a confirmed one because you decided the complexity was "probably needed".
- **Never post anything to GitHub on your own.** No `gh pr review`, no `gh pr comment`, no `gh api` writes. Output stays in chat. If the user wants comments drafted or posted, they run `/kc-gates:kc-post-review`. The plugin's hook blocks unapproved GitHub review writes.
- **Verify conventions against the codebase before flagging.** Do not cite a "convention" from memory. Before saying "this codebase does it like X", grep the repo and confirm there are at least 2-3 existing examples of X. Cite the example file paths in your finding.
- **Before flagging, confirm it's actually a deviation, not a misread.** Some things look wrong in isolation but are the house style when you grep. Grep to confirm the thing genuinely deviates from how the codebase does it, and cite the evidence. This check is about ACCURACY (don't raise a non-issue based on a misunderstanding); it is NOT a license to suppress. Once something genuinely deviates from a rule, you surface it; see the next two rules.
- **Report what you can confirm; drop what you cannot.** A finding you cannot confirm (a possible bug you could not trace, a judgment call you cannot back with evidence from the code or docs) is dropped, not softened into a "maybe". A confirmed violation of a checklist box is never dropped or softened: whether it is acceptable is the user's (and the PR author's) call, not yours, so "intentional", "defensible", "matches the neighbors" or "low-value" is still never a reason to withhold one. Those words may be added as descriptions for the human's benefit.
- **Any finding fails its gate. There is no finding that "still passes."** A gate is PASS only when nothing is found in it; the moment one thing is found, that gate is FAIL and the overall verdict is FAILED. Severity labels (🔴/🟠/🟡, issue/suggestion/nitpick) calibrate only the *weight communicated to the author*; they do NOT affect whether the finding is reported or whether the gate passes. A single 🟡 nitpick fails its gate and therefore the review. Report FAILED plainly; never round up to "looks good with minor nits."
- (Self-review parallel: when reviewing *my own* work, precedent never excuses a violation either; the same confirmed-findings bar applies before I call work done.)
- **A round reviews one version of the code.** Do not change the code under review while its gates run, and never carry a PASS onto code that changed after the gate saw it. Fixes written after the round get no gate round of their own: `kc-ready-for-review` holds each by a test that fails when it is broken, lint and types, since a round on fix code finds something in its fixes, and so on without end.
- **A duplication finding on a one- or two-line expression is answered inline.** The fix never adds a file, hook or helper for a plain expression (`kc-conventions:kc-simplicity` §P11); it leaves the expression inline at each site or reuses a unit that already exists.
- **A contested call is the user's, and it is recorded in the repo.** A call is contested when two gates' fixes for one construct conflict, or a finding reverses a call an earlier round or run made on the same construct. Never settle one yourself, not even by applying the fix that looks better: applying one quietly turns the other into a finding next round. Ask the user, one question per call, with each side's fix as an option. Then write the answer to the repo's `.claude/review-conventions.md`, so the next run in that repo holds the code to it instead of deciding again:
  - When the file is missing, create it: a short header saying it holds calls the owner settled, which win over the built-in rules; `## Rules`, with the call as `### R<n>` (the rule as a do or don't, what fails it, an example path or snippet); and `## Gate checklist`, with one box per rule ending in its N/A condition. The project-conventions gate walks those boxes.
  - When it exists, add the next `R<n>` and its box, and leave the rules already there alone.
  - Say in the report which rules were added, and leave the file for the user to commit.
- **When a rule lists examples, examples are illustrations, never an exhaustive boundary.** State the principle first, examples second, explicitly labeled as illustrations. Apply the rule to *every* item in the diff that matches the principle, including items not in the example list. If you find yourself thinking "this item isn't in the listed examples so the rule doesn't apply," you're misreading the rule. This applies BOTH when reading rules (don't narrow to the listed examples) AND when writing rules (don't frame a rule around a specific domain when the principle is general).
- **Brevity is a hard rule on every surface: chat findings, drafted comments, and replies.** Length is the most consistently violated rule in this skill. Every unit of output has a budget, and a sentence past it must earn its place: **a chat finding is one line**, **a drafted comment is one to three sentences**, **a reply accepting feedback is one sentence plus the commit SHA**. A drafted `suggestion` carries one brief reason inside its budget (see `kc-post-review`). Prose that restates the rule, justifies a change the reader already asked for, re-describes what a linked commit shows, or over-justifies a finding past that one reason does NOT earn its place; cut it. If the reader needs more of the why, they will ask. Count before you show: an over-budget unit is a rewrite *before* the user sees it, never after they ask you to shorten it.
- **No em dashes (U+2014) in any output.** Not in the chat report, verdict blocks, drafted comments or replies. Use a period, comma, colon or parentheses instead.
- **A pre-existing problem is flagged at most once, and only when it intersects the change.** Code the diff did not touch is not the author's to fix in this PR. When an untouched line interacts with a changed one (the change calls into it, extends it, or depends on its behavior), raise it once, briefly, marked as pre-existing; otherwise leave it out. A violation the diff copies or moves is not pre-existing: it is the diff's own (see "Matches the existing pattern" below).
- **Read the actual changed code yourself** with the `Read` tool, after fetching the diff. Gate verdicts are a starting point: the specific issues live in specific lines and you need to see them to call them out usefully.
- **A gate finding is a lead, not a fact. Verify every one before it reaches the user.** Gates apply a real rule to the wrong line, cite a file that does not hold what they claim, miscount, or assert behavior nobody ran. Before a finding enters the report, tick all four: (a) re-read the cited `file:line` at the head SHA and confirm it holds what the finding says; (b) when the finding names several files, check each one, not only the first; (c) when it asserts behavior, measure it rather than relaying the gate's reasoning; (d) confirm the measurement ran against the real module, not a global test mock or stub. A finding failing any box is dropped and listed on the report's `Dropped:` line with a one-clause reason, never omitted silently. The same bar applies to a finding you produced yourself, and to your own wording of a gate's finding: the words in the report line are what gets checked, so a claim the rewording adds or sharpens (a gate's "calls the helper twice" turned into "parses the file twice") is checked against the code before it goes in.
- **A sweep is complete or it did not happen.** Every hit a sweep prints gets its own `file:line` verdict. Never pipe a sweep through `head` or `tail`, take the "first N", sample, or stop reading at the first find: the hit count must equal the verdict count. A sampled sweep fails its box exactly like a sweep never run, because the line nobody read is where the miss is.
- **Any fix proposed must itself pass every rule, of every gate, and break nothing.** A suggestion is code the author will write because we asked, so it gets the bug check our own change would. Before a suggested change goes into a finding (yours or a gate's), whether written as code or in words, walk it against all the checklists, not only the rule that surfaced it. When it changes behaviour, list every state that reaches the changed line with its result before and after (correctness §B15): a state the fix is not for whose result moves means the suggestion introduces a bug, so rewrite it or drop it. A replacement that still holds a multi-line ternary, a conditional spread, a hand-rolled helper or a subject-less name like `isOn` is worse than no suggestion, because it launders the violation as the reviewer's own recommendation; a replacement that breaks another state is worse still, because the author ships it on the reviewer's word. A name, key, file or location a finding suggests is checked the same way: search the names already beside it (one a letter or a word apart from an existing one reads as a typo, `customerEmail` beside `customersEmail`), and check what would import from the suggested place (a data module importing from a view folder). Examples: a translation key suggested next to one that differs by an "s"; a helper suggested "next to the component" that a data hook then imports; a config key suggested that another setting already uses.
- **A finding asks for the whole fix, in one comment.** The author fixes what the comment names, so a finding that names one place or one symptom gets one place fixed, and the next round finds the rest. Before it is written, list every place in the diff with the same case (the same state handled in two components, the same field read by two queries) and the whole of what the broken rule asks (the wrapper the rule forbids, not only the helper inside it), and name them all. A finding that asks for a test names the break the test must catch, what the code would wrongly do ("shows the login address when a sending address is set"), not the line or branch to cover: a test written to cover a line can pass with the original bug still in. Examples: a failed-load state flagged on a status badge but not on the form field that shows the same record; a lookup asked out of a data wrapper the rule says should not exist, so the wrapper stays; "test the fallback" answered with a fixture where both values are the same, so swapping their order still passes.
- **Cite line numbers, file paths, and head SHA** for every finding. Vague feedback is useless.
- **Locale diffs require a per-key audit table, never an aggregate grep, never your memory.** This is enforced by the i18n gate agent: if the diff touches translation/locale files, that agent must produce a per-key audit table (one row per new key, checking namespace placement, pluralization, naming, and duplication; see the `kc-conventions:kc-i18n` skill's §I1) as its evidence, and a missing/incomplete table is a gate FAIL. You may NOT write any locale verdict, including "no new keys", "no issues this round", or silently dropping i18n from the checklist, without the table. An aggregate report ("greped N keys, all unique") is an automatic incomplete review: a direct-duplicate grep alone cannot catch a generic noun that belongs in a shared strings file, a singular-only label that should be a plural-aware key, or a key whose name doesn't match its own value. "It matches the neighbors" / "low-value" / "no new keys" are the three rationalizations that have caused this miss; none of them is valid without the table.

## Workflow: agent-driven gates

The review is NOT a single inline pass. It is a fan-out of independent **gate agents**, one per convention topic, aggregated into a single PASS/FAIL verdict. The fan-out runs **every time the skill is invoked**, a re-review included, and there is no "I already looked at this" shortcut for code a gate has not read. What a re-review reads is the code that is new: the commits the author pushed since the head reviewed last time (Step 1's `--since`), with `select-gates.sh` run on that delta, so a gate the new commits don't need isn't dispatched. Reading the whole pull request again spends a full review to re-judge lines that already had one, and a second sampling of old lines finds things by chance, which sends the author a new list each round. A fix that brings a new violation is in the delta, so the gates still see it. The whole diff is reviewed again only when the delta can't be made (the author rebased). A re-review is for someone else's new push; your own fixes in `kc-ready-for-review` get no round (see "A round reviews one version of the code").

**Why agents instead of inline:** an inline reviewer silently skips checklist items ("low-value", "matches the neighbors", "no new keys"); this has been the repeated failure mode. A dedicated agent that owns exactly one topic and must return a per-box PASS/FAIL verdict has no other job to crowd it out, so it cannot quietly drop a box.

### Step 1: gather context (you, the orchestrator)

Run the bundled scripts from the target repo's working directory; each prints what it gathered, so read its output rather than re-deriving it.

- **Diff, head SHA, changed files:** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/gather-review.sh" <num>` for a PR, or `bash "${CLAUDE_PLUGIN_ROOT}/scripts/gather-review.sh" --branch [<base>]` for a local branch (base: `origin/HEAD`, then `main`, then `master`). It saves `review.diff` and `changed-files.txt` under `${TMPDIR:-/tmp}/kc-review-<sha>/` and prints `meta.env`: `HEAD_SHA`, `BASE`, `TITLE`, `DIFF_FILE`, `CHANGED_FILES`, and `PR` in PR mode. Every gate gets `DIFF_FILE` and `HEAD_SHA` from it; the sweep scripts run against `DIFF_FILE`.
- **Head checkout:** when `meta.env` has a `FETCH=` line, the working tree is not on the head commit. Run that command so the gate agents can read files at the exact head SHA via `git show <sha>:<path>`.
- **Scope facts (PRs):** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/scope-facts.sh" <num>` prints the author, base, commit and file counts, the author's other open PRs, and each linked issue, saving the PR description (`pr-body.md`) and each issue body (`issue-<n>.md`) beside the diff. The §G1-§G3 boxes below are judged from it.
- **On a re-review, gather the delta:** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/gather-review.sh" <num> --since <sha>`, where `<sha>` is the head your last review read (`gh pr view <num> --json reviews --jq '[.reviews[] | select(.author.login == "<your-login>")] | last | .commit.oid'`), after running the `FETCH=` command when the first gather printed one. `meta.env` then has `SINCE=`, and `DIFF_FILE` and `CHANGED_FILES` hold only what changed since; every later step uses them. When it prints `SINCE_SKIPPED=` instead (the branch was rebased), the files hold the whole diff: review that, and say so in the report.
- **On a re-review, also read the reply threads on your previous comments:** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/review-threads.sh" <num> --mine <your-login>` (login: `gh api user --jq .login`) prints every thread, root then replies, and marks the threads you started and whether the author replied after your last comment. For every carried-over finding, classify the author's reply before re-raising it:
  - **A commit SHA** = "fixed in `<sha>`". Verify it against head, and verify the WHOLE class, not just the examples you named. A common pattern: the author fixes the exact items you listed but leaves the rest of the same class; the finding is still open, but re-frame it as "the named ones are done; the same applies to the rest", not as if nothing changed. A fix for a bug, and a test added because a comment asked for one, is checked by putting the bug back (revert the fixed line, swap the two values, drop the guard) and running the tests: a test that still passes does not guard it, and the finding stays open. The mutation sweep makes the commonest of these on its own: it swaps the two sides of a value fallback (`user?.nickname || user?.name`), so a test whose fixture leaves one side empty shows up as a survivor.
  - **Reasoned push-back** (e.g. "this matches the existing pattern, keeping it") = do NOT silently re-post a fresh duplicate comment on a thread they already answered; that reads as ignoring them. Surface their reasoning to the user, and either drop the finding or reply in the existing thread with the counter-point; let the user decide.
  - **No reply / unaddressed** = re-raise, noting it is still open from the prior round.

  Carry the author's responses into Step 4 so the report and any re-drafted comments reflect what was fixed, what was declined-with-reason, and what is genuinely still open. Posting a re-review that ignores the author's replies is a documented trust failure.

If a script fails, relay its message; fall back to the equivalent `gh`/`git` command by hand only when the script itself is unavailable, and say so in the report.

**Scope checks (you, before the fan-out).** These are about the target as a whole, so no single gate owns them. Walk each box yourself and record the result as a `SCOPE:` block in the same `BOXES:` shape the gate agents return (Step 3); the verification gate audits it (its §V7). A scope finding goes into the report like any gate finding and fails the review the same way.

- [ ] §G1 The target is not stacked: the author's other open PRs were listed (`scope-facts.sh`), and when the diff is large (30+ files) or the PR's base or commits belong to another open branch (compare its head, base and commit count with the listed PRs), the review stops and reports the stacking before any line-level finding, suggesting a rebase onto the default branch. A stacked diff cannot be reviewed in isolation. (N/A: local diff, or the author has no other open PR)
- [ ] §G2 The diff does only what its title and description say. Out-of-scope work (an unrelated refactor, removed public surface, a new abstraction, a bundled feature or option) is one finding asking to split the PR, naming which commits belong in which PR; it is not reviewed silently as if it were in scope. On a re-review the box is checked again against the commits added since the last round: work that arrived between rounds is scoped like a new pull request before any of it is reviewed. (N/A: never; every target has a stated purpose, even if it is only a branch name)
- [ ] §G3 Every linked issue was read in full (the `issue-<n>.md` files `scope-facts.sh` saved, and its `pr-body.md`), and every design, prototype or mockup it links was opened and walked through each state the diff changes (on and off, empty and filled, each role or plan) before any finding about what a person sees. Each constraint the issue states ("no public API change", "must work offline") is checked against the diff, and a violated one is a finding that cites the issue. Each finding about copy, layout, or what shows in which state is checked against the design as well: one the design contradicts is dropped, and one where the issue's text and the design disagree is a question for whoever owns the spec, citing both. For example, faulting a settings page's wording that the linked mockup has word for word, or calling a card's placement wrong when the mockup puts it there. (N/A: no linked issue)
- [ ] §G4 A diff too large to read in one pass (roughly 35KB or more) was read from the saved file in offset/limit chunks, every chunk; no hunk was skimmed. The gate agents get the saved path, not a truncated paste. (N/A: the diff was read whole)
- [ ] §G5 The approach was questioned before the lines. The orchestrator wrote down the result the change is after, then at least one other way to get it, and compared them: fewer mechanisms, fewer places that know the same thing, less code. When another way is materially simpler, it is one design finding that leads the report and any drafted comment, and the line findings it would delete are folded under it instead of listed as separate asks. Evidence: the goal in one line, the alternative considered, and why it is or is not simpler. On a re-review it is walked again, and when this round finds a new case of a defect an earlier round fixed in the same code, the recurrence is the evidence: the approach comes back as a finding (a question citing the rounds), even when the author declined it before. (N/A: never; even a one-line change has a goal another shape could meet)

### Step 2: dispatch the gate agents in two phases (mandatory: every gate the diff needs, EVERY round)

First decide which phase-1 gates this diff needs, by script, never by judgment: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/select-gates.sh" "$DIFF_FILE" "$CHANGED_FILES"`, from the target repo's root. It prints `GATES=` (the gates to dispatch) and one line per gate saying why it runs or why it is N/A, read from the changed files and the added lines (a React gate only when the diff has `.jsx`/`.tsx` files or a changed module imports React, a Rails gate only for Ruby, rake, Gemfile or `db/` files, and so on).

Dispatch each listed gate with the Agent tool, `subagent_type` set to the agent name below. Phase 1 runs in parallel: issue every listed gate's Agent call in a single message. Phase 2 (verification) runs only after every phase-1 agent has returned, because it audits their returned verdict blocks rather than re-deriving findings.

Each topic gate preloads its `kc-conventions:kc-<topic>` skill, so it already holds that topic's `## Review checklist`, `## Review detail` and `## Sweeps`. You do not paste rules into the prompt.

**Phase 1: dispatch the gates `GATES=` lists, in parallel.**

| Gate | Agent (`subagent_type`) | Dispatch note |
|------|-------------------------|---------------|
| naming | `kc-gates:naming-gate` | always |
| clarity | `kc-gates:clarity-gate` | always |
| structure | `kc-gates:structure-gate` | always |
| simplicity | `kc-gates:simplicity-gate` | always |
| datetime | `kc-gates:datetime-gate` | when an added line has date or time code |
| react | `kc-gates:react-gate` | when a `.jsx`/`.tsx` file changed or a changed JS/TS module imports React |
| rails | `kc-gates:rails-gate` | when a Ruby, rake, Gemfile or `db/` file changed |
| i18n | `kc-gates:i18n-gate` | when a locale file changed or an added line calls a translation |
| testing | `kc-gates:testing-gate` | always; agent returns PASS (N/A) if the diff changes no behavior and touches no test file |
| correctness | `kc-gates:correctness-gate` | always |
| project-conventions | `kc-gates:project-conventions-gate` | when the target repo has `.claude/review-conventions.md` |

**Phase 2: dispatch only after every phase-1 agent has returned.**

| Gate | Agent (`subagent_type`) | Dispatch note |
|------|-------------------------|---------------|
| verification | `kc-gates:verification-gate` | always; its prompt additionally includes `select-gates.sh`'s output, every dispatched phase-1 gate's returned `GATE:`/`STATUS:`/`BOXES:`/`FINDINGS:` block verbatim (copied, never summarized: a summary drops the sweep counts the verification gate audits, and it then fails boxes the gate passed, as when a testing gate's "0 hits" lines were left out of a one-line recap), your `SCOPE:` block, and on a re-review your classification of each carried-over finding (Step 1) |

Dispatch exactly the gates `GATES=` lists: never leave a listed gate out because it looks inapplicable, and never add or drop one by judgment. A gate the script leaves out is reported ⚪ N/A in the gate table with the script's reason, and the verification gate audits it from that line. A listed gate whose rules turn out not to apply once it reads the diff still returns `PASS (N/A)` **with the reason**; that verdict is the gate agent's, never an assumption you make on its behalf. When a review covers several diffs at once (a backend and a frontend PR, a stack), each diff gets its own `select-gates.sh` run, and one agent per gate can grade every diff that lists it, returning one block per diff.

The `project-conventions` gate is how this skill stays repo-agnostic while still enforcing house rules: it reads the target repo's own `.claude/review-conventions.md` (if one exists) and grades the diff against whatever that file declares. A repo with no such file is legitimately N/A; it is not this skill's job to invent conventions for a repo that hasn't written any down. When a repo rule contradicts a built-in convention, the repo rule wins for that repo: the gate lists the override (its §X3), and you report the built-in box as overridden, citing the repo rule, instead of failing it.

**Fallback when a gate agent is unavailable.** If an Agent call fails because the `kc-gates:<gate>` agent type does not exist (for example, the `kc-conventions` dependency failed to load, or the plugin's agents are not registered), dispatch a `general-purpose` agent for that gate instead. Tell it to invoke the `kc-conventions:kc-<topic>` skill with the Skill tool first, then follow the gate-agent contract in Step 3 exactly, returning the same verdict block. For project-conventions or verification, tell it to read `${CLAUDE_PLUGIN_ROOT}/agents/<gate>.md` and follow it. If the `kc-conventions:kc-<topic>` skill cannot be invoked either, the gate is FAIL with the evidence "topic skill unavailable"; never grade a topic from memory. Report every fallback in the output (see Output format).

### Step 3: the gate-agent contract

The agents carry this contract in their own definitions; the dispatch prompt supplies the inputs. Give each phase-1 agent:

- the head SHA (`HEAD_SHA` from `meta.env`);
- the path to the saved unified diff file (`DIFF_FILE` from `meta.env`);
- the changed-file list (`CHANGED_FILES` from `meta.env`);
- the target repo root.

**Context you add** (what the author already settled) informs the gate; it never narrows what the gate checks in the diff it was given. On a re-review that diff is the delta, and each gate still reads the changed files whole at the head, so new code is judged against the old code it touches. Settled means a design stays, not that it works: the prompt still has each gate walk every input that design handles. A brief that called a text-matching swap "accepted; review its correctness" and listed only the round's fix had every gate check that fix, while inputs the design never handled went unchecked for three rounds.

**Optional inputs**, for a caller that acts on the findings itself (`kc-ready-for-review` passes them; a review on request passes none, and its findings stay one line each). The chat report still shows each finding as one line.

- **Fixes.** Under each finding's line, unindented, `FIX: <what must be true after the fix, and every place it must hold>`: the behaviour expected, not the code. One writer, the caller, writes the code, having read every finding; code a gate writes for one finding is written blind to the others and to the uses of what it changes. The one exception is a mechanical fix (a rename, a deleted or moved line), given as edits that apply as written, each SEARCH block copied exactly from the file at the head SHA and found once in it, replacing at most two lines:

  ```
  EDIT <path>
  <<<<<<< SEARCH
  <the exact lines to replace>
  ======= REPLACE
  <the lines that replace them>
  >>>>>>> END
  ```

  `DELETE <path>` and `MOVE <path> <new-path>` stand alone. A new file, a new branch or condition, or anything longer is a `FIX:` line, never an edit; `check-gate-fixes.sh` lists any edit that breaks this, and the caller reads it as a description. Gates stay read-only: they never apply an edit. Each gate walks its fixes against every gate's checklist, not only its own, and gives the receipt `<n> rewrites checked against <gates>` (verification §V8).
- **Mutation output.** The mutation sweep's output on the diff, for the testing gate (`surviving-mutants.sh`, `kc-conventions:kc-testing`). The caller runs the sweep, not a gate: once per area with `--paths` (the unit specs for the server code, a page's end-to-end spec for that page) and the install command as `--setup` when a fresh checkout needs one. It starts the sweep before dispatching the other gates and dispatches the testing gate when it is done. Run inside a gate, the sweep's test runs would overlap the other gates' runs, and a suite that takes a fixed port or a shared build would read another run's server.

Each agent must:

1. Read its topic's `## Review checklist` and `## Review detail` in full.
2. **Sweep the greppable constructs FIRST, before reading the diff for meaning.** Some boxes cover constructs a script can enumerate exactly, and those boxes are graded on whether the hits were **listed**, not on whether they were noticed. The agent runs every script under its topic's `## Sweeps` against the diff file, then gives every hit a `file:line` verdict in the evidence, with the hit count. `0 hits` must be stated explicitly; a box with no receipt is FAIL by default, because silence is indistinguishable from never having looked.
3. Evaluate EVERY checklist box against every matching construct in the diff. Before failing a box on a convention, grep the target repo to confirm the convention is real (cite 2-3 example paths in the evidence).
4. Return ONLY this structured verdict:
   ```
   GATE: <name>
   STATUS: PASS | PASS (N/A) | FAIL
   BOXES:
   - [PASS|FAIL|N/A] <box id>: <evidence: file:line, grep result, or "no matching construct in diff">
   FINDINGS:
   - <severity 🔴|🟠|🟡> <file>:<line>: <issue>. <fix>
   ```
5. Failure semantics: a box is **FAIL** if ANY matching construct in the diff violates it; a sweep whose hit count differs from its verdict count is FAIL too (never truncated or sampled); the gate STATUS is **FAIL** if ANY box is FAIL. Do not average, do not "mostly pass".
6. Drop a finding it cannot confirm, never a confirmed one, and write no em dash (U+2014) in the block.
7. Walk every fix it proposes against every gate's checklist, not only its own, before writing it into a finding, and for a fix that changes behaviour, list each state reaching the line with its result before and after (correctness §B15). It writes code only for a mechanical fix (see Fixes above).

A verdict that does not have this shape, or that has a box with no evidence, is rejected: send it back to the same agent for the per-box `BOXES:` breakdown before aggregating.

### Step 4: aggregate into one verdict (you, the orchestrator)

- Overall verdict is **PASSED** only when every gate returned `PASS` or `PASS (N/A)`, and the `SCOPE:` block has no FAIL box.
- **A single FAIL box in any one gate means overall FAILED.** State plainly that the review has not passed and the author needs further changes; do not soften a FAILED into "looks mostly good" or "just nits". A nitpick-severity finding still fails its box and therefore the review; severity calibrates the *comment*, not whether the gate passed.
- **A gate PASSES only when it found nothing. Any finding = that gate FAILED.** Do not let a gate agent (or yourself) return PASS while also listing a finding; that is contradictory and means FAIL. Aggregate by surfacing every finding from every gate; never drop or merge-away a confirmed finding because you judged it intentional/acceptable (that call is the user's; see Hard rules). The report lists all findings found, and the verdict is FAILED if the list is non-empty.
- A built-in box the project-conventions gate lists as overridden (§X3) is reported as overridden, citing the repo rule, and does not fail its gate.
- **Mark what fails safe.** For each finding, ask whether what it describes lets something wrong through: a wrong result or state, data lost or exposed, a crash, a broken use, or a rule broken in code that ships. A finding that doesn't, one that only refuses too much or fails safe (a guard that blocks more than it must, an input nobody sends rejected with an error, an edge case whose worst outcome is a refusal or a no-op), still fails its gate and is reported, with `(fails safe)` at the end of its line. `kc-ready-for-review` leaves those unfixed, on the user's open list. Example: a delete guard that cancelled orders block refuses too much and is `(fails safe)`; a fallback that lets an empty name through is not.
- Emit the gate-status table first, then the deduped findings, then the explicit `PASSED`/`FAILED` verdict (see Output format).
- On a re-review, run Steps 1-4 again on the delta, and fold in the author's replies to your prior comments (Step 1): mark each carried-over item as fixed (verify the whole class), declined-with-reason (surface it, don't re-post over their reply), or still-open. Report the new verdict; do not carry forward a prior round's PASS.

**Self-review trigger:** when *I* am the one implementing changes (not reviewing a teammate's PR), the gate fan-out runs in two cases only: when the user asks for a review, or as part of `kc-gates:kc-ready-for-review`, the one pass before a PR goes to a reviewer, which runs it once, holds the fixes by tests, and then hands what is still open to the user. It does not run after each fix, commit or push, or on uncommitted work before showing it to the person for approval; the fan-out costs too much time and too many tokens for that, and the pass at hand-off runs it again anyway. When it runs, lint and types passing is not the same as gate-clean, and every gate's checklist is walked box by box to a PASS. Separately, UI work is looked at rendered in a browser before I call it done (see the verification gate's self-review group), since tests lay nothing out; on a task headed for a pull request, that walk is the QA step of the hand-off pass, not a second walk while building.

**"Matches the existing pattern" is a yellow flag, not a green light.** A gate agent must not pass a box because the diff copied the shape of nearby code. If the surrounding pattern violates the rule, the new code that extends it violates it too. Every copied block, every matched helper, every duplicated key style is evaluated against the rule on its own; nearby precedent is not the evaluation.

## Output format

Report directly in chat. No file output. **Be terse.** The reader is the user, not the PR author; they want to scan, not read prose.

**Rules:**
- One finding = one line. Two short lines max if a fix snippet is genuinely needed. This is a budget, not a target to fill; most findings fit in one line and should stay there.
- **No explanation paragraphs anywhere in the report**: not under a finding, not under the verdict, not as a preamble to a section. The gate table, the finding line and the fix carry the whole message.
- Prefix every finding with a severity color so the user can scan weight at a glance: 🔴 must-fix (real bug, regression, security, drift from a stated convention), 🟠 should-address (correctness gap, validation hole, behavior question that needs an answer), 🟡 low (style, naming, nit, cleanup). These emojis are chat-only: never put them in posted PR comment bodies, where the Conventional Comments label (`issue` / `suggestion` / `nitpick`) carries the weight instead.
- Lead with the file:line. Then the issue. Then the fix (as inline code or short phrase, not a code block, when it fits).
- No code blocks unless the suggested fix is multi-line and cannot be expressed inline.
- No "explanation" paragraphs. The fix implies the reasoning. If the reader needs the *why*, they will ask.
- Do not repeat the same finding under two gates. Pick the closer fit.
- Skip a section header entirely when the section is empty.

**Format:**

```
### Review: <PR title>
**Head:** `<short-sha>` (re-review: `since <short-sha>`, or `whole diff: rebased`) · **Verdict:** ✅ PASSED | ❌ FAILED (<n> gate(s) failing)

**Approach:** <one line: the simpler design and the line findings it replaces, or "no simpler shape found: <the alternative weighed>">.

**Gate status:** (one row per gate, every round)
| Gate | Status |
|------|--------|
| naming | ✅ PASS / ❌ FAIL / ⚪ N/A |
| clarity | ... |
| structure | ... |
| simplicity | ... |
| datetime | ... |
| react | ... |
| rails | ... |
| i18n | ... |
| testing | ... |
| correctness | ... |
| project-conventions | ... |
| verification | ... |

**Naming:**
- 🔴 `<file>:L<n>`: <issue>. <fix as inline code or short phrase>.
- 🟡 `<file>:L<n>`: <issue>. <fix>. (fails safe)

**Clarity:**
- 🟠 `<file>:L<n>`: <issue>. <fix>.

**i18n:** (paste the per-key audit table from the i18n gate when locale files changed)

**Overridden by repo conventions:** (only when the project-conventions gate listed an override)
- <gate> §<box>: overridden by <repo rule>, `.claude/review-conventions.md:L<n>`.

**Checklist:** (one line per applicable trigger group, per the verification gate's "How to use this in the output": a cited receipt, or `n/a, diff does not touch X`)
- Always: <files read at sha, findings cite file:line + sha, nothing posted to GitHub>.
- Scope: <§G1-§G5 results, e.g. "not stacked (author has no other open PR); title matches; no linked issue; diff read whole; approach: weighed one grouping step for both cases, the diff's two are needed because <reason>">.
- <trigger group>: <receipt, or "n/a, diff does not touch X">.
- Integrity: <n> fixes re-checked; <n> rewrites checked; <n> findings, <n> verified, <n> dropped, <n> fail safe.

**Dropped:** (only when a finding failed the lead-not-fact check) `<file>:L<n>` <finding>: <one-clause reason>. One entry per dropped finding.

**Fallbacks:** (only when a gate ran as a `general-purpose` agent) <gate>: `kc-gates:<gate>` unavailable, ran as general-purpose with `kc-conventions:kc-<topic>`.

**Overall:** <one short sentence; if FAILED, name what must change for the next round to pass>.
```

The verification gate's "How to use this in the output" section, with a full worked Checklist example, is in `${CLAUDE_PLUGIN_ROOT}/agents/verification-gate.md`.

The **Gate status table is mandatory and leads the report**: it is the receipt that every gate was checked by its agent this round. A review without the full table (all gates listed, each with PASS / FAIL / N/A) is incomplete. The top-line **Verdict is FAILED if any gate is FAIL**, full stop; do not report PASSED with a failing gate, and do not omit a gate to make the table look clean.

**Each gate's verdict reflects every box in its checklist, not just the headline rule.** A gate agent reports `PASS` only after walking every box in its topic's `## Review checklist` and citing evidence for each. A vague "naming looks fine" from an agent is a rejected verdict; send it back for the per-box `BOXES:` breakdown.

**Examples of good vs bad findings:**

Bad (too wordy, paragraph-shaped):
> 1. **Opaque local names: `current` / `prev`** (`Widget.tsx:63-66`)
>    In this function, `current` is "the new item" and `prev` is "the previously removed item." A reader has to trace through the logic to figure that out. Suggested: `newItem` / `previouslyRemovedItem`.

Good (single line, fix in-place):
> - `Widget.tsx:63,66`: `current` / `prev` are opaque. Rename `newItem` / `previouslyRemovedItem`.

Bad:
> 4. **Magic spread + override + default mix** (`Widget.tsx:72-77`)
>    Three different things happening in one literal: spread, override, default. Reads cleaner as a named helper: ...

Good:
> - `Widget.tsx:72-77`: Spread + override + default in one literal. Extract a named `revivedItem`.

If the whole PR looks clean, one line:

```
### Review: <PR title>
`<short-sha>` `<file>`: follows existing conventions and naming. No changes.
```

## Drafting and posting PR comments

This skill does not draft or post PR comments. To turn findings into comments, or to post them, the user runs `/kc-gates:kc-post-review`, which carries the Conventional Comments format, the draft audits, and the explicit post-signal protocol.

## What this skill is not

- It is not a generic style linter substitute and it is not a security review. Stay focused on the gates above plus any repo-declared conventions.
- It does not post to GitHub on its own.

## Notes for iteration

This skill is in active iteration. When the user gives feedback ("you missed X", "you flagged a non-issue Y", "we have a convention for Z"):

1. Identify which file the feedback belongs in. **Topic feedback goes to the `kc-conventions` plugin, never to kc-gates:**
   - Identifier naming → `plugins/kc-conventions/skills/kc-naming/SKILL.md`
   - Ternaries, comments, magic numbers, other readability smells → `plugins/kc-conventions/skills/kc-clarity/SKILL.md`
   - Code placement, dead wrappers, exports, enums/discriminators → `plugins/kc-conventions/skills/kc-structure/SKILL.md`
   - Reuse / DRY / not-reinventing existing primitives → `plugins/kc-conventions/skills/kc-simplicity/SKILL.md`
   - Dates, times, timezones, locale-dependent formatting → `plugins/kc-conventions/skills/kc-datetime/SKILL.md`
   - React/data-fetching/forms/component-structure conventions → `plugins/kc-conventions/skills/kc-react/SKILL.md`
   - Rails models, layers, queries and N+1s, request risks, backfills, Rails specs → `plugins/kc-conventions/skills/kc-rails/SKILL.md`
   - Translations / locale keys → `plugins/kc-conventions/skills/kc-i18n/SKILL.md`
   - Test coverage, assertions, test setup, test placement → `plugins/kc-conventions/skills/kc-testing/SKILL.md`
   - Logic bugs, edge cases, data-shape mismatches, regressions of fixed bugs → `plugins/kc-conventions/skills/kc-correctness/SKILL.md`
   - A new deterministic sweep → a script in that topic's `scripts/`, listed under its `## Sweeps`, with a fixture in `plugins/kc-conventions/tests/sweeps/`
   - Receipts one gate must show for another → `plugins/kc-gates/agents/verification-gate.md`
   - How a gate agent works (inputs, procedure, verdict shape) → `plugins/kc-gates/agents/<gate>.md`
   - PR scope, stacking, linked issues, reading large diffs → the scope checks in this `SKILL.md` (Step 1)
   - PR comment format, label, tone, posting protocol → `plugins/kc-gates/skills/kc-post-review/SKILL.md`
   - Workflow change, output format change, hard rule → this `SKILL.md`
   - Feedback that is specific to one target repo, not a general rule → suggest the user add it to that repo's own `.claude/review-conventions.md` instead of any file in this kit.

   A topic skill's `## Rules` section is copied into `plugins/kc-conventions/rules/kc-<topic>.md` by `scripts/build-rules.sh`; never edit `rules/` by hand. After changing a `## Rules` section, run `bash plugins/kc-conventions/scripts/build-rules.sh` to regenerate, and `--check` to confirm.

2. Update with a concrete pattern, a *why*, and a canonical file path, rather than abstract rules. Concrete examples that future-Claude can grep for beat general principles every time.

3. When adding a new convention, always include at least one canonical file path so future-Claude can verify the convention is real before citing it.

4. **Inline code examples must use generic names AND a generic shape, not specific identifiers OR the specific operation from the case that triggered the update.** Use placeholders like `flagA`, `flagB`, `mode`, `valueByMode`, `someBoolean`, `predicateA`, not identifiers lifted from the current task. Just as important: do not frame the rule around the *operation* that happened to trip it. If a multi-line ternary with a `.filter()` branch triggers the rule, the rule is "multi-line/non-trivial-branch ternaries," NOT "ternaries with `.filter()`"; the branch could be anything. Naming the trigger operation in the rule narrows a general rule to one instance and is exactly how the next instance slips through. State the shape/principle; treat the operation as incidental.

4.5. **Express every rule as a checklist of independent failure modes.** When adding or refining a rule, break it into discrete boxes a reviewer can tick one by one. Failing any single box is a finding (see the Hard Rules). A rule written as one prose blob invites "eh, close enough"; a checklist forces a yes/no per failure mode.

4b. **Every topic skill with a gate MUST carry a `## Review checklist` block, and every new rule MUST add a box to it.** The gate agents read that block to know what to tick, so a rule that lives only in prose is invisible to its gate. When you add or change a rule, update that skill's `## Review checklist` in the same edit: one box per independent failure mode, each box self-contained enough that an agent can mark it PASS / FAIL / N/A against a diff. A box must state its own N/A condition (e.g. "or N/A: no form schema in diff") so the agent never has to guess whether a silent gate means pass or skip.

5. Keep `SKILL.md` lean. If a section grows beyond a few paragraphs, move it to the agent or topic skill that owns it and replace it with a one-line summary plus pointer.

6. **Hard cap: every `SKILL.md` and agent file stays under 500 lines.** When a topic skill crosses that line, move a cluster of its `## Review detail` into `skills/kc-<topic>/references/<cluster>.md`, linked from the section it replaces by its `${CLAUDE_PLUGIN_ROOT}/skills/kc-<topic>/references/<cluster>.md` path so a gate can read it (examples: `kc-clarity/references/ternaries.md`, `kc-react/references/forms.md`). Keep `## Rules`, `## Review checklist` and `## Sweeps` in `SKILL.md`: `build-rules.sh` reads only `## Rules`, and gates tick only the checklist. Do not let a single file become a kitchen sink.

7. **Splits group by topic, not by physical proximity.** When the 500-line cap forces a split, factor out a *cluster of related rules*, not a single section, and not a grab-bag of whatever happened to be adjacent. A rule that applies broadly to "any unit of code" or "anywhere in the codebase" belongs in the general topic it was already in, not in a narrower one, just because it sat next to that topic's rules in the source.

8. **Do not over-fragment.** Keep small sections inline. A short section does not warrant its own file; splitting would create navigation friction without solving any real organization problem. The signal for a split is *a heavy-reference cluster* (100+ lines or several tightly-related rules), not "every section deserves its own file."
