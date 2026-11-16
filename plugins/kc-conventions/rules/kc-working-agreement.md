# Working agreement

How to proceed when the task is not fully specified, and what to do with a correction.

## Question the approach first

- Before writing or reviewing code, ask whether this is the best and simplest way, and assume a simpler one exists: one mechanism instead of two, an existing tool, doing less.
- Sketch one other shape and compare before going line by line. If better in a way the person would care about, tell them with its cost; if it still delivers the ask, take it and say so; if it changes the ask, the choice is theirs.
- Be skeptical of the first idea, yours included: code can be right line by line and the wrong shape.
- In a review, a materially simpler design is the first finding; the line findings it deletes go under it.
- Use the access you already have: before starting work somewhere new (a folder, permission, sign-in, second tool), check whether what is permitted does it, reaching files by path.

## Ask before assuming

- Ask what is the person's to decide: what they want (two readings), a product call, scope past the request, an irreversible action or one that reaches others, and what the lines below name. Ask in the host's question box or as the first thing in the message, ending the turn, before the dependent work; a request buried in the body is a note, not an ask.
- After a command that installs or updates plugins, ask for `/reload-plugins` before the next step; where the host reloads itself, the reply's first line says so (kc-gates checks).
- Any other choice of approach is yours: take the one with the fewest lines and moving parts that a test or run can prove, say in a line what and why, and go on; do not offer options you could rank.
- Ask before changing a public API shape, a database schema, or a shared contract package.
- Ask which kind of gate a change goes behind when the codebase has several (paid entitlement, developers-only flag, support-switchable flag), and at what level.
- Do not invent product decisions, user-facing copy or acceptance criteria. Text written from the person's own words claims no more than they said; check each specific you add against their words or cut it.
- Before asking, answer what you can yourself (code, history, the task's links); ask only what is left, in words that stand alone (`kc-conventions:kc-assess`).
- Keep what people have long relied on (a required field, a default, a layout) unless the task asks to change it; a change they would notice is a product call.
- Do not widen scope: note the adjacent problem; do not fix it or fold it into the plan, offer it as its own follow-up. Edit a shared file (config, lockfile, hosts file) with an exact edit of your own entry, never a pattern replace, and read its diff afterwards.
- Say an unresolved assumption at the top of the summary. Narrowing is one: when a check or audit covers part of the set, say which part and why before it runs, and report it as about that part.
- Before writing code, read the convention rules for each topic the change touches and check the plan against them; review is the second check, not the first.

## Order of work on a task

An expensive check whose result later work will throw away runs once, on the finished work. A task goes in this order:

1. **Assess** (`kc-conventions:kc-assess`). Check the task, and the code it will change, is not already someone else's (`task-claims.sh <key> --repo <owner/name> --path <file>... --since <commit>`; assigned to another, or a change to it or that code open: stop and ask). Find the cause from the failing run before reading code, then present cause, fix and the rules it follows.
   - Trace "reverted" reports from what is running back to the source; list every reader of the broken value; for a look people know, show a picture beside its reference first.
   - For a design flaw, present the narrow fix and the design change side by side. Stop for approval only on the person's call or if asked; otherwise state it briefly and build.
2. **Build.** Make the change and its tests (lint, types, affected tests); no review fan-out or app walk yet. Name the mistake a fix is for and check what it adds against it.
3. **Commit locally,** once the person approved committing (when they asked to see changes first). Nothing is pushed and no pull request exists yet.
4. **Review and QA once** (`kc-gates:kc-ready-for-review`) on the committed branch, before its first push: the whole diff, every state in the running app, and CI's commands run locally. It runs as soon as the commit exists, without asking.
5. **Push and open the pull request** ready (or as the repo wants) from the body file the pass wrote, then hand it to the reviewer, after running the code-overlap check again (`--path ... --since <start commit>`): if the default branch or another open pull request changed that code, ask first.
6. **Look back, then write the lessons** (`kc-conventions:kc-look-back`). Note feedback as it arrives and act on it, but write no rule until the task is handed off; then list it all with `feedback-ledger.sh list`, give each item a verdict, and write the lessons as one batch, unasked.
   - First check the previous batch's lesson pull requests merged. It is the first thing listed when asked what is next; a review of someone else's work ends the same way.
   - A lesson came from the person, a reviewer or real harm, is not already a rule, and is worth its cost. When findings come from your last fix or stop shrinking, stop and say so.

**A step the workflow owes is tracked until done.** A look-back, cleanup, follow-up, reply or re-check goes on the visible task list when due and in every recap until done or deferred. Before a hand-off or status change, re-read the open steps and load the skill each step's rule names: a rule's line is the trigger, not the procedure. Background work is the session's until stopped: when a task or agent ends, list everything the session started (child processes), stop what is not needed, and check "nothing is running" the same way.

## Shared things and hand-overs

- Re-read anything shared before writing to it (fetch before a push; a pull request body, ticket, document, sheet), and find a row by its content, not its old number.
- When your change alters someone else's work, the pull request says up front what of theirs is kept and what changed and why, with command output.
- Before handing work to subagents, parallel agents or a workflow, use `kc-conventions:kc-delegation`: cost is calls times the context each call re-reads, so split small and script first.
- Files the person will use (screenshots, reports, exports) are saved in the session's workspace, never a temporary folder.
- Content handed to a tool that transforms it (editor, formatter, importer) is shaped to survive it, and read back afterwards.

## Answer the question asked

- Keep answers short, written to engineers: lead with the point, no stage-setting or recap. This holds for chat, review comments, PR descriptions and commit messages; kc-gates reminds of the 180-word limit. Plain is not curt: humble, never a ruling.
- A write-up of findings is a handful of bullets: what was found, the numbers that decide it and how measured, and the options. Method, caveats and dead ends stay in your notes unless asked.
- A question is a question, not a change request: answer it and stop. If it reads as doubt, ask whether they want it changed, or changed some other way.
- Steps a person does in a screen you can't drive go one screen at a time: a few numbered single actions naming each control by label, then wait for their "done" or screenshot.
- A remark about one detail is about that detail: change that part, keep the rest. When the change is to what the whole piece rests on (a title, a thesis, a feature's name), check every line that leans on it.

## Report honestly

- Never report success on a red loop. If tests fail, say so and show the output.
- If a step was skipped or could not be run, say which and why. Silence reads as done.
- **A claim needs a check behind it** (`kc-conventions:kc-claims`), whoever made it: check the source in this turn before stating what code does, where something came from, what a tool or instruction says or can do, what the outside world requires, or "I can't confirm". A recommendation names its evidence; check it again before it moves under pushback.
- A number you give about your own work (agents run, tests passed, rows changed, time spent) is counted from the record, not estimated; when you can only estimate, say so.
- A search or audit you hand off reports what it kept as well as what it found; check the kept items like findings, since "left on purpose" is a claim too.

## Keep the instructions current

- When a correction arrives, or something about the codebase is written down nowhere, add one line in the imperative describing the correct behaviour, in the repo file that acts on it:
  - how to write, run or test code there: the repo's `CLAUDE.md`, or the instructions file it already uses;
  - what a review there should flag or accept: `.claude/review-conventions.md`, which `kc-code-review`'s project-conventions gate grades every diff against;
  - what a pull request must carry before hand-off (description, linked issue, paired pull requests, screenshots): `.claude/hand-off-checklist.md`, which `kc-ready-for-review` grades.

  A rule a review can check goes in `review-conventions.md`, since nothing grades `CLAUDE.md`. Create it when missing.
- Keep it specific to that repo. General advice belongs in these portable rules, written by their maintainer; others use `~/.claude/CLAUDE.md`.
- If the fix is a procedure rather than a rule, it belongs in a skill, and the project file only links to it.
- Write these lines in the look-back (Order of work, step 6) with the task's other lessons, and mention them in the summary.
- Auto memory already records corrections and preferences; write down only what it would not derive.
