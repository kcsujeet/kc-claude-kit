# kc-delegate detail

### Full wording before the steps rewrite

- The whole `SKILL.md` body as it was, moved verbatim (headings two levels down). Read the part a step or box points to.

### Delegating work

- Delegated work costs about the number of calls times the context each call re-reads. One long-running agent that walks everything makes many calls on a context that keeps growing, so it costs far more than the same work split into small pieces. Examples of the same mistake: a review fan-out where one agent reads every file; a migration sweep run as one agent over a whole codebase; a research agent that keeps every fetched page in context; a session that has run for days and re-reads its whole history on every call. In one measured day, re-reading context beyond the first 200k tokens of each call was a third of all spend.

- Before handing work off, walk these habits:

- **Script first.** A deterministic script does the mechanical part: for an audit of a shop's docs, extract every line and the paths and identifiers it cites, and check that each exists. Only what the script flags goes to a model.
- **Many small agents, not one long one.** One fresh agent per file or small batch (one storefront's config, ten orders' fixtures), with a narrow brief, returning a short table. Never one agent that walks everything. An agent past about 50 calls or 150k tokens of context is split.
- **The strongest model decides; a mid model executes work it is handed.** Whatever decides (what to build, whether a finding stands, what a comment says) runs on the strongest model; a mid model runs a named step to a stated spec, and the deciding session reads its output (the diff, the verdicts) before anyone relies on it. The tree:

  | Who | Model | Effort | Does |
  |---|---|---|---|
  | Orchestrating (main) session | strongest (e.g. Opus or Fable) | high | briefs, routes, checks; no hands-on work |
  | Child session that decides, one per task (a ticket, a review, a re-review), in its own worktree | strongest | medium | assesses, judges findings, drafts, decides |
  | Mechanical session with exact steps (e.g. cleaning up worktrees) | mid (e.g. Sonnet) | medium | runs the steps |
  | Hands-on agent under a child session (code, tests, walks) | mid, named in the brief or agent file | | executes its brief |
  | Review gate agent (grades one checklist) | mid, named in the agent file | | grades box by box |
  | Unnamed agent | `CLAUDE_CODE_SUBAGENT_MODEL`, set to the strongest | | may decide, so never lands on a mid model |

  A mid-model agent may make a bounded call on a list it is handed (refute a finding, sort fix or dismiss) when a strongest-model gate checks the result downstream; name each such agent and its reason. A small model was weighed for mechanical steps and left out: the saving is small.
- **Results go to files.** Each agent writes its findings to a file; the orchestrator reads the summaries, not transcripts or dumps.
- **Keep every session's context small.** Start a fresh session per phase (assess, build, review, each round of feedback), handing over through a notes file, and compact between phases within one. What phase one read is not needed in phase two.
- **Start sessions and agents fresh, not forked.** A fork carries the whole conversation it came from into every call it makes. Give a fresh start a full brief (goal, files, what done looks like, what was ruled out) and, for work in progress, a notes file. An orchestrating session stays thin: it briefs, checks and reports, leaves reading and editing to the sessions and agents it starts, and is restarted fresh once its context grows large. The `guard-fork-context.sh` hook refuses a fork while the context is above 100k tokens.
- **Check the settings.** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-cost-settings.sh"` prints each setting that raises every call's cost, with its fix, and nothing when they are fine.
- **Re-check only what changes.** After a fix, rerun the script and the agents on the files that changed, not everything again.
- **Never switch a running session's model.** The prompt cache is per model, so the switch makes the session write its whole context again.
- **Measure.** Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/subagent-cost.sh" <transcript.jsonl or folder>...` on the session's transcripts (a session's `subagents/` folder works) to see calls and cached tokens per agent, before and after the change.

#### Gate checklist

- [ ] §D1 Each independent result is waited on by its own short poll, acted on as it lands: no one call waits on several (two deploys, three test runs, two CI watches in a `Promise.all` or a chain), since it returns only when the slowest ends and a hung one hides, and no wait has a timeout over 10 minutes on a check that takes seconds. Held by kc-gates `guard-batched-wait.sh`, which denies a call with two CI watches or one with a timeout over 10 minutes. (N/A: the work waits on nothing)
- [ ] §D2 Files the person will use (screenshots, reports, exports) are saved in the session's workspace, never a temporary folder. (N/A: no files for the person)