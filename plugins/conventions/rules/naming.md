---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,swift,go,java,kt,php,cs,rs}"
---
<!-- Generated from skills/naming/SKILL.md by scripts/build-rules.sh. Edit the skill, not this file. -->

# Naming

A name is read far more often than it is written, and a wrong one survives refactors. Pick the existing word; do not coin a new one.

- One word per concept, reused everywhere. If the codebase says `booking`, never introduce `reservation` for the same thing.
- Name the role, not the type or the shape: `activeBookings`, not `data`, `result`, `temp`, `items`, `obj`, `arr`.
- Functions read verb-noun: `createBooking`, `listBookings`, `updateBooking`. Not `handle`, `process`, `doStuff`, `save` when it means create-or-update.
- Booleans read as assertions: `isSyncing`, `hasBalance`, `canEdit`, `shouldRetry`.
- A name must read as a true sentence about what it holds. Watch for the four common lies: the subject elided (`items` in a file about invoices), the context borrowed as subject (`total` that is really `taxTotal`), the name left stale after a refactor, and a familiar shape hiding different behaviour (`useQuery` that mutates).
- A boolean chain with two or more non-obvious operands (raw comparisons, enum equality, negations, optional field access) gets **each** operand extracted to its own named boolean. Naming the whole chain does not count: `const canSubmit = a && b > 0 && c !== Locked` still leaves three unnamed conditions for the reader to decode.
- A name must be unambiguous **where it is read**, not where it is declared. Beside the declaration the surrounding lines supply the subject for free; at the use site they do not. A bare generic verb or noun that names the mechanism rather than the subject (`check`, `run`, `wrap`, `guard`, `handle`) is wrong even when it is accurate, and so is a boolean prefix on a bare state word (`isOn`, `isOpen`, `hasData`: on what? open what?), and any name that collides with an unrelated declaration elsewhere. Applies to locals as much as exports; distance and collision are what matter, not module boundaries.
- A domain check that combines fields or hides a rule (`widget.provider === Provider.A && !widget.disconnectedAt`) and appears 3 or more times in the repo becomes a named `isX` from the module that owns the data. One field compared to one enum value (`status === Status.DONE`) already reads as the question, so it stays inline at any count.
- A name says, at the import site with no folder path, what kind of thing it is (a data hook, a form-state hook, a component, a util, a constant) and what it belongs to. A hook that only fills one form's fields does not read like a data hook.
- Parts of one unit keep its prefix and end with their kind: the parts of `WidgetPanel` are `WidgetPanelSyncSection` and `WidgetPanelRow`, not `WidgetPanelSync` (reads like a second panel) or `WidgetSyncSection` (loses the family).
- Match the language's own casing: `snake_case` columns and plural tables in SQL, `UpperCamelCase` types with the file named after the type, `kebab-case` plural nouns in routes.
- A file name identifies the file without its path. Tabs, search results and stack traces show it bare, so `header.tsx` deep in a feature folder is `widget-list-header.tsx`, and no two files share a basename unless the framework requires it.
- Before naming a new file, look at 2-3 existing files of the same kind and follow their naming pattern and location. Sibling precedent never excuses a generic or colliding basename: the subject still goes in the name.

- When a change alters what a thing is (one becomes many, a page becomes a list with a page per record, a setting moves onto each item), the names that describe the old shape are wrong now, even though the diff never touched them. Route segments, folders, files, exports, API paths, query keys and translation keys get the name the repo gives that new shape, or the change says why one has to wait (a public URL that needs a redirect first).
- When a resource is served in more than one variant (public and admin, signed-in and anonymous, v1 and v2), every unit that serves one variant carries that variant's qualifier the same way: the client or resource, its data hooks, cache keys, path constants and test fixtures. The qualifier sits once, on the container: a public resource's methods are `getStore`, not `getPublicStore`.
Detection criteria and per-box review failure modes live in the `## Review checklist` of the `naming` skill (`conventions:naming`), with the detail under its `## Review detail`. These rules are the statement of the convention; that checklist is how a diff gets graded against it.
