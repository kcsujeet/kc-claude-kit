## Saved replies: U2 Picker UI

Delivered by autopilot in 2 fix rounds. Every criterion below was checked by the verifier, not the author.

### Acceptance criteria

| Criterion | Result | Evidence |
|---|---|---|
| AC2 Picking a saved reply inserts its text at the cursor. | pass | composer.test.tsx: inserts at cursor |
| AC3 An empty picker shows "No saved replies yet". | pass | screenshot qa/empty.png |

### Staff engineer

- Approach: Reuse the existing Popover; no new state library.
- Final review: Proportionate: 3 files, follows the composer pattern.

### Review

Fixed:
- picker.tsx:42 missing key on list items

Dismissed:
- extract a hook for 4 lines (used once; extraction adds indirection)

### QA

- first-time agent on a slow laptop: fixed "double-click inserted twice" (qa/double-click.png)

<details><summary>Decision log</summary>

| Step | Outcome | Reason |
|---|---|---|
| design gate | approach 2 | matches composer |
| round 1 qa | 1 bug | double insert |

</details>
