---
name: review-code
description: Gate-based code review for a PR, branch, or set of changes in any repo. Trigger on "review this PR", "review my code", "review my changes", "review my branch", "is this clean", "is this good to merge", "code review please", a bare PR URL, or a branch name. Fans out one subagent per rule file (naming, clarity, structure, simplicity, datetime, react, i18n, project conventions, verification), aggregates per-box PASS/FAIL verdicts into a single PASSED/FAILED result. Reads the target repo's own .claude/review-conventions.md as an extra gate when present. Output stays in chat only - never posts comments to the PR without explicit approval.
---

# Reviewing code

This skill reviews a diff against a fixed set of quality gates, plus any repo-specific conventions the target project declares for itself.

A regular review catches bugs. The things that slip through review are: convention drift, code placed in the wrong layer, duplicated logic that already exists somewhere else, and code that takes three readings to understand. That is what this skill is for.

## Hard rules

- **Failing even ONE checklist item is worth raising.** Many rules are expressed as a checklist of failure modes (e.g. a ternary rule listing nested / long / multi-line / non-trivial-branch as independent failure modes). A code item that trips a *single* box is a finding — do NOT wait for two or three boxes to fail, and do NOT decide "it's only one of the conditions, that's fine." Walk each box independently and raise on the first failure. (Severity still calibrates per the rubric below; "worth raising" can be a 🟡, but it gets raised.) The recurring miss is pattern-matching a rule to its example domain — e.g. reading a "ternary" rule as "JSX ternaries only" and skipping a multi-line *value* ternary — so apply each checklist to every matching construct, not just the ones that look like the example.
- **Apply DRY, YAGNI, and KISS as a standing lens on every diff — not just the specific checklists.** Evaluate every change against three questions and surface a finding whenever the answer is "no", with the same any-finding-fails weight as any other rule:
  - **DRY** — is any logic, value, literal, or markup duplicated that should be a single source? A copied block, a re-declared constant, a re-implemented helper.
  - **YAGNI** — is there speculative or unused code? Unused params/props, an abstraction with a single caller built for a hypothetical second one, config options nothing passes, dead branches, a generality the diff doesn't use.
  - **KISS** — is there a materially simpler equivalent? A lookup object beating nested conditionals, an early return beating nesting, an existing util/stdlib call beating a hand-roll, fewer moving parts for the same behavior.
  These are first-class smells, not stylistic extras. Surface them with evidence and let the user judge (per the surface-everything rule); never withhold one because you decided the complexity was "probably needed".
- **Never post anything to GitHub on your own.** No `gh pr review`, no `gh pr comment`, no `gh api` writes. Output stays in chat. If the user asks to post, follow the drafting + explicit-signal protocol in `references/pr-comments.md`.
- **Verify conventions against the codebase before flagging.** Do not cite a "convention" from memory. Before saying "this codebase does it like X", grep the repo and confirm there are at least 2-3 existing examples of X. Cite the example file paths in your finding.
- **Before flagging, confirm it's actually a deviation — not a misread.** Some things look wrong in isolation but are the house style when you grep. Grep to confirm the thing genuinely deviates from how the codebase does it, and cite the evidence. This check is about ACCURACY (don't raise a non-issue based on a misunderstanding) — it is NOT a license to suppress. Once something genuinely deviates from a rule, you surface it; see the next two rules.
- **Surface everything you find. Do NOT make the "is it acceptable / intentional" call yourself — that is the user's (and the PR author's) judgment, not yours.** Your job is detection and reporting. NEVER drop a finding, and never soften it to "this is fine / probably intentional / defensible / low-value / pure conformance so skip it," because you decided it was intended or not worth it. If you found it, you report it, with evidence, and let the human decide whether it's okay. "Intentional" / "defensible" / "matches the neighbors" / "low-value" are descriptions you may add for the human's benefit — never reasons to withhold.
- **Any finding fails its gate. There is no finding that "still passes."** A gate is PASS only when nothing is found in it; the moment one thing is found, that gate is FAIL and the overall verdict is FAILED. Severity labels (🔴/🟠/🟡, issue/suggestion/nitpick) calibrate only the *weight communicated to the author* — they do NOT affect whether the finding is reported or whether the gate passes. A single 🟡 nitpick fails its gate and therefore the review. Report FAILED plainly; never round up to "looks good with minor nits."
- (Self-review parallel: when reviewing *my own* work, precedent never excuses a violation either — the same surface-everything bar applies before I call work done.)
- **When a rule lists examples, examples are illustrations, never an exhaustive boundary.** State the principle first, examples second, explicitly labeled as illustrations. Apply the rule to *every* item in the diff that matches the principle, including items not in the example list. If you find yourself thinking "this item isn't in the listed examples so the rule doesn't apply," you're misreading the rule. This applies BOTH when reading rules (don't narrow to the listed examples) AND when writing rules (don't frame a rule around a specific domain when the principle is general).
- **Brevity is a hard rule on every surface: chat findings, drafted comments, and replies.** Length is the most consistently violated rule in this skill. Every unit of output has a budget, and a sentence past it must earn its place: **a chat finding is one line**, **a drafted comment is one to three sentences**, **a reply accepting feedback is one sentence plus the commit SHA**. Prose that restates the rule, justifies a change the reader already asked for, re-describes what a linked commit shows, or explains the reasoning behind a finding whose fix is already stated does NOT earn its place; cut it. If the reader needs the why, they will ask. Count before you show: an over-budget unit is a rewrite *before* the user sees it, never after they ask you to shorten it.
- **Read the actual changed code yourself** with the `Read` tool, after fetching the diff. Subagent summaries are a starting point — the specific issues live in specific lines and you need to see them to call them out usefully.
- **Cite line numbers, file paths, and head SHA** for every finding. Vague feedback is useless.
- **Locale diffs require a per-key audit table — never an aggregate grep, never your memory.** This is enforced by the i18n gate agent: if the diff touches translation/locale files, that agent must produce a per-key audit table (one row per new key, checking namespace placement, pluralization, naming, and duplication — see `references/i18n.md`) as its evidence, and a missing/incomplete table is a gate FAIL. You may NOT write any locale verdict — including "no new keys", "no issues this round", or silently dropping i18n from the checklist — without the table. An aggregate report ("greped N keys, all unique") is an automatic incomplete review: a direct-duplicate grep alone cannot catch a generic noun that belongs in a shared strings file, a singular-only label that should be a plural-aware key, or a key whose name doesn't match its own value. "It matches the neighbors" / "low-value" / "no new keys" are the three rationalizations that have caused this miss — none of them is valid without the table.

## Workflow — agent-driven gates

The review is NOT a single inline pass. It is a fan-out of independent **gate agents**, one per reference file, aggregated into a single PASS/FAIL verdict. The whole fan-out runs **every time the skill is invoked — including every re-review after the author has addressed previous comments**. There is no delta-only, "I already looked at this", or "only the changed files since last round" shortcut: a re-review re-runs every gate against the new head SHA from scratch. A previously-passed gate can fail on a later round (the fix introduced a new violation), so each round earns its PASS independently.

**Why agents instead of inline:** an inline reviewer silently skips checklist items ("low-value", "matches the neighbors", "no new keys") — this has been the repeated failure mode. A dedicated agent that owns exactly one reference file and must return a per-box PASS/FAIL verdict has no other job to crowd it out, so it cannot quietly drop a box.

### Step 1 — gather context (you, the orchestrator)

Determine the target repo from the current working directory. Detect the default branch instead of hardcoding one, e.g. `git rev-parse --abbrev-ref origin/HEAD | sed 's|origin/||'`.

- Diff + head SHA + changed files: for a PR, `gh pr diff <num>` and `gh pr view <num> --json headRefOid,title,files`. For a branch: `git diff $(git rev-parse --abbrev-ref origin/HEAD | sed 's|origin/||')...HEAD` and `git rev-parse HEAD`.
- If the working tree is not on the head commit, fetch it (`git fetch origin pull/<num>/head:pr-<num>`) so the gate agents can read files at the exact head SHA via `git show <sha>:<path>`.
- **On a re-review, also fetch the reply threads on your previous comments and read what the author said.** `gh api 'repos/<owner>/<repo>/pulls/<num>/comments?per_page=100'` and group by `in_reply_to_id` to see each thread. For every carried-over finding, classify the author's reply before re-raising it:
  - **A commit SHA** = "fixed in `<sha>`". Verify it against head — and verify the WHOLE class, not just the examples you named. A common pattern: the author fixes the exact items you listed but leaves the rest of the same class; the finding is still open, but re-frame it as "the named ones are done; the same applies to the rest", not as if nothing changed.
  - **Reasoned push-back** (e.g. "this matches the existing pattern, keeping it") = do NOT silently re-post a fresh duplicate comment on a thread they already answered — that reads as ignoring them. Surface their reasoning to the user, and either drop the finding or reply in the existing thread with the counter-point; let the user decide.
  - **No reply / unaddressed** = re-raise, noting it is still open from the prior round.
  Carry the author's responses into Step 4 so the report and any re-drafted comments reflect what was fixed, what was declined-with-reason, and what is genuinely still open. Posting a re-review that ignores the author's replies is a documented trust failure.

### Step 2 — fan out gate agents in two phases (mandatory: ALL gates, EVERY round)

Dispatch gate agents (Task tool, `general-purpose` or `Explore`) in **two phases**: the eight rule gates run in parallel first; verification runs second, once all eight have returned, because it audits their returned verdict blocks rather than re-deriving findings. The registry maps each gate to exactly one reference file — each reference is checked by its own agent:

**Phase 1 — dispatch these eight in parallel:**

| Gate | Reference file | Dispatch note |
|------|----------------|----------------|
| naming | `references/naming.md` | always |
| clarity | `references/clarity.md` | always |
| structure | `references/structure.md` | always |
| simplicity | `references/simplicity.md` | always |
| datetime | `references/datetime.md` | agent returns PASS (N/A) if no date/time logic in diff |
| react | `references/react.md` | agent returns PASS (N/A) if no React/JSX UI code in diff |
| i18n | `references/i18n.md` | agent returns PASS (N/A) if no locale files in diff |
| project-conventions | `references/project-conventions.md` | agent returns PASS (N/A) if target repo has no `.claude/review-conventions.md` |

**Phase 2 — dispatch only after every Phase 1 agent has returned:**

| Gate | Reference file | Dispatch note |
|------|----------------|----------------|
| verification | `references/verification.md` | always; its prompt additionally includes every Phase 1 gate's returned `GATE:`/`STATUS:`/`BOXES:`/`FINDINGS:` block |

Every gate is dispatched even when it looks inapplicable. A gate whose rules don't apply returns `PASS (N/A)` **with the reason** — you do NOT skip dispatching it. "No hooks changed, so react is N/A" is a verdict the gate agent must produce after reading the diff, never an assumption you make on its behalf.

The `project-conventions` gate is how this skill stays repo-agnostic while still enforcing house rules: it reads the target repo's own `.claude/review-conventions.md` (if one exists) and grades the diff against whatever that file declares. A repo with no such file is legitimately N/A — it is not this skill's job to invent conventions for a repo that hasn't written any down.

### Step 3 — the gate-agent contract (include this in every agent's prompt)

Give each agent: the gate name, its single owned reference file path, the head SHA, the changed-file list, and the diff (or the commands to fetch them). The verification agent additionally receives every other gate's returned verdict block as input, since it audits those receipts rather than re-deriving findings. Require the agent to:

1. Read the ENTIRE owned reference file, including its `## Gate checklist` block.
2. **Sweep the greppable constructs FIRST, before reading the diff for meaning.** Some boxes cover constructs a grep can enumerate exactly, and those boxes are graded on whether the hits were **listed**, not on whether they were noticed. Run the grep over the diff's added lines, then give every hit a `file:line` verdict in the evidence, with the hit count. `0 hits` must be stated explicitly; a box with no receipt is FAIL by default, because silence is indistinguishable from never having looked.
3. Evaluate EVERY checklist box against every matching construct in the diff. Before failing a box on a convention, grep the target repo to confirm the convention is real (cite 2-3 example paths in the evidence).
4. Return ONLY this structured verdict:
   ```
   GATE: <name>
   STATUS: PASS | PASS (N/A) | FAIL
   BOXES:
   - [PASS|FAIL|N/A] <box id> — <evidence: file:line, grep result, or "no matching construct in diff">
   FINDINGS:
   - <severity 🔴|🟠|🟡> <file>:<line> — <issue> — <fix>
   ```
5. Failure semantics: a box is **FAIL** if ANY matching construct in the diff violates it; the gate STATUS is **FAIL** if ANY box is FAIL. Do not average, do not "mostly pass".

### Step 4 — aggregate into one verdict (you, the orchestrator)

- Overall verdict is **PASSED** only when every gate returned `PASS` or `PASS (N/A)`.
- **A single FAIL box in any one gate ⇒ overall FAILED.** State plainly that the review has not passed and the author needs further changes; do not soften a FAILED into "looks mostly good" or "just nits". A nitpick-severity finding still fails its box and therefore the review — severity calibrates the *comment*, not whether the gate passed.
- **A gate PASSES only when it found nothing. Any finding = that gate FAILED.** Do not let a gate agent (or yourself) return PASS while also listing a finding — that is contradictory and means FAIL. Aggregate by surfacing every finding from every gate; never drop or merge-away a finding because you judged it intentional/acceptable (that call is the user's — see Hard rules). The report lists all findings found, and the verdict is FAILED if the list is non-empty.
- Emit the gate-status table first, then the deduped findings, then the explicit `PASSED`/`FAILED` verdict (see Output format).
- On a re-review, run Steps 1-4 again in full, and fold in the author's replies to your prior comments (Step 1): mark each carried-over item as fixed (verify the whole class), declined-with-reason (surface it, don't re-post over their reply), or still-open. Report the new verdict; do not carry forward a prior round's PASS.

**Self-review trigger:** when *I* am the one implementing changes (not reviewing a teammate's PR), the same gate fan-out applies before I declare work "complete" / "verified" / "ready for review". Lint and types passing is not the same as gate-clean. For a small self-review I may run the gates inline rather than spawning agents, but every gate's checklist must still be walked box-by-box and reach a PASS before I call the work done.

**"Matches the existing pattern" is a yellow flag, not a green light.** A gate agent must not pass a box because the diff copied the shape of nearby code. If the surrounding pattern violates the rule, the new code that extends it violates it too. Every copied block, every matched helper, every duplicated key style is evaluated against the rule on its own; nearby precedent is not the evaluation.

## Output format

Report directly in chat. No file output. **Be terse.** The reader is the user, not the PR author — they want to scan, not read prose.

**Rules:**
- One finding = one line. Two short lines max if a fix snippet is genuinely needed. This is a budget, not a target to fill; most findings fit in one line and should stay there.
- **No explanation paragraphs anywhere in the report** — not under a finding, not under the verdict, not as a preamble to a section. The gate table, the finding line and the fix carry the whole message.
- Prefix every finding with a severity color so the user can scan weight at a glance: 🔴 must-fix (real bug, regression, security, drift from a stated convention), 🟠 should-address (correctness gap, validation hole, behavior question that needs an answer), 🟡 low (style, naming, nit, cleanup). Use the same three colors in the chat draft list when previewing PR comments. These emojis are chat-only: never put them in the posted PR comment bodies, where the Conventional Comments label (`issue` / `suggestion` / `nitpick`) carries the weight instead.
- Lead with the file:line. Then the issue. Then the fix (as inline code or short phrase, not a code block, when it fits).
- No code blocks unless the suggested fix is multi-line and cannot be expressed inline.
- No "explanation" paragraphs. The fix implies the reasoning. If the reader needs the *why*, they will ask.
- Do not repeat the same finding under two gates. Pick the closer fit.
- Skip a section header entirely when the section is empty.

**Format:**

```
### Review: <PR title>
**Head:** `<short-sha>` · **Verdict:** ✅ PASSED | ❌ FAILED (<n> gate(s) failing)

**Gate status:** (one row per gate, every round)
| Gate | Status |
|------|--------|
| naming | ✅ PASS / ❌ FAIL / ⚪ N/A |
| clarity | ... |
| structure | ... |
| simplicity | ... |
| datetime | ... |
| react | ... |
| i18n | ... |
| project-conventions | ... |
| verification | ... |

**Naming:**
- 🔴 `<file>:L<n>` — <issue>. <fix as inline code or short phrase>.
- 🟡 `<file>:L<n>` — <issue>. <fix>.

**Clarity:**
- 🟠 `<file>:L<n>` — <issue>. <fix>.

**i18n:** (paste the per-key audit table from the i18n gate when locale files changed)

**Possible bug:** (only if a gate agent spotted one while reading)
- `<file>:L<n>` — <one-liner>.

**Checklist:** (one line per applicable trigger group, per `references/verification.md`'s "How to use this in the output" — a cited receipt, or `n/a, diff does not touch X`)
- Always: <files read at sha, findings cite file:line + sha, nothing posted to GitHub>.
- <trigger group>: <receipt, or "n/a, diff does not touch X">.

**Overall:** <one short sentence; if FAILED, name what must change for the next round to pass>.
```

The **Gate status table is mandatory and leads the report** — it is the receipt that every reference file was checked by its agent this round. A review without the full table (all gates listed, each with PASS / FAIL / N/A) is incomplete. The top-line **Verdict is FAILED if any gate is FAIL**, full stop; do not report PASSED with a failing gate, and do not omit a gate to make the table look clean.

**Each gate's verdict reflects every box in its reference file, not just the headline rule.** A gate agent reports `PASS` only after walking every box in its `## Gate checklist` and citing evidence for each. A vague "naming looks fine" from an agent is a rejected verdict — send it back for the per-box `BOXES:` breakdown.

**Examples of good vs bad findings:**

Bad (too wordy, paragraph-shaped):
> 1. **Opaque local names — `current` / `prev`** — `Widget.tsx:63-66`
>    In this function, `current` is "the new item" and `prev` is "the previously removed item." A reader has to trace through the logic to figure that out. Suggested: `newItem` / `previouslyRemovedItem`.

Good (single line, fix in-place):
> - `Widget.tsx:63,66` — `current` / `prev` are opaque. Rename `newItem` / `previouslyRemovedItem`.

Bad:
> 4. **Magic spread + override + default mix** — `Widget.tsx:72-77`
>    Three different things happening in one literal: spread, override, default. Reads cleaner as a named helper: ...

Good:
> - `Widget.tsx:72-77` — Spread + override + default in one literal. Extract a named `revivedItem`.

If the whole PR looks clean, one line:

```
### Review: <PR title>
`<short-sha>` `<file>` — follows existing conventions and naming. No changes.
```

## Drafting and posting PR comments

When the user asks to draft, post, or convert findings into PR comments, switch from the terse chat format to Conventional Comments. **Read `references/pr-comments.md` for the full format, label table, tone rules, worked examples, and the load-bearing "wait for an explicit, fresh post signal" protocol.**

The three rules to internalize before reading the reference:
- The label-on-its-own-line layout is mandatory: `**<label>**:\n<body>`.
- Posting requires a fresh, standalone "post" / "go ahead" signal *after* the user has seen the latest draft set. Combined-intent messages ("show me and post") do not count as authorization.
- A reply to feedback on our own PR is **one sentence plus the full SHA**, unless one of three listed exceptions applies. Restating the reviewer's point, justifying a change they asked for, or listing what the commit already shows all get cut before the drafts are shown.

## What this skill is not

- It is not a bug scan. If you spot a real bug while reading, mention it under "**Possible bug:**" but do not let bug-hunting take over — the user has other tools for that.
- It is not a generic style linter substitute and it is not a security review. Stay focused on the nine gates above plus any repo-declared conventions.
- It does not post to GitHub on its own.

## Notes for iteration

This skill is in active iteration. When the user gives feedback ("you missed X", "you flagged a non-issue Y", "we have a convention for Z"):

1. Identify which file the feedback belongs in:
   - Identifier naming → `references/naming.md`
   - Ternaries, comments, magic numbers, other readability smells → `references/clarity.md`
   - Code placement, dead wrappers, exports, enums/discriminators → `references/structure.md`
   - Reuse / DRY / not-reinventing existing primitives → `references/simplicity.md`
   - Dates, times, timezones, locale-dependent formatting → `references/datetime.md`
   - React/data-fetching/forms/component-structure conventions → `references/react.md`
   - Translations / locale keys → `references/i18n.md`
   - PR comment format, label, tone, posting protocol → `references/pr-comments.md`
   - Workflow change, output format change, hard rule → this `SKILL.md`
   - Feedback that is specific to one target repo, not a general rule → suggest the user add it to that repo's own `.claude/review-conventions.md` instead of any file in this skill.

2. Update with a concrete pattern, a *why*, and a canonical file path — rather than abstract rules. Concrete examples that future-Claude can grep for beat general principles every time.

3. When adding a new convention, always include at least one canonical file path so future-Claude can verify the convention is real before citing it.

4. **Inline code examples must use generic names AND a generic shape — not specific identifiers OR the specific operation from the case that triggered the update.** Use placeholders like `flagA`, `flagB`, `mode`, `valueByMode`, `someBoolean`, `predicateA` — not identifiers lifted from the current task. Just as important: do not frame the rule around the *operation* that happened to trip it. If a multi-line ternary with a `.filter()` branch triggers the rule, the rule is "multi-line/non-trivial-branch ternaries," NOT "ternaries with `.filter()`" — the branch could be anything. Naming the trigger operation in the rule narrows a general rule to one instance and is exactly how the next instance slips through. State the shape/principle; treat the operation as incidental.

4.5. **Express every rule as a checklist of independent failure modes.** When adding or refining a rule, break it into discrete boxes a reviewer can tick one by one. Failing any single box is a finding (see the Hard Rules). A rule written as one prose blob invites "eh, close enough"; a checklist forces a yes/no per failure mode.

4b. **Every reference file MUST carry a `## Gate checklist` block, and every new rule MUST add a box to it.** The gate agents read that block to know what to tick, so a rule that lives only in prose is invisible to its gate. When you add or change a rule in a reference file, update that file's `## Gate checklist` in the same edit: one box per independent failure mode, each box self-contained enough that an agent can mark it PASS / FAIL / N/A against a diff. A box must state its own N/A condition (e.g. "or N/A: no form schema in diff") so the agent never has to guess whether a silent gate means pass or skip.

5. Keep `SKILL.md` lean. If a section grows beyond a few paragraphs, move it to a reference file and replace it with a one-line summary plus pointer.

6. **Hard cap: every `.md` file in this skill stays under 500 lines.** When a reference file crosses that line, split it by topic into a new sibling file in `references/`, leave a one-paragraph pointer at the original section, and update SKILL.md so reviewers know where to look. Do not let a single reference file become a kitchen sink.

7. **Splits group by topic, not by physical proximity.** When the 500-line cap forces a split, factor out a *cluster of related rules* into a dedicated topic file — not a single section, and not a grab-bag of whatever happened to be adjacent. A rule that applies broadly to "any unit of code" or "anywhere in the codebase" belongs in the general gate file it was already in, not in a narrower topic file, just because it sat next to that topic's rules in the source.

8. **Do not over-fragment.** Keep small sections inline. A short section does not warrant its own file — splitting would create navigation friction without solving any real organization problem. The signal for a split is *a heavy-reference cluster* (100+ lines or several tightly-related rules), not "every section deserves its own file."
