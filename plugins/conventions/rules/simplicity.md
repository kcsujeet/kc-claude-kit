---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---
<!-- Generated from skills/simplicity/SKILL.md by scripts/build-rules.sh. Edit the skill, not this file. -->

# Simplicity

The simplest code that does the job is the easiest to read, change and delete. Every construct earns its place.

- DRY is about knowledge: a rule, a format, an API call or a meaningful value has one source. Code that only looks alike is not duplication.
- A helper earns its place by carrying knowledge its callers should not hold (an API call, a data format or conversion, a domain rule, several steps), or by wide use. One plain expression (a `find` by id, a filter plus a sort, a one-field object) stays inline, even with two callers.
- YAGNI: no speculative code. No param, prop or config option that nothing passes, no abstraction built for a hypothetical second caller, no dead branch. A generality the change does not use is removed, even if it might be needed later.
- KISS: take the materially simpler equivalent when one exists. A lookup object beats nested conditionals, an early return beats nesting, an existing util or standard-library call beats a hand-roll.
- Reuse before writing. Assume the capability already exists and look for it, in order: a prop or slot on the component already in use, a shared hook or util, a variant of an existing component, data already in state or the store. Search by shape (a type's field set, a component's props and markup), not only by name.
- Ask what breaks if a new construct is deleted or collapsed. If nothing does, use the simpler form. A named intermediate that makes a line readable is not a candidate.
- Finish the refactor: no leftover duplicate block, unused import, parameter nobody reads, or commented-out code.
- A prop added to a shared component for one caller's case makes every other caller carry it. Let that caller own or compose the behavior instead.
- Defaults carry the everyday case, and a caller overrides only what differs. No variant per scenario (`WidgetWithIcon`, `useWidgetsForToday`, `formatPriceShort`, `mockOrderWithOwner`): give the base unit a default and let the one caller pass a prop, argument or override.
- A new pattern or technique follows 2 places in the repo that already do it. When nothing does, ask the developer before introducing it.
