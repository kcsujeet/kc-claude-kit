# Structure: file and folder shape

Review detail for structure §S3 and §S20, moved out of `SKILL.md` to keep it under the line cap. The boxes are in `SKILL.md` under `## Review checklist`.

## §S3. Flatten single-file folders; no re-export barrels

**Single-file folders: flatten.** A folder containing exactly one file (no sub-components, no co-located hook, no helpers, no styles, no test) is dead structure — drop the folder, leave the file at the parent level. The folder earns its place the moment a second file appears alongside.

**No `export { default } from './X'` re-export barrels.** A single-item `index.ts` that exists only to shorten an import path adds no value: it perpetuates the default-export anti-pattern (§S8) and the importer can resolve the actual file directly with one extra path segment. Either flatten the folder or have the importer reach the file directly. This is distinct from a real barrel that groups several already-declared named exports with intent — that earns its place; a barrel whose sole content is one re-exported default does not.

## §S20. A unit's helpers share one file named for the unit

Helpers, constants and types live at the level their consumers decide (§S2), and each level has one file shape. In a React codebase the app and feature levels are bulletproof-react's layout (the structure skill's React section), which this rule doesn't change; the unit level is this kit's own addition below what bulletproof-react covers.

- **Shared across packages or apps:** the shared utils package, one file per subject (`dates.ts`, `currency.ts`) holding that subject's functions.
- **Shared across one app:** the app's `utils/` folder; **within one feature:** `features/<feature>/utils/`. Again one file per subject.
- **Used by one unit** (a component, a form, a screen): one file in the unit's folder, named for the unit and the kind of thing it holds, `<unit>.utils.ts`, beside `<unit>.tsx` and its hook. Its constants and types follow the same form (`<unit>.constants.ts`, `<unit>.types.ts`) when they need a file apart from the code that uses them. Match the unit's own casing (`OrderForm.utils.ts`, `order-form.utils.ts`).

Two shapes fail:

- **A file per function or constant** (`getOrderTotal.ts`, `defaultOrderStatus.ts`). It scatters one unit's logic across many small files, adds an import line per helper, and makes a reader open several files to follow one flow. Related helpers belong together in their subject's or unit's file.
- **A bare `utils.ts`, `constants.ts` or `types.ts` inside a unit's folder.** Repeated in every folder, the name says nothing on its own: a file-name search returns dozens of identical hits, and editor tabs and stack traces show the same name for different files. `<unit>.utils.ts` is unique in search, sorts next to its unit in the folder, and says whose helpers it holds.

Applies to new and moved files (§S18). An existing file in the old shape is renamed when its unit is already being changed, not as a side effect of unrelated work. A repo with its own stated rule for this follows that rule.

The §S11 sweep lists a `<unit>.utils.ts` under a components folder as a candidate: it passes when its only consumers are that unit (§S2).
