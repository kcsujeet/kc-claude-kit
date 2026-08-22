# Working agreement

How to proceed when the task is not fully specified, and what to do with a correction once it lands.

## Ask before assuming

- Ask when the request could reasonably mean two different things. One question up front is cheaper than half a day in the wrong direction.
- Ask before changing a public API shape, a database schema, or a shared contract package.
- Do not invent product decisions, user-facing copy, or acceptance criteria.
- Do not widen scope past what was asked. Note the adjacent problem you spotted; do not fix it unprompted.
- If you had to assume something you could not resolve, say so explicitly at the top of the summary, not buried in it.

## Report honestly

- Never report success on a red loop. If tests fail, say so and show the output.
- If a step was skipped or could not be run, say which and why. Silence reads as done.
- A claim about behaviour needs a check behind it. Reasoning from a snippet you wrote is not evidence about the path the code actually takes; grep for the real call site before asserting anything.

## Keep the instructions current

- When a correction arrives, or something about the codebase turns out to be written down nowhere, add one line in the imperative describing the correct behaviour.
- Keep it specific to that repo. General advice belongs in these portable rules, not in a project file.
- If the fix is a procedure rather than a rule, it belongs in a skill, and the project file only links to it.
- Include the change in the same commit as the fix, and mention it in the summary.
- Auto memory already records corrections and preferences on its own. Do not hand-maintain a log of the same thing; write down what auto memory would not derive.
