---
name: kc-delegation
description: Use before delegating work to subagents, parallel agents or a workflow, before a sweep, audit or migration across many files, and before starting parallel or long-running sessions. Keeps work cheap: script first, small agents and sessions, cheapest model per step, capped context, results in files.
---

# Delegating work

Delegated work costs about the number of calls times the context each call re-reads. One long-running agent that walks everything makes many calls on a context that keeps growing, so it costs far more than the same work split into small pieces. Examples of the same mistake: a review fan-out where one agent reads every file; a migration sweep run as one agent over a whole codebase; a research agent that keeps every fetched page in context; a session that has run for days and re-reads its whole history on every call. In one measured day, re-reading context beyond the first 200k tokens of each call was a third of all spend.

Before handing work off, walk these habits:

- **Script first.** A deterministic script does the mechanical part: for an audit of a shop's docs, extract every line and the paths and identifiers it cites, and check that each exists. Only what the script flags goes to a model.
- **Many small agents, not one long one.** One fresh agent per file or small batch (one storefront's config, ten orders' fixtures), with a narrow brief, returning a short table. Never one agent that walks everything. An agent past about 50 calls or 150k tokens of context is split.
- **Cheapest model that can do each step.** A small model for exists/matches checks, a mid model for judgment, the strongest only for decisions. Sessions too: a routine one (release notes, a re-review, a mechanical follow-up) runs on a mid model. The default subagent model (`CLAUDE_CODE_SUBAGENT_MODEL`) is a mid one, so an agent spawned without a model never lands on the strongest.
- **Results go to files.** Each agent writes its findings to a file; the orchestrator reads the summaries, not transcripts or dumps.
- **Keep every session's context small.** Cap the auto-compact window (`"autoCompactWindow": 200000` in settings); with a 1M window each call can re-read hundreds of thousands of cached tokens. Start a fresh session per phase (assess, build, review, each round of feedback), handing over through a notes file, and compact between phases within one. What phase one read is not needed in phase two.
- **Start sessions and agents fresh, not forked.** A fork carries the whole conversation it came from into every call it makes. Give a fresh start a full brief (goal, files, what done looks like, what was ruled out) and, for work in progress, a notes file. An orchestrating session stays thin: it briefs, checks and reports, leaves reading and editing to the sessions and agents it starts, and is restarted fresh once its context passes the compact window. The `guard-fork-context.sh` hook refuses a fork while the context is above 100k tokens.
- **Check the settings.** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-cost-settings.sh"` prints each setting that raises every call's cost, with its fix, and nothing when they are fine.
- **Re-check only what changes.** After a fix, rerun the script and the agents on the files that changed, not everything again.
- **Never switch a running session's model.** The prompt cache is per model, so the switch makes the session write its whole context again.
- **Measure.** Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/subagent-cost.sh" <transcript.jsonl or folder>...` on the session's transcripts (a session's `subagents/` folder works) to see calls and cached tokens per agent, before and after the change.
