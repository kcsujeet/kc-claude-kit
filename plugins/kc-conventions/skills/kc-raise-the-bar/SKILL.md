---
name: kc-raise-the-bar
description: Before handing over work that works: measure it, find a better way, apply it or note tries.
---

# Raise the bar

Working is the floor, not the finish. This is when to look for better and whether to take it; `kc-simplicity`, `kc-performance`, `kc-delegate` and `kc-investigate` are how. Cases: `references/detail.md`.

## Steps

1. Measure what you just did: time, runs, steps, size, lines, cost. A number from a run, not an estimate. Nothing to measure yet means measure it first.
2. Assume a better way exists. List two or three alternatives, the ones that do less first: delete a step, a loop or a branch; reuse what exists (`kc-simplicity`); only then add something.
3. Try the most promising and measure again the same way.
4. Apply it or record what was tried. Keep it only when it is better on the measure and no worse on clarity, correctness and simplicity. A gain that adds code, a cache, a flag or a special case names its cost and goes through the same gates.
5. Keep it out of the reply. A hook reminds you once at hand-off; nothing is written to a file and nothing about this check goes to the person. When nothing better exists, move on.

Faster or cheaper and simpler go together; a speedup that makes the code harder to read or trust is a trade, and a trade is the person's call.

## Gate checklist

- [ ] §RB1 Measured with a number from a run, not an estimate.
- [ ] §RB2 Two or three alternatives were listed, the ones that do less first.
- [ ] §RB3 The most promising was tried and measured the same way.
- [ ] §RB4 Kept only when better on the measure and no worse on clarity, correctness and simplicity; a gain that costs says what and passed the same gates.
- [ ] §RB5 Nothing about this check went into the reply to the person.
