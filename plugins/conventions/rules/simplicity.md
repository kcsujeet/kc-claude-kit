---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---
<!-- Generated from skills/simplicity/SKILL.md by scripts/build-rules.sh. Edit the skill, not this file. -->

# Simplicity

The simplest code that does the job is the easiest to read, change and delete. Every construct earns its place.

- DRY: logic, a value, a literal or a block of markup has one source. Twice is the threshold: at the second copy, extract it to a named helper or constant.
- YAGNI: no speculative code. No param, prop or config option that nothing passes, no abstraction built for a hypothetical second caller, no dead branch. A generality the change does not use is removed, even if it might be needed later.
- KISS: take the materially simpler equivalent when one exists. A lookup object beats nested conditionals, an early return beats nesting, an existing util or standard-library call beats a hand-roll.
- Reuse before writing. Assume the capability already exists and look for it, in order: a prop or slot on the component already in use, a shared hook or util, a variant of an existing component, data already in state or the store. Search by shape (a type's field set, a component's props and markup), not only by name.
- Ask what breaks if a new construct is deleted or collapsed. If nothing does, use the simpler form. A named intermediate that makes a line readable is not a candidate.
- Finish the refactor: no leftover duplicate block, unused import, parameter nobody reads, or commented-out code.
- A prop added to a shared component for one caller's case makes every other caller carry it. Let that caller own or compose the behavior instead.
