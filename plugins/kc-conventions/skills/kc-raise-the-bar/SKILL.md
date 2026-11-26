---
name: kc-raise-the-bar
description: Before handing over work that works: measure it, find a better way, apply it or note tries.
---

# Raise the bar

Working is the floor, not the finish. This is when to look for better and whether to take it; `kc-simplicity`, `kc-performance`, `kc-delegation` and `kc-investigate` are how, and are not repeated here.

## Procedure

1. **Measure what you just did:** time, runs, steps, size, lines, cost. A number, from a run, not an estimate. Nothing to measure yet means measure it first.
2. **Assume a better way exists.** List two or three alternatives, the ones that do less first: delete a step, a loop or a branch; reuse what exists (`kc-simplicity`); then, only then, add something.
3. **Try the most promising, measure again** the same way.
4. **Apply it or record what was tried.** Keep it only when it is better on the measure and no worse on clarity, correctness and simplicity. A gain that adds code, a cache, a flag or a special case names what it costs and goes through the same gates as any change.
5. **Record it, in the session's file, never in the reply.** The Stop hook asks for one line per work turn in `better-lines/<session id>` under the plugin data folder (it names the full path when it blocks), tab-separated, the time first (`date -u +%Y-%m-%dT%H:%M:%SZ`):
   - `<time> TAB order export TAB 40 s TAB 3 s`: the thing improved, its state before and after. Deleting the per-order loop is the thing, not "fixed the export".
   - `<time> TAB none TAB tried a cache (40 s to 38 s, +30 lines) and a batch query (rejected: changes the order), 3 runs`: what was checked or measured. This is the plain default when nothing better exists.
   A list of actions (fixed, posted, merged, confirmed) is no record: name what changed state. The reply to the person says nothing about this check.

Faster or cheaper and simpler go together: prefer the change that deletes code, removes a step or a moving part. A speedup that makes the code harder to read or to trust is a trade, and a trade is the person's call.

## Cases

- A test suite accepted at 9 minutes because it passes: measure where the time goes, drop the setup repeated per case.
- A review that re-reads every file when the changes since the last round would do.
- A query fine on today's data: run it on ten times the rows before calling it done.
- A request to raise a limit or add a workaround, made before measuring one's own part in it.
