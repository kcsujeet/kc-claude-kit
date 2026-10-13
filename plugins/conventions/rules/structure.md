---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---
<!-- Generated from skills/structure/SKILL.md by scripts/build-rules.sh. Edit the skill, not this file. -->

# Structure

Where code lives is part of its contract. A path promises something about what is inside it.

- One observable responsibility per unit. A directory name is a promise: `hooks/` contains hooks, `utils/` contains pure functions.
- Co-locate with the single consumer. Promote at the second consumer: within a feature, to the nearest common ancestor; across features, to the shared app level, never sideways into another feature.
- Flatten a folder that holds one file. `Foo/Foo.tsx` with no siblings is just `Foo.tsx`.
- No barrel re-export files. Import the module path directly, which also keeps tree shaking working. A barrel for a single component is fine.
- Named exports on new files, declared inline (`export const foo = ...`), not collected in a trailing export block.
- Delete dead wrappers in every shape: async-await passthrough, destructure-and-reconstruct, single-use alias, identity transform, a Promise wrapped around a Promise, a hook returning another hook's values unchanged, a wrapper whose only addition is an `onSuccess` every caller could pass itself.
- A module exports the thing it is named for plus its own surface (its props, argument and return types). An unrelated export, such as a domain enum in a hook file, moves to where its consumers are; a type only this module uses stays.
- New code acts on its home's subject. A method added to the order module creates, reads or changes orders; one that only prices a cart belongs with the cart.
- One exported component per file. Its hooks and helpers move to their own files, and a subcomponent with one consumer stays private in that consumer's file.
- A lookup object beats a `switch` or an `if` chain that maps a key to a value. Use thunks when the branches need per-branch work.
- Exported APIs carry a short doc comment saying what they are for, not restating the signature.
- Do not widen a package's public exports so a sibling package can reach an internal. Move the shared piece to a shared layer both consume.
- A discriminator the backend serializes is a string enum, not a literal union: if the backend can return it, it needs a name in the code.

## React and TypeScript codebases

**Bulletproof-react is the canonical source for placement**: https://github.com/alan2207/bulletproof-react/blob/master/docs/project-structure.md

Where anything above appears to disagree with it, that document wins and this file is the one to correct.

- Feature code lives under `features/<feature>/{api,components,hooks,stores,types,utils}`, including only the subfolders that feature actually needs.
- Shared code lives at the app level: `components/`, `hooks/`, `utils/`, `types/`, `stores/`, `lib/`, `config/`.
- No cross-feature imports. Two features that need the same thing compose at the app level, or the shared thing moves up.
- Dependencies flow one way: shared can be used anywhere, features import only from shared, the app imports from both.
- `app/` is the routing layer: route files, their tests and route-level actions, plus the app's own entry, provider and router. Components, hooks and utils go to the shared folders or a feature, never beside a route.
- Its guidance on barrel files matches the rule above: barrels were once recommended per feature and no longer are, because they break tree shaking. Import files directly.

Apply this to a repo that already uses a feature-based layout or is migrating to one. In a legacy flat layout, do not demand a migration as a side effect of unrelated work; just avoid making the existing structure more inconsistent than it already is.

Detection criteria and per-box review failure modes live in the `## Review checklist` of the `structure` skill (`conventions:structure`) and of the `react` skill, with the detail under each one's `## Review detail`. These rules are the statement of the convention; those checklists are how a diff gets graded against it.
