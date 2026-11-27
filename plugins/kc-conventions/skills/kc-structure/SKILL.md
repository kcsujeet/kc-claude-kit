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

- [ ] Tick every box for each construct you add or change. Report each: PASS, FAIL (file:line) or N/A (why).

- [ ] §S1 One observable responsibility per unit (function, hook, component, module): no data-reading unit also bundles a selector, formatter or mutation; no util silently performs a side effect.
- [ ] §S2 Single-consumer code stays beside its consumer; multi-consumer code sits at their nearest common ancestor; promote only when a real consumer appears; shared-layer code goes there at once.
- [ ] §S3 Single-file folders are flattened; no new or changed `index` re-exports more than its unit's main file (no barrel, no default re-export). (N/A: no folders or barrels touched)
- [ ] §S20 Helpers, constants and types of one unit sit in one `<unit>.utils`/`.constants`/`.types` file; no single-helper file (`get-foo.ts`) and no bare `utils.ts` in a unit's folder.
- [ ] §S4 No dead wrappers: one-item array wrap-and-spread, no-op async passthroughs, destructure-and-rebuild, single-use aliases, hooks returning inner results as is (list returned vs inner keys).
- [ ] §S5 Lookup objects over `switch`/`else if` chains and nested `if`; one verdict per hit of `switch-else-if-iife.sh` and `nested-ifs.sh`; a fix must not add another violation (see §S5).
- [ ] §S6 Helpers placed by consumer count: a one-consumer helper gets no subfolder of its own; a two-plus-consumer helper is not left in one consumer's local folder. (N/A: no helper added)
- [ ] §S7 Every new exported function, hook, component and props/type interface has JSDoc unless fully self-explanatory; none merely restates the name.
- [ ] §S8 New files use inline named exports (`export const Foo`), not default or a trailing `export { Foo }`; framework-mandated defaults exempt; an export nothing imports is a finding.
- [ ] §S9 Fixed-value discriminators serialized or compared at runtime (status, mode, kind) are TypeScript string enums, not literal unions, placed where the repo keeps sibling enums.
- [ ] §S10 Breaking changes are named: a removed or renamed export, changed shared prop or parameter shape, or removed or newly required exported-type field, with every importer grepped and cited.
- [ ] §S11 No context, hook or pure helper in a components folder: every hit of `misplaced-modules.sh` over changed and untracked files has a verdict naming its destination. (N/A: sweep 0 hits)
- [ ] §S12 A package's public exports are not widened only so a sibling package can import an internal; the shared piece moves to a shared package or layer. (N/A: no such new export)
- [ ] §S13 A module exports what it is named for: each export of a changed module is `own-surface` or `misplaced` (a domain enum in a hook file); `misplaced` is a finding naming its destination (§S2).
- [ ] §S14 New code belongs where put: the evidence names the unit that owns the behaviour (found by reading it) and why the member is not there; code only borrowing the home's inputs FAILS.
- [ ] §S15 One exported component per file (count per changed file); other exports move out, a private subcomponent stays only while a few lines of markup, no file only wraps one element.
- [ ] §S17 Code built for reuse (mixin, concern, trait, higher-order function, shared-folder hook) that one unit uses moves back beside that user; list each piece's users by grep.
- [ ] §S16 `app/` (the routing layer) holds only route files, their tests, route actions and the app's entry, provider or router; a component, hook, util or constant there FAILS; list new files.
- [ ] §S18 Moved and renamed files (`R` lines of `git diff -M --name-status`) pass every new-file box (exports, docs, imports, naming, placement); one verdict per line. (N/A: no file moved or renamed)
- [ ] §S19 The caller asks, the provider serves: no provider code removes, rewrites or second-guesses the caller's fields, includes or filters, or returns extra; enumerate request-shaping code.
- [ ] §S21 No generated file is edited by hand: changes go through the source and generator and the repo's drift check passes; list changed files that look generated. (N/A: no generated file changed)
- [ ] §S22 Dependencies flow one way: shared code is used anywhere, features import only from shared, the app imports both; shared code lives at the app level. (N/A: no new import between layers)

- Examples and edge cases per box: references/detail.md (read when a box is unclear).

## Sweeps

- [ ] Save the diff under review to a file (`gh pr diff <num> > /tmp/review.diff`, or `git diff <default-branch>...HEAD > /tmp/review.diff`) and run each script over it; `-` reads the diff from stdin. Each prints one `path:line: text` hit per line, where `line` is the new-side line number, and nothing else. Give every hit its own verdict, and state each receipt with its count, `0 hits` included.

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

- Code built or placed for reuse is only worth that shape when two or more units use it today. In class-based code that is a mixin, concern, trait or protocol extension. In functional code it is a higher-order function, or a hook or helper module in a shared folder. With one user it is not shared code: it hides that unit's behaviour somewhere a reader will not look, and splits one unit across two places.

- [ ] Keep it with its one user, in the same file or a file beside it, as long as that user still passes the simplicity and structure rules. When it would not (§S1: more than one responsibility; or simply too long to read), move the logic into the kind of unit this repo already uses for that sort of code, near its user, and call it from there: a service object, a plain function in its own file, a hook. Find that kind by reading how the codebase handles similar logic. If the repo has none, ask before inventing one.

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

- The exception is code whose role is the shared data or resource layer (§S2's role override): it belongs in its shared layer even with one user today.
