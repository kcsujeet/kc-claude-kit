---
name: kc-delegation
description: Use before delegating work to subagents, parallel agents or a workflow, and before a sweep, audit or migration across many files. Keeps delegated work cheap: script first, many small agents, cheapest model per step, results in files.
---

# Delegating work

Delegated work costs about the number of calls times the context each call re-reads. One long-running agent that walks everything makes many calls on a context that keeps growing, so it costs far more than the same work split into small pieces. Examples of the same mistake: a review fan-out where one agent reads every file; a migration sweep run as one agent over a whole codebase; a research agent that keeps every fetched page in context.

Before handing work off, walk these habits:

- **Script first.** A deterministic script does the mechanical part: for an audit of a shop's docs, extract every line and the paths and identifiers it cites, and check that each exists. Only what the script flags goes to a model.
- **Many small agents, not one long one.** One fresh agent per file or small batch (one storefront's config, ten orders' fixtures), with a narrow brief, returning a short table. Never one agent that walks everything.
- **Cheapest model that can do each step.** A small model for exists/matches checks, a mid model for judgment, the strongest only for decisions.
- **Results go to files.** Each agent writes its findings to a file; the orchestrator reads the summaries, not transcripts or dumps.
- **Compact the orchestrating session between phases.** What phase one read is not needed in phase two.
- **Re-check only what changes.** After a fix, rerun the script and the agents on the files that changed, not everything again.
- **Never switch a running session's model.** The prompt cache is per model, so the switch makes the session write its whole context again.
- **Measure.** Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/subagent-cost.sh" <transcript.jsonl or folder>...` on the session's transcripts (a session's `subagents/` folder works) to see calls and cached tokens per agent, before and after the change.
