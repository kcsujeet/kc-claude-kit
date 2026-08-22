---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Structure

Where code lives is part of its contract. A path promises something about what is inside it.

- One observable responsibility per unit. A directory name is a promise: `hooks/` contains hooks, `utils/` contains pure functions.
- Co-locate with the single consumer. Promote at the second consumer: within a feature, to the nearest common ancestor; across features, to the shared app level, never sideways into another feature.
- Flatten a folder that holds one file. `Foo/Foo.tsx` with no siblings is just `Foo.tsx`.
- No barrel re-export files. Import the module path directly, which also keeps tree shaking working. A barrel for a single component is fine.
- Named exports on new files, declared inline (`export const foo = ...`), not collected in a trailing export block.
- Delete dead wrappers in every shape: async-await passthrough, destructure-and-reconstruct, single-use alias, identity transform, a Promise wrapped around a Promise.
- A lookup object beats a `switch` or an `if` chain that maps a key to a value. Use thunks when the branches need per-branch work.
- Exported APIs carry a short doc comment saying what they are for, not restating the signature.
- A discriminator the backend serializes is a string enum, not a literal union: if the backend can return it, it needs a name in the code.

## React and TypeScript codebases

**Bulletproof-react is the canonical source for placement**: https://github.com/alan2207/bulletproof-react/blob/master/docs/project-structure.md

Where anything above appears to disagree with it, that document wins and this file is the one to correct.

- Feature code lives under `features/<feature>/{api,components,hooks,stores,types,utils}`, including only the subfolders that feature actually needs.
- Shared code lives at the app level: `components/`, `hooks/`, `utils/`, `types/`, `stores/`, `lib/`, `config/`.
- No cross-feature imports. Two features that need the same thing compose at the app level, or the shared thing moves up.
- Dependencies flow one way: shared can be used anywhere, features import only from shared, the app imports from both.
- Its guidance on barrel files matches the rule above: barrels were once recommended per feature and no longer are, because they break tree shaking. Import files directly.

Apply this to a repo that already uses a feature-based layout or is migrating to one. In a legacy flat layout, do not demand a migration as a side effect of unrelated work; just avoid making the existing structure more inconsistent than it already is.

Detection criteria and per-box review failure modes live in the code-review plugin's `references/structure.md` and `references/react.md`. This file is the statement of the convention; those files are how a diff gets graded against it.
