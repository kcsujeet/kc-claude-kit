---
name: kc-claims
description: Use before stating what code, a tool, a platform, an instruction, a source, a number or a requirement is or can do, before saying "I can't confirm" or "can't be done here", and before a recommendation or an example.
---

# A claim needs a check behind it

Applies to whoever made the claim: you, a review agent or a subagent. Check the source in this turn, then state the claim and cite what you found.

## Claim kinds

- **What the code does.** Reasoning from a snippet you wrote is not evidence about the path the code takes. Grep for the real call site before asserting anything.
- **Where something came from** (which environment a report, recording or log is from, which account or version). Read it from the material itself (the address bar, an org or host name, a timestamp) or ask. Never infer it from who sent it.
- **Facts a question is offered on.** Check them first; the person decides on them.
- **What a tool, platform or runtime can do.** Before planning around a capability (a second trigger, an API option, a language or shell feature, a browser feature), check that the version that will run it has it, in its own docs or by trying it there.
- **A command handed to the person to run.** Check the access it runs with that you can see (the CLI's login, its keys and what they may do, the account it acts on) with a read-only command, and fix what is missing before handing it over.
- **What instructions say** (the kit's rules, a repo's CLAUDE.md, a checklist). Read the rule before saying what it requires or lacks, and cite it. kc-gates notes a reply that does this or the previous kind with nothing checked in that turn, and names it at the start of the next.
- **"I can't confirm" or "I don't know".** A claim about the evidence, said only after every source that could settle it (each log, file and command) was checked and what was found is cited. A partial search is unfinished work, not uncertainty. kc-gates names such a reply at the start of the next turn.
- **"This can't be done here".** Before saying a tool or operation is missing and handing the step to the person, search every catalog that could hold it (the loaded tools, a connector's own operation search, the CLIs on the machine).
- **What the world outside the code requires** (a standard, a regulator, a carrier, a vendor's terms). The source is the authority's own text, opened in this session. A picture, a comment in the repo, a search summary or what the person just said is a lead to it, not the source.
- **An example given to explain something.** Its numbers come from a run, not from what would make the point.
- **A recommendation.** It names the evidence it rests on. When the person pushes back, check that evidence again before it moves, and say which fact changed, or that none did and it stands.

## Examples

- A no-code workflow planned with a webhook trigger beside its form, when each workflow takes one trigger.
- An associative array in a script the team's machines run with an older shell that lacks them.
- A bug recording assumed to be from staging because a tester made it, when its frames showed production.
- An agent's "a free item will now show $0.00" relayed in a question, when the formatter prints nothing for 0.
- A log line read as today's without its date.
- A file upload handed back to the person as "no tool for it", when the connector listed it under its operation search.
- "The carrier requires the label's barcode 20 mm from the edge" said from a screenshot of its template and a comment in the repo, when the carrier's own page gave no such distance.
- A rounding bug explained with an order total that no real order had, and that the orders table contradicted.
- A recommendation changed three times to match the person's last remark, until they asked whether it was being made to please them.
- Live payment commands handed over three times, failing on a missing live login, then a key to renew, then a missing write permission, when the CLI's config already showed it had no live key.
- "A lesson is only text, nothing checks it" said of a kit whose checklist asks every lesson for a check that fails without it.
