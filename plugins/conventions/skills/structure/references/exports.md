# Structure: exports and public API

Review detail for structure §S7, §S8, §S10, §S12 and §S13, moved out of `SKILL.md` to keep it under the line cap. The boxes are in `SKILL.md` under `## Review checklist`.

## §S7. JSDoc on exported APIs

Exported APIs carry doc comments so a consumer reading at the call site can hover and see what the thing does, what its parameters mean, and what it returns, without opening the source. Internal helpers used in only one file generally don't need it. Before flagging density on this box, grep the target repo to confirm it actually uses doc comments as a convention — don't impose the rule on a repo that doesn't.

**Where doc comments are expected:**
- Exported utility functions in shared helper locations.
- Exported custom hooks, whether shared or feature-scoped.
- Exported components, especially shared ones used across features.
- Exported types and props interfaces, particularly when the type name doesn't fully describe the shape.

**Standard tags:** parameter descriptions with type, return description, a component/type marker where the language convention supports one. Keep descriptions concise — one or two lines beats a paragraph.

**What to flag:**
- A new exported function, hook, or component with no doc comment at all.
- A new exported props/type interface where the field names aren't self-explanatory and there's no per-field description.
- A doc comment that just restates the function name (`/** Get the user. */` above `getUser()`) — the restates-the-name flag applies everywhere, regardless of what kind of unit it's on. Either deepen it or drop it.

**What NOT to flag:**
- Internal helpers (not exported, used in one file).
- Trivially-named exports where the name fully describes the behavior (`isProduction`, `EMPTY_ARRAY`).
- Existing files that already lack doc comments, if the PR isn't adding new exports there — retroactive additions are out of scope for a feature PR.

## §S8. Named exports for new modules

New files should use `export const Foo = …` / `export function foo` over `export default`. Existing `export default` declarations are fine — don't churn old code just for style. Framework-mandated default exports (route/page/layout files and any similar convention where the framework specifically reads `default`) are exempt; flag those as the only allowed defaults.

**Why named over default:**

1. **Refactor safety.** Renaming a named export forces every import site to update (a type error at each call site). Default imports invent a local name at every call site, so renaming the source doesn't propagate — different files end up with different local names pointing at the same value.
2. **Find-references in IDEs.** "Find all usages" works cleanly on a named export across the whole repo; on a default export, the search has to match arbitrary local names callers invented, which it can't.
3. **Auto-import.** Editors surface named exports cleanly with their canonical name; default exports either don't auto-suggest or suggest whatever name the editor inferred from the filename, which decays as files get renamed.
4. **Explicit API surface.** `export { Foo, fooHelper }` reads as a deliberate public contract. A default plus a stray named export muddles which is "the" thing in the file.
5. **Tree-shaking.** Named exports compose better with bundler dead-code elimination, which matters most for shared packages consumed by multiple apps.

**What to flag:**
- A new component / hook / util that exports `default` instead of a named const.
- A new app-level hook using `export default` because its siblings in the same folder are all default-export. Sibling defaults are exactly the "looks like conformance" trap this rule overrides — "the existing hooks here are default" is not a valid reason to keep the new one default. Flag it at the same weight as a new component.
- A default export in a file that already has named exports of related helpers (mixed signal — make all named).

**What NOT to flag:**
- Framework route files (page/layout/loading/error/not-found equivalents) that require `export default` by convention.
- Existing default exports on files not being substantively edited in this PR.
- Existing default-plus-named mixed files in a legacy area the PR isn't touching.

**Unnecessary exports.** A new `export` on a constant, type, or helper that nothing outside its own file actually imports is a finding independent of named-vs-default: an export advertises an API contract to the rest of the codebase, and a contract nothing has taken up yet is speculative surface area (the YAGNI lens applies here too). Grep the target repo for the identifier before flagging — confirm zero external importers, cite the `0 hits` grep result, then drop the `export` keyword. Internal-only reuse within the same file never needs it.

**One-line counter-example:**

Bad — new component file:
```ts
const Foo = (props: FooProps) => <div />
export default Foo
```

Good:
```ts
export const Foo = (props: FooProps) => <div />
```

The diff is one line, and from then on `Foo` is `Foo` everywhere.

**§S8.1 — inline `export const`, not a trailing `export { Foo }` block.** Even when the export is already named, prefer attaching `export` to the declaration over declaring `const Foo = …` then re-exporting it at the bottom of the file with `export { Foo }`. Both are named exports; the inline form keeps the export adjacent to the declaration instead of a redundant statement the reader has to scroll to find. A trailing `export { … }` block earns its place only when re-exporting from elsewhere or intentionally grouping several already-declared names together.

```ts
// Flag: declaration and export split across the file
const Foo = (props: FooProps) => <div />
// ...
export { Foo }

// Better: export on the declaration
export const Foo = (props: FooProps) => <div />
```

This is a nitpick-severity consistency item, not an §S8 failure (the export is already named). Flag it when a new file uses the trailing form, especially when several new sibling files all do.

## §S10. Breaking changes are named, whatever the description says

A change to a public or shared API can break a caller the diff never shows. Walk every changed export, shared component signature, and exported type, and treat these as breaking:

- An export removed or renamed.
- A prop or parameter removed, renamed, retyped, or reordered on a shared component or exported function.
- A field removed from an exported type, or an optional field made required. Consumers who construct the type as a literal stop compiling, even though the library itself always passes the value.

For each, grep the target repo for importers and cite the count and paths. When the package is published, the importers you can grep are not all of them; say so in the finding. The finding stands even when the PR description says "no breaking changes" or "internal only": the description is a claim, and the signature is the evidence. The usual remedy is the non-breaking shape (keep the field optional with a default, keep the old export as a deprecated alias) unless the break is intended, in which case the finding asks for it to be stated and versioned.

## §S12. Do not widen a public API to share an internal

In a repo with several packages, the tempting fix for "package B needs a helper that lives inside package A" is to export it from A's public entry point. That turns an implementation detail into a public contract A now has to keep, and couples B to A's internals. When a new export on a package's public entry exists for a sibling package to import (grep the sibling's imports to confirm), the shared piece belongs in a shared package or layer that both consume.

This is distinct from §S8's unnecessary exports: there, nothing imports the new export; here, something does, and the question is whether it should be importing it from there. Do not flag an export that is part of the package's intended public API for its real consumers; flag the one that exists only to let a sibling reach inside.

## §S13. A module exports what it is named for

A module exports the thing it is named for, plus whatever describes that thing's own surface: `use-widget.ts` exports `useWidget` and its argument and return types, `widget-card.tsx` exports `WidgetCard` and its props, `format-price.ts` exports `formatPrice`. This applies to every module, utils, constants, types and api modules included.

**Move it out** when the export is unrelated to what the module is named for, or outlives it: an enum or constant naming a domain state or wire value, a pure function with no tie to the module's subject that another feature could want, a type describing a domain object rather than this module's own surface. Where it lands is decided by §S2 and the bulletproof-react layout (the feature's `types/` or `utils/`, or the shared level when several features use it).

```ts
// Flag: use-widget.ts
export enum WidgetMode { DRAFT = 'draft', LIVE = 'live' }   // domain enum
export const getWidgetMode = (count: number) => (count > 0 ? WidgetMode.LIVE : WidgetMode.DRAFT) // pure helper
export const useWidget = () => { /* ... */ }

// Prefer: the enum and helper move to the feature's types/ and utils/; use-widget.ts exports useWidget
```

**Leave it** when it only describes the module's own surface and has a small, local audience: the props interface, the hook's argument or return type, a one-off constant used by this module and maybe one neighbour. A type that exists to type this hook's props does not earn a file of its own.

**The test:** would a reader look for this somewhere other than the file that defines it? If yes, move it. If the only consumers are the module itself and its immediate callers, leave it. Over-flagging a locally used type is itself a miss, so every verdict states the test's answer.

An export that only delegates to something that already exists elsewhere (a hook-file function wrapping a util, a re-export that adds nothing) is wrong placement and a dead wrapper (§S4) at once.
