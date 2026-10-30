---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---
<!-- Generated from skills/kc-correctness/SKILL.md by scripts/build-rules.sh. Edit the skill, not this file. -->

# Correctness

Code that reads well and is wrong is still wrong. Walk every change for the bugs a reader skims past.

- Consider the empty, null, zero and boundary input on every path you add or change, not only the value the feature was built for.
- Check every operator and condition for an off-by-one or an inversion: `<` against `<=`, `&&` against `||`, a negation that flips the meaning.
- Keep dependency arrays and closures current: an effect, memo, callback or handler reads the latest value of everything it uses.
- Do not let a cast hide a real type mismatch. When data crossing a boundary (an API response, props, storage) does not match its declared type, fix the type or parse the value.
- Before changing code, check the repo's history for a bug already fixed there (the changelog, dev logs, `git log -S <symbol>`), so the change does not bring it back.
- Trace every submitted field from its input, through any transform and the request payload, to what the receiving end does with it, for each state the user can leave it in: set, changed, cleared, left alone, invalid. Each state must arrive in a shape the receiver accepts and have the effect the user expects.
- When a change adds a reference from one module or class to another, follow the references back and check that they do not close a loop. Inside a loop, code that runs when a module is defined (a subclass copying its parent's fields, a registration, class-level configuration) can run before what it needs exists, and fail with no error. Use the lazy form of the reference when the library has one.
- A count, total or summary of a list uses the same filter as the list: what the list hides (archived, deleted, inactive items) the count leaves out too.
- When a change alters what a value means (a route parameter or field now holds a different kind of id, a setting now applies per item), find every reader of that value and check each one still gets what it expects.
- A bug fix covers every instance of its cause, not only the one that was reported. Once the cause is known, grep the repo, tests included, for the same pattern (the same query, call or assumption) and fix or list each hit; code written alongside the original, on the same day or in a sibling branch, is the first place to look.
- Before saying what a value holds ("this column is always blank", the cause of a flaky test), find every writer of it: the class body, every module or concern it includes and their callbacks, factories and seed code. A claim read off the visible class alone is a guess.
- When a change turns one into many (a shop's store becomes stores), every accessor that still picks "the" one (the first, the lowest id, a "default") is a leftover unless a stated product rule chooses it. Each reader uses the specific record it already has (the order's store, the one in the URL), and the accessor and every fallback to it go.
- A guard that refuses a delete or removal ("has orders", "has items") counts only the related records the delete would harm: completed payments, live work, records people still see. Abandoned, expired, failed, archived or deleted ones go with it, or are cleaned up, and the message says in plain words what blocks it and what to do instead.

Detection criteria and per-box review failure modes live in the `## Review checklist` of the `kc-correctness` skill (`kc-conventions:kc-correctness`), with the detail under its `## Review detail`. These rules are the statement of the convention; that checklist is how a diff gets graded against it.
