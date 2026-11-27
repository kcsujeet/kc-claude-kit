---
name: kc-assess
description: Use at the start of a task, before building a fix: claims check, reproduce the failure first, trace a "reverted" or "stopped" report, list every reader of the broken value, compare a changed look with its reference.
---

# Assess a task

Step 1 of `kc-conventions:kc-do-a-task`. Do this before any code, then present the cause and the fix with the rules it follows. Examples and the full wording of each step: `references/detail.md`.

## Steps

1. Check the task is not already someone else's: `task-claims.sh <key> --repo <owner/name>`, once per repository it may touch. Assigned to another, or a change open: stop and ask whether to build, review that change or leave it. A cleanup that deletes files also passes `--deleting <path>` and deletes only the `mine` ones.
2. Check overlap by code: `task-claims.sh <key> --repo <owner/name> --path <file>... --since <commit>` (`--since` in a checkout). Run it again before the PR is marked ready; if that code changed, ask.
3. Read the issue and everything it links (recordings, designs, logs).
4. Reproduce the failure first, the way the reporter met it: their entry point, runtime and version, environment, real-shaped data. A copy of one layer is not a reproduction.
5. Read what the failing run records (request and status, log line, stack trace) before reading code; a cause reasoned from code alone is a guess.
6. Put a `Reproduced:` line per problem in the proposal (§AS1), or `Not reproduced: <why>`. The person's approval of the proposal comes before any build.
7. Trace a "changed, regressed, reverted or stopped" report from what is running back to the source: live build, whether it holds the change, `git log` on the file.
8. Before proposing anything new, list how the codebase already does the same job, with paths, searching by the job; a new unit says why none fits.
9. Answer what you can before asking (code, `git log -S <text>`, the task's links). Ask only what is left, in words that stand alone, with options, evidence and your pick.
10. A result unlike what the person entered or the task asks is a bug, never a question: reproduce it and fix it. Ask only about a call that is theirs.
11. A question from the person gets its answer and no edit; if it reads as doubt, ask whether to change it.
12. Keep what people have long relied on (a required field, a default, a layout) unless the task asks to change it; a change they would notice is a product call.
13. When the cause is a design that lets this bug happen, present the narrow fix and the design change side by side and say which to ship now.
14. List every reader of the broken value, with what each does with the bad case and whether the fix covers it.
15. For each reader a person reaches, state the state they are in; check the fix against what they see.
16. When the fix changes a look people hold against a reference, open the reference and show a picture of the change beside it before building.
17. Stop for approval when the fix makes a call that is the person's (§AS2 to §AS7) or they asked to see it first; otherwise state cause and fix in a few lines. New storage, a new unit or moved behaviour gets its shape approved first (`kc-conventions:kc-shape-the-change`).

## Gate checklist

- [ ] §AS1 Reproduced: <entry point, environment, data, what was seen>, or Not reproduced: <why>, in every cause-and-fix proposal; a copy of one layer is no reproduction. (N/A: no problem reported)
- [ ] §AS2 Asked only what is the person's to decide (two readings, a product call, scope past the request, an irreversible action), first in the message, ending the turn before dependent work.
- [ ] §AS3 Any other choice of approach was made: the fewest lines and moving parts a test or run can prove, said in a line with why; no options offered that you could rank.
- [ ] §AS4 Asked before changing a public API shape, a database schema or a shared contract package, and before choosing which kind of gate a change goes behind, and at what level.
- [ ] §AS5 No invented product decisions, user-facing copy or acceptance criteria; each specific added was checked against the person's words or cut.
- [ ] §AS6 Scope not widened: the adjacent problem is noted as its own follow-up; a shared file was edited with an exact edit of your own entry and its diff read afterwards.
- [ ] §AS7 An unresolved assumption is said at the top of the summary; a check covering part of a set says which part and why before it runs.
- [ ] §AS8 The convention skills for each topic the change touches were read and the plan checked against them before code; review is the second check.
- [ ] §AS9 After a command that installs or updates plugins, the person was asked for `/reload-plugins` before the next step (kc-gates checks).
