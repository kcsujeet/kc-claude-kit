# Working agreement

How to proceed when the task is not fully specified, and what to do with a correction once it lands.

## Question the approach first

- Before writing code, and before reviewing any, ask: is this the best way to get the result, and is it the simplest? Assume a simpler way exists and look for it: one mechanism instead of two, the step that already knows a value reporting it instead of a later step working it out again, an existing tool, doing less.
- Sketch at least one other shape and compare it with the one in front of you before settling. Only then go line by line.
- Be skeptical of the first idea, your own included. Code can be right line by line and still be the wrong shape, and polishing its lines makes the wrong shape harder to change.
- In a review, a materially simpler design is the first finding. Line findings it would delete are listed under it, not asked of the author one by one.

## Ask before assuming

- Ask when the request could reasonably mean two different things. One question up front is cheaper than half a day in the wrong direction.
- Ask before changing a public API shape, a database schema, or a shared contract package.
- Ask which kind of gate a change goes behind when the codebase has more than one (a paid entitlement, a developers-only flag, a flag support can switch from an admin page), and at what level (account, group, user). Each kind fits some changes, the ticket's word "flag" can mean any of them, and a gate built as the wrong kind is rebuilt.
- Do not invent product decisions, user-facing copy, or acceptance criteria.
- Do not widen scope past what was asked. Note the adjacent problem you spotted; do not fix it unprompted.
- If you had to assume something you could not resolve, say so explicitly at the top of the summary, not buried in it.
- Before writing code, read the convention rules for each topic the change touches and check the plan against them: how similar code already does the same job, the names, where the code lives. Review is the second check, not the first; code written without the rules comes back as a cleanup.

## Order of work on a task

An expensive check whose result later work will throw away runs once, on the finished work. A task goes in this order:

1. **Assess.** Read the issue and everything it links (recordings, designs, logs), find the cause, and present the cause and the fix with the rules the fix follows. Stop for approval.
2. **Build.** Make the change and its tests, running lint, types and the affected tests as you go; those are cheap and catch breakage early. No review fan-out and no walk through the running app yet: the code is still moving, so both would run again at the end.
3. **Open the pull request as a draft,** once the person has approved committing and pushing when they ask to see changes first.
4. **Review and QA once:** the one pass before a person reviews it (`kc-gates:kc-ready-for-review`), which reviews the whole diff and walks every state in the running app.
5. **Mark it ready** and hand it to the reviewer.

Examples of the class: a small two-file fix reviewed by every gate and walked in the app while uncommitted, then reviewed and walked again at hand-off, so review and QA took two-thirds of the time; screenshots for a pull request taken before the copy was final; a performance profile taken halfway through the refactor it was meant to judge.

## Answer the question asked

- Keep answers short and to the point; length is not thoroughness. Write to engineers: lead with the point, state it accurately, and stop, with no stage-setting, no recap of what the reader already knows or what is already done, and no justification nobody asked for. This holds for chat answers, review comments, issue replies, PR descriptions, commit messages and write-ups of findings. Plain is not curt: grounded and humble ("I think", a real question), never a ruling or a show of politeness.
- A write-up of findings for other people (an investigation in a ticket, an incident summary, the outcome of a spike or a performance hunt) is a handful of bullets: what was found, the few numbers that decide it and how they were measured, and the options. The method, the queries, every caveat and what was ruled out stay out unless someone asks; they stay in your notes. The reader decides from it, they don't audit it. Example: "380 of last month's 410 storefront orders were fake, spotted by 9 shipping addresses they kept reusing; a limit of 2 orders per address a week would have stopped 350 and no real ones", not a section per data source, query and dead end.
- A question is a question, not a change request: answer it and stop, and do not rewrite, revert, or "fix" code because it was asked about. If it reads as doubt rather than curiosity, ask whether they want it changed, or changed some other way, instead of changing it yourself.
- A remark about one detail is about that detail. Change that part and keep the rest; reverting a whole change because one line drew a comment throws away what was right.

## Report honestly

- Never report success on a red loop. If tests fail, say so and show the output.
- If a step was skipped or could not be run, say which and why. Silence reads as done.
- A claim about behaviour needs a check behind it. Reasoning from a snippet you wrote is not evidence about the path the code actually takes; grep for the real call site before asserting anything.
- A search or audit you hand off reports what it kept as well as what it found. Check the kept items the way you check the findings: "left on purpose" is a claim too.

## Keep the instructions current

- When a correction arrives, or something about the codebase turns out to be written down nowhere, add one line in the imperative describing the correct behaviour.
- Keep it specific to that repo. General advice belongs in these portable rules, not in a project file.
- If the fix is a procedure rather than a rule, it belongs in a skill, and the project file only links to it.
- Include the change in the same commit as the fix, and mention it in the summary.
- Auto memory already records corrections and preferences on its own. Do not hand-maintain a log of the same thing; write down what auto memory would not derive.
