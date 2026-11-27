---
name: kc-simplicity
description: "DRY, YAGNI and KISS conventions: reuse before writing, delete what adds nothing, narrow types, one-caller props, familiar user flows. Use when writing or reviewing code that adds a helper, component, type, prop or abstraction, repeats logic, or changes a flow (sign-up, checkout)."
user-invocable: false
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Simplicity

## Contents

- Review checklist
- Sweeps

## Review checklist

Tick every box for each construct you add or change. Report each: PASS, FAIL (file:line) or N/A (why).

- [ ] §P1 DRY: no knowledge duplicated that should have one source (copied logic, re-declared constant, re-implemented helper); a literal moved to a constant leaves no other copy (§P11).
- [ ] §P2 YAGNI: no unused params or props, no single-caller abstraction built for a hypothetical second, no config option nothing passes, no dead branch.
- [ ] §P3 KISS: no materially simpler equivalent left: a lookup object beats nested conditionals, an early return beats nesting, an existing util or stdlib call beats a hand-roll.
- [ ] §P4 A new hand-rolled capability was checked against a prop or slot in use, a shared hook or util, a component variant and existing state; types and components are grepped by shape.
- [ ] §P5 Numeric coercions are NaN-safe and keep a legitimate `0` (no bare `value ?? 0`, `Number(x) || 0`); a conversion repeated at 2+ sites is a named helper.
- [ ] §P6 Every new construct (variable, branch, guard, helper, prop, option, type, wrapper) survives "what breaks if I delete or collapse this?"; give the simpler form; named intermediates exempt.
- [ ] §P7 Return and param types are as narrow as their sink: no `| undefined`, `| null` or `| ''` member the consumer treats like the default; the sink's behaviour was opened or run first.
- [ ] §P8 Where the PR or review says a new member mirrors an existing sibling, the two signatures sit side by side in the evidence; an unjustified difference is a finding.
- [ ] §P9 No refactor leftovers: no duplicated markup or block, unused import, prop or param never read, or commented-out code. (N/A: none in the diff)
- [ ] §P10 A prop or option added to a shared component or helper for one caller's case is questioned: could the caller own it or compose the shared piece? (N/A: no shared signature changed)
- [ ] §P11 A new helper carries knowledge its callers should not hold (API call, format, rule, several steps) or is widely used; a wrapper around one plain expression FAILS, as does proposing one.
- [ ] §P12 Defaults carry the everyday case: no new variant per scenario of a component, hook, util or fixture when the base unit could take a default and the differing caller passes an override.
- [ ] §P13 Every new or reshaped unit names ~10 similar pieces read and matches their shape, name, place and wording; each difference is a finding unless explained; none exists means a `question`.
- [ ] §P14 Every new branch, fallback or exception for a data state (blank, missing, legacy) cites the writer or query showing it can still occur; a state defaults or a backfill rule out FAILS.
- [ ] §P15 Deferred work is done when its condition is met: grep the markers of the work this diff finishes (`once`, `after`, `remove when`); each met condition FAILS unless the code is removed.
- [ ] §P16 The whole change is the simplest shape that works: state the goal, compare one other way; two mechanisms for one job or a redundant layer FAILS when the other is materially simpler.
- [ ] §P17 Familiar flows (sign-up, sign-in, reset, checkout, settings) keep the order and behaviour people know; a dropped, merged or added step FAILS unless the diff says why; enumerate each flow.
- [ ] §P19 New code has precedent: each `no-precedent.sh` hit (a package, CSS property, global or config pattern no other code uses) FAILS unless the repo's way is used or a comment says why.
- [ ] §P18 A value a shared unit derives by convention (a name from a name, a default from a pattern) is not made cleverer for one caller; that caller passes an optional override.

Examples and edge cases per box: references/detail.md (read when a box is unclear).

## Sweeps

Save the diff under review to a file and run the script over it; `-` reads the diff from stdin. Each hit gets its own verdict.

- `no-precedent.sh` (§P19): tokens the added lines introduce with zero uses in the repo at the base. Receipt: `grepped no precedent: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-simplicity/scripts/no-precedent.sh" <diff-file> <repo-root>
  ```

- `added-lines.sh` (citation map): every added line as `path:line: text`, with the source line number at the head SHA. Cite every finding's line from this output or from a sweep hit, never from a position in the diff file.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh" <diff-file>
  ```
