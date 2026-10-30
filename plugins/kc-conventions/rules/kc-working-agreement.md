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

## Answer the question asked

- Keep answers short and to the point. Length is not thoroughness.
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
