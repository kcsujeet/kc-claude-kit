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

- [ ] §P1 DRY: no knowledge duplicated that should have one source (a copied block of real logic, a re-declared constant, a re-implemented helper, a repeated format or domain rule). When the diff moves a literal into a shared constant, grep the repo for the literal's text: every other copy reads the constant or is listed. Lines that only look alike, with a meaning plain on sight, are not a DRY finding at any count; see §P11. (N/A: nothing duplicated in the diff)
- [ ] §P2 YAGNI: no speculative or unused code — no unused params/props, no abstraction with a single caller built for a hypothetical second one, no config option nothing passes, no dead branch. (N/A: no new abstraction, param, prop, or config option in the diff)
- [ ] §P3 KISS: no materially simpler equivalent left on the table — a lookup object beats nested conditionals, an early return beats nesting, an existing util/stdlib call beats a hand-roll. (N/A: nothing in the diff has a simpler available equivalent)
- [ ] §P4 Assume-it-exists: any new hand-rolled capability was checked against a prop/slot on the component already in use, a shared hook/util, a component variant, and data already in state/store, in that order, before being written; a component that only reuses a shared *hook* is still checked against a shared *component* that composes that same hook; a new type was grepped by its field set and a new component by its core props and markup, not only by name. (N/A: nothing hand-rolled in the diff)
- [ ] §P5 Numeric hygiene: coercions are NaN-safe and don't silently swallow a legitimate `0` (no bare `value ?? 0` on a nullable/optional numeric, no `Number(x) || 0`, no NaN-risky `Number(x)` on a possibly-empty/non-numeric value; no wrapping of an already-guaranteed `number`); a non-trivial conversion/encoding repeated at 2+ call sites is extracted to a named helper rather than re-inlined per site. (N/A: no numeric coercion and no repeated conversion in the diff)
- [ ] §P6 Delete-or-collapse: every new construct (variable, branch, guard, helper, prop, param, option, type, default, wrapper) passes "what breaks if I delete or collapse this?"; one that collapses to a simpler form with identical behavior FAILS, and the finding gives the concrete simpler form. "It works", "it's defensive", and "it's more explicit" are not justifications. A named intermediate kept for readability is exempt (clarity §C18). (N/A: no new construct in the diff)
- [ ] §P7 Types as narrow as their sink: every new or changed return/param type carries no member its consumers treat identically to another (a `=> T | undefined`, `| null`, or `| ''` whose sink handles the empty value exactly like the default narrows to `=> T`); the sink's behavior was opened or run before the finding claims it. (N/A: no new or changed signature)
- [ ] §P8 Mirror claims are diffed: wherever the PR or the review says a new member mirrors, follows, or matches an existing sibling, the two signatures are set side by side in the evidence; an unjustified difference between siblings is a finding. (N/A: no new member beside an existing sibling, and no such claim)
- [ ] §P9 No refactor leftovers: no markup or block left duplicated by an incomplete refactor, no import nothing uses, no prop or param threaded through and never read, no commented-out code. (N/A: none in the diff)
- [ ] §P10 A prop or option added to a shared component or shared helper for a single caller's case is questioned: could the caller own it, or compose the shared piece instead? (N/A: no shared component or helper signature changed)
- [ ] §P11 A helper earns its place: every new or proposed helper (util, hook, small component) carries knowledge its callers should not hold (an API call, a data format or conversion, a domain rule, several steps) or is used in many places. A helper around one plain expression FAILS even with two callers, and so does a finding that proposes one. So does a helper whose body is one call to an existing function or built-in on a field of its argument (`toWidgetId = (widget) => toNumber(widget.id)`): the called function already holds the knowledge, and a comment calling it a conversion doesn't change that. The evidence shows how the repo writes the same expression elsewhere. (N/A: no helper added or proposed)
- [ ] §P12 Defaults carry the everyday case: no new variant per scenario of a component, hook, util, fixture or test helper when the base unit could hold the common data or behavior with a default and the one differing caller could pass a prop, argument or override. A caller that depends on something being absent says so in its own override. (N/A: no new variant or scenario helper)
- [ ] §P13 Everything new conforms: every new or reshaped unit in the diff (an endpoint, a data read, a class, function or hook, a file, a message, a test, an abstraction or technique) names the similar code read (about ten pieces that do the same job, or all there are when fewer) and matches it in shape, name, place and wording; each difference is a finding unless the diff says why. A file with a similar name is not precedent, and neither is an option a shared type declares but no caller passes, or a lone unit that does it differently from the rest. With no precedent, the finding is a `question` to the author (in a self-review, ask the developer before writing it). **Enumerate** the new and reshaped units with the similar code read for each. (N/A: nothing new or reshaped in the diff)
- [ ] §P14 Every new branch, fallback or exception for a data state (blank, missing, legacy shape) cites evidence that the state can still occur: the writer that can still produce it, or a data query. A state that create-time defaults, validations or a completed backfill rule out FAILS; handle it in the backfill or the validation instead. (N/A: no new branch for a data state)
- [ ] §P15 Deferred work is done when its condition is met: grep the repo for the markers of the work this diff finishes (its feature or phase name, `once`, `after`, `remove when`); each one whose condition the diff meets FAILS unless the diff removes the code it guards. Each one left in place states what it still waits on. (N/A: the diff finishes no deferred work)
- [ ] §P16 The shape of the whole change is the simplest that works: state the result the diff is after, then at least one other way to get it, and compare. A diff that runs two mechanisms for one job (two storage shapes, two lookups, a branch on a mode through every step), recomputes downstream what an earlier step already knew, or adds a layer an existing one could carry FAILS when the other way is materially simpler, and the finding describes that shape in a sentence or a short sketch. Line findings that shape would delete go under this one, not beside it. (N/A: never; even a one-line change has a goal another shape could meet)
- [ ] §P17 Familiar flows stay familiar: every flow people go through that the diff adds or reshapes (sign-up, sign-in, password reset, checkout, account settings, navigation, or any other task most products run the same way) asks for things in the order, and behaves the way, people know from other products. A step dropped, merged, moved or added against that order to save a screen or a request FAILS; a departure the developer chose is fine only when the diff or the PR says so, and otherwise is a `question`. A flow that copies a departure the codebase already has is raised as one too, not taken as precedent (§P13). **Enumerate** each flow with its steps in order beside the order most products use. (N/A: the diff adds or reshapes no flow a person goes through)
- [ ] §P19 New code has precedent in the codebase: every hit of the `no-precedent.sh` sweep (a package, CSS unit or property, browser global, test-mocking call, config key or file-name pattern the diff introduces that nothing else in the repo uses at the base) FAILS unless the author uses the way the repo already does that job (name the file that does it) or a comment or the description says why it can't. Receipt: `grepped no precedent: N hits`, one verdict per hit. (N/A: `grepped no precedent: 0 hits`)
- [ ] §P18 A value a shared unit derives by convention (a name built from another name, a default read from a string pattern) is not made cleverer for one caller it gets wrong (pluralization rules, another regex, a special case); that caller passes the value through an optional override, and every other caller keeps the old default. (N/A: no derived value changed or worked around in the diff)

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
