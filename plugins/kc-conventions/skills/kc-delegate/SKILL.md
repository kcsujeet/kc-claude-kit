---
name: kc-delegate
description: Use before delegating work to subagents, parallel agents or a workflow, before a sweep, audit or migration across many files, and before starting parallel or long-running sessions. Keeps work cheap: script first, small agents and sessions, cheapest model per step, capped context, results in files.
---

# Delegating work

Delegated work costs about the number of calls times the context each call re-reads, so one long agent that walks everything costs far more than the same work split small. Full wording and the cost numbers: `references/detail.md`.

## Steps

1. Script first: a deterministic script does the mechanical part; only what it flags goes to a model.
2. Use many small agents, not one long one: one fresh agent per file or small batch, a narrow brief, a short table back. Split an agent past about 50 calls or 150k tokens of context.
3. Whatever decides (what to build, whether a finding stands, what a comment says) runs on the strongest model; a mid model runs a named step to a stated spec, and the deciding session reads its output before anyone relies on it. The tree:

   | Who | Model | Effort | Does |
   |---|---|---|---|
   | Orchestrating (main) session | strongest (e.g. Opus or Fable) | high | briefs, routes, checks; no hands-on work |
   | Child session that decides, one per task (a ticket, a review, a re-review), in its own worktree | strongest | medium | assesses, judges findings, drafts, decides |
   | Mechanical session with exact steps (e.g. cleaning up worktrees) | mid (e.g. Sonnet) | medium | runs the steps |
   | Hands-on agent under a child session (code, tests, walks) | mid, named in the brief or agent file | | executes its brief |
   | Review gate agent (grades one checklist) | mid, named in the agent file | | grades box by box |
   | Unnamed agent | `CLAUDE_CODE_SUBAGENT_MODEL`, set to the strongest | | may decide, so never lands on a mid model |

4. A mid-model agent may make a bounded call on a list it is handed when a strongest-model gate checks the result downstream; name each such agent and its reason.
5. Results go to files: each agent writes findings to a file; the orchestrator reads summaries, not transcripts.
6. Keep every session's context small: a fresh session per phase (assess, build, review, each feedback round), handed over through a notes file.
7. Start sessions and agents fresh, not forked, with a full brief (goal, files, what done looks like, what was ruled out). `guard-fork-context.sh` refuses a fork while the context is above 100k tokens. An orchestrator stays thin and restarts fresh when its context grows.
8. Check the settings: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-cost-settings.sh"` prints each setting that raises every call's cost, with its fix.
9. Re-check only what changes: after a fix, rerun the script and agents on the changed files only.
10. Never switch a running session's model; the cache is per model.
11. Measure: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/subagent-cost.sh" <transcript.jsonl or folder>...` shows calls and cached tokens per agent.

## Gate checklist

- [ ] §D1 Each independent result is waited on by its own short poll, never several in one call and no timeout over 10 minutes on a quick check (`guard-batched-wait.sh`). (N/A: waits on nothing)
- [ ] §D2 Files the person will use (screenshots, reports, exports) are saved in the session's workspace, never a temporary folder. (N/A: no files for the person)
