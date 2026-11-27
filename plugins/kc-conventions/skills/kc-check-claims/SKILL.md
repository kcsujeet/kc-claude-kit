---
name: kc-check-claims
description: Use before stating what code, a tool, a platform, an instruction, a source, a number or a requirement is or can do, before saying "I can't confirm" or "can't be done here", and before a recommendation or an example.
---

# A claim needs a check behind it

Applies to whoever made the claim: you, a review agent or a subagent. Check the source in this turn, then state the claim and cite what you found. Examples and the longer wording of each kind: `references/detail.md`.

## Steps

1. Before saying what code does, grep for the real call site; reasoning from a snippet you wrote is not evidence about the path the code takes.
2. Before saying where something came from (environment, account, version), read it from the material itself (address bar, host name, timestamp) or ask; never infer it from who sent it.
3. Check the facts a question is offered on before asking; the person decides on them.
4. Before planning around what a tool, platform or runtime can do, check that the version that will run it has it, in its docs or by trying it there.
5. Before handing the person a command to run, check the access it runs with (CLI login, keys, account) with a read-only command and fix what is missing.
6. Before saying what instructions require (the kit's rules, a CLAUDE.md, a checklist), read the rule and cite it.
7. Before saying "I can't confirm" or "I don't know", check every source that could settle it and cite what you found; a partial search is unfinished work. kc-gates names such a reply at the start of the next turn.
8. Before saying "X can't do that" or "this can't be done here", look it up that turn (docs, `--help`, a search, trying it on the version that will run it; every catalog that could hold the tool) and cite it (`check-reply-sources.sh`).
9. For what the world outside the code requires (a standard, regulator, carrier, vendor terms), open the authority's own text this session; a picture, a repo comment or what the person said is a lead, not the source.
10. Give an example whose numbers come from a run, not from what would make the point.
11. Name the evidence behind a recommendation; when the person pushes back, check that evidence again before it moves, and say which fact changed or that none did.

## Review checklist

- [ ] §CL1 Published text states no fact about code, data, a setting or a tool that this turn did not read a source for, or says plainly it is unverified (`guard-unchecked-claim.sh`).
- [ ] §CL2 Never reported success on a red loop: when tests fail, say so and show the output.
- [ ] §CL3 A skipped step or one that could not be run is named with why; silence reads as done.
- [ ] §CL4 A number given about your own work (agents run, tests passed, rows changed, time spent) is counted from the record; an estimate says it is one.
- [ ] §CL5 A search or audit handed off reports what it kept as well as what it found, and the kept items are checked like findings, since "left on purpose" is a claim too.
- [ ] §CL6 A recommendation names its evidence, and the evidence is checked again before the recommendation moves under pushback.
