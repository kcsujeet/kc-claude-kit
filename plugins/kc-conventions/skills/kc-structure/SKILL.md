---
name: kc-structure
description: "Code placement and module-shape conventions: one responsibility per unit, co-location, no barrels or dead wrappers, lookup objects over switch, named exports, one component per file. Use when writing or reviewing code that adds, moves or exports a file, function, hook or type, or branches on a type."
user-invocable: false
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---

# Structure

## Contents

- Review checklist
- Sweeps

## Review checklist

Tick every box for each construct you add or change. Report each: PASS, FAIL (file:line) or N/A (why).

- [ ] §S1 Separation of concerns: each unit (function, hook, component, module) has one observable responsibility; no data-reading unit also bundles a selector, formatter, or mutation; no util silently performs a side effect. (N/A: no multi-responsibility unit added)
- [ ] §S2 Co-location/promotion: single-consumer code stays next to its consumer; multi-consumer code sits at the consumers' nearest common ancestor judged by scope/coupling, not raw count; view-local helpers are promoted only when a real external consumer appears (YAGNI-gated), not on speculation; inherently-shared-layer code is placed in its shared layer from day one regardless of current consumer count. (N/A: no files moved/added)
- [ ] §S3 Single-file folders are flattened; no new or changed `index` file re-exports more than its unit's main file (no folder, feature or package barrel), and none re-exports a default. (N/A: no folders/barrels touched)
- [ ] §S20 Helpers, constants and types used by one unit sit in one `<unit>.utils` / `.constants` / `.types` file in the unit's folder; shared ones in a file named for their subject; no new or moved file holds a single helper or constant (`get-foo.ts`), and none is a bare `utils.ts`, `constants.ts` or `types.ts` in a unit's folder. (N/A: no helper, constant or type files added or moved)
- [ ] §S4 No dead wrappers: single-item array wrap-then-spread, no-op async passthroughs, argument destructure-and-reconstruct passthroughs, single-use const aliases, verbatim object-spread, a producer value the consumer independently re-derives, promise-wrapping-a-promise, manual await-then-callback when the callee already accepts a callback, a hook or function returning an inner call's values unchanged (**enumerate**: for every changed hook, list the keys it returns and the keys it takes from inner hook calls; a key in both lists, untouched, is a passthrough), a wrapper whose only addition is an `onSuccess` or similar callback every caller could pass itself. (N/A: none added)
- [ ] §S5 Lookup objects over `switch`/nested `if`: branch-selecting-a-value uses a named map, not a switch or if/else-if chain; differing per-branch computation is handled with a thunk map, not treated as an exemption; a trailing default/else becomes the map's fallback; more than one level of `if` nesting is flattened; the branch key, if derived from multiple booleans, is built from named single-level intermediates, never a chained ternary; a fix for one violation here doesn't introduce another (e.g. replacing the map with an if-early-return helper); map entries are plain values unless a value closes over a per-call argument or must be lazy, and the map is typed so its fallback is justified; every `switch`, `else if`, and value IIFE in the added lines (`switch-else-if-iife.sh`), and every nested `if` the indentation scan reports (`nested-ifs.sh`), is enumerated with a verdict. (N/A: only when both sweeps return 0 hits, stated as `grepped switch/else-if/IIFE: 0 hits` and `nested-if scan: 0 hits`)
- [ ] §S6 Helpers placed by consumer count: a helper with exactly one consumer is not pulled into its own subfolder; a helper with two or more consumers is not left stranded in one consumer's local folder. (N/A: no helper added)
- [ ] §S7 JSDoc on every new exported function, hook, component, and props/type interface, unless the name is fully self-explanatory; no JSDoc that merely restates the name. (N/A: no new exported API, or target repo doesn't use doc comments — confirm by grep before marking N/A)
- [ ] §S8 New files use named exports (`export const Foo`), inline on the declaration, not `export default` and not a trailing `export { Foo }` block; sibling default-exported files are not an exemption; framework-mandated default exports (route/page/layout files and equivalents) are exempt; a new `export` on a constant/helper that nothing outside the file references is itself a finding — grep to confirm nothing imports it. (N/A: no new module)
- [ ] §S9 Fixed-value discriminators that get serialized/compared at runtime (status, mode, kind, origin, vendor type, etc.) are TypeScript string enums, not string-literal unions; placement matches wherever the target repo already keeps sibling enums. (N/A: no new status/mode/kind field)
- [ ] §S10 Breaking changes are named: a removed or renamed export, a changed prop or parameter shape on a shared component or exported function, and a field removed from (or made required on) an exported type are each identified as breaking, every importer is grepped and cited, and the finding stands even when the PR description says the change is not breaking. (N/A: no exported symbol, shared component signature, or exported type changed)
- [ ] §S11 No context, hook, or pure helper in a components folder: the misplaced-modules sweep (`misplaced-modules.sh`) ran over every changed AND untracked file, and each hit (a `createContext(` module, a hook file, a non-component module under a components folder) has a verdict naming its type-correct destination. (N/A: only when the sweep returns 0 hits, stated as `misplaced-modules sweep: 0 hits`)
- [ ] §S12 No package's public exports are widened only so a sibling package can reuse an internal: when a new export on a package's public entry point exists for another package in the same repo to import an implementation detail, the shared piece moves to a shared package or layer instead. (N/A: no new public-entry export consumed by another package in the repo)
- [ ] §S13 A module exports what it is named for: for every changed module (hooks, components, utils, constants, types, api modules), every export gets a verdict of `own-surface` (the named thing plus its props, argument and return types, or a one-off local constant) or `misplaced` (a domain enum or wire value in a hook file, a pure helper in a types file, a domain type in a utils file). Only `misplaced` is a finding, and it names the destination by §S2. A locally used type or constant flagged only for living in the file is itself a FAIL, so each verdict states the scope test's answer. **Enumerate**: list every export per changed module. (N/A: no export added or changed)
- [ ] §S14 New code belongs where it is put: for every new member (a method on a module, a hook, a type, a constant, a validation, a rule, a key, a style, a file), the name of its home and the members already there were read, the new code acts on that same subject, and the evidence names the unit that owns the behaviour it serves (the one holding its siblings: the other rules for that field, the other cases of that formatter), found by reading that unit's code, and why the member is not there, and when a dependency is what keeps it out, the dependency changes rather than the home (no wrapper or second copy covers for it). Code that only borrows the home's inputs or helpers without acting on its subject FAILS, and so does code placed where similar code already sits, where a reviewer pointed or where the diff happens to be open instead of in its owner; the finding names where it belongs. Matching a backend route that is itself misplaced is not a pass; flag both. (N/A: no new member added)
- [ ] §S15 One exported component per file: no new or changed component file exports more than one component (**enumerate**: count the exported components in every changed component file, one verdict per file with its count). Its other exports (hooks, helpers, shared style constants) move out to their own files, placed by §S2 and §S11, a private subcomponent stays in its consumer's file only while it is a few lines of markup (a bigger one FAILS until it has its own file in the unit's folder), and no new file only wraps one value or element. (N/A: no changed file exports a component)
- [ ] §S17 Shared only when it is shared: code built or placed for reuse (a mixin, concern, trait or protocol extension in class-based code; a higher-order function, or a hook or helper module in a shared folder, in functional code) that only one unit uses today is flagged. **Enumerate**: for each such piece the diff adds, name its users (grep). With one user it moves back next to that user (same file or a file beside it), or, when that user would then break a simplicity or structure rule, into the kind of unit the repo already uses for that logic, near its user and called from it; with no such kind in the repo, the finding says to ask first. Inherently-shared-layer code under §S2's role override is exempt. (N/A: the diff adds no mixin, concern, trait, protocol extension, higher-order function, or shared-folder hook or helper)
- [ ] §S16 `app/` holds routes only: every new file under the routing layer (`app/`, or the repo's equivalent) is a route file the framework reads by name, a test for one, a route-level action, or the app's own entry, provider or router; a component, hook, util or constant there FAILS, even beside existing ones, since precedent is not an exemption. **Enumerate**: list every new file under it with a verdict. (N/A: no new file under the routing layer)
- [ ] §S18 Moved and renamed files are graded as new: every file the diff moves or renames (the `R` lines of `git diff -M --name-status`) passes every new-file box (exports, doc comments, imports, naming, placement), even where the old file did not. **Enumerate** the `R` lines with a verdict each. (N/A: no file moved or renamed)
- [ ] §S19 The caller asks, the provider serves: no added code in a provider removes, rewrites or second-guesses what its caller asked for (fields, related data, filters, options), and none loads or returns extra the caller did not ask for. What a caller may reach is limited by what the provider declares, not by editing the request. **Enumerate** request-shaping and eager-loading code the diff adds. (N/A: no provider added or changed)
- [ ] §S21 No generated file is edited by hand: every changed file that the repo generates (named in its README, CI config or a header comment) changed only through its source and the generator, and the repo's drift check passes. **Enumerate** changed files that look generated (a build or `--check` script names them, or a header says generated) with a verdict each. (N/A: no generated file changed)
- [ ] §S22 Dependencies flow one way: shared code is used anywhere, features import only from shared, the app imports from both; shared code lives at the app level (`components/`, `hooks/`, `utils/`, `lib/`). (N/A: no new import between layers)

Examples and edge cases per box: references/detail.md (read when a box is unclear).

## Sweeps

Save the diff under review to a file (`gh pr diff <num> > /tmp/review.diff`, or `git diff <default-branch>...HEAD > /tmp/review.diff`) and run each script over it; `-` reads the diff from stdin. Each prints one `path:line: text` hit per line, where `line` is the new-side line number, and nothing else. Give every hit its own verdict, and state each receipt with its count, `0 hits` included.

- `added-lines.sh` (citation map): every added line as `path:line: text`, with the source line number at the head SHA. Cite every finding's line from this output or from a sweep hit, never from a position in the diff file.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/added-lines.sh" <diff-file>
  ```

- `switch-else-if-iife.sh` (§S5): added lines holding a `switch`, an `else if`, or an IIFE assigned to a value. Receipt: `grepped switch/else-if/IIFE: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-structure/scripts/switch-else-if-iife.sh" <diff-file>
  ```

- `nested-ifs.sh` (§S5): nested `if` statements on added lines, found by an indentation scan of each changed file. It reads the files, so run it from the repo root with the diff's new side checked out, or pass the root as a second argument. Receipt: `nested-if scan: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-structure/scripts/nested-ifs.sh" <diff-file>
  ```

- `misplaced-modules.sh` (§S11): a context, hook, or non-component module under a components folder, over every changed and untracked file. It reads the files and `git ls-files`, so run it from the repo root, or pass the root as a second argument. A file-level hit is reported at line 1 with its reason in place of the line text. Receipt: `misplaced-modules sweep: N hits`.

  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/kc-structure/scripts/misplaced-modules.sh" <diff-file>
  ```

### §S17. Shared only when it is shared

Code built or placed for reuse is only worth that shape when two or more units use it today. In class-based code that is a mixin, concern, trait or protocol extension. In functional code it is a higher-order function, or a hook or helper module in a shared folder. With one user it is not shared code: it hides that unit's behaviour somewhere a reader will not look, and splits one unit across two places.

Keep it with its one user, in the same file or a file beside it, as long as that user still passes the simplicity and structure rules. When it would not (§S1: more than one responsibility; or simply too long to read), move the logic into the kind of unit this repo already uses for that sort of code, near its user, and call it from there: a service object, a plain function in its own file, a hook. Find that kind by reading how the codebase handles similar logic. If the repo has none, ask before inventing one.

```ruby
# FAIL: a concern only Storefront includes; its callbacks live in another file
module SetsUpFirstStorefront
  extend ActiveSupport::Concern
  included { after_create :link_staff, if: :first_in_shop? }
end

# PASS: the model keeps the callback and calls the repo's existing kind of unit
class Storefront < ApplicationRecord
  after_create -> { Storefronts::Setup.link_staff(self) }, if: :first_in_shop?
end
```

```ts
// FAIL: a higher-order component in shared/ that wraps exactly one page
export const withInvoiceTotals = (Page) => (props) => <Page {...props} totals={useTotals(props.id)} />

// PASS: the one page calls the hook itself
const InvoicePage = ({ id }) => { const totals = useTotals(id); ... }
```

The exception is code whose role is the shared data or resource layer (§S2's role override): it belongs in its shared layer even with one user today.
