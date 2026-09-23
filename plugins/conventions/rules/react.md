---
paths:
  - "**/*.{tsx,jsx}"
  - "**/hooks/**/*.{ts,js}"
  - "**/api/**/*.{ts,js}"
---
<!-- Generated from skills/react/SKILL.md by scripts/build-rules.sh. Edit the skill, not this file. -->

# React

Placement is covered by the `structure` skill, which defers to bulletproof-react. This file is everything else: how components, data access, forms and state are built.

## Components and markup

- A component owns its own container. It never leaves a required wrapper to the caller, and never sets root `size`, `flexGrow` or self-margins that only work under one particular parent.
- Conditional element assembly is a named local component with early returns, not a `let` reassigned through `if/else` and not a multi-line ternary building markup inline.
- Three or more structurally identical sibling blocks that differ only by data become a map over an array, with stable keys.
- No index as a key for anything reorderable, and never mix indices taken from a filtered list with an unfiltered one.
- No side-effect-only component: a `useEffect` with `return null` is a hook or an HOC, not a component.
- No `renderSomething()` inline render functions, and no skipping items by returning null from a ternary inside a map. Filter first.
- Assign a hook result to a variable, then derive on the next line. Never inline a selector or subscription inside a transforming expression.
- Do not reach for `useMemo` or `useCallback` by default when the project runs React Compiler. Write the plain value or function.
- Without React Compiler, a `useMemo` or `useCallback` has to hit: empty dependencies mean a module constant, and a dependency that changes every render (an inline object, array or function) means the memo never does. Pass stable references to memoized children.
- A block of markup past about thirty lines that reads as its own unit is a named component, and a wrapper element that only repeats its parent's styling is deleted.

## Data access

- Reads and writes live in separate hooks. A component contains no raw `fetch`, no `axios`, no direct `useQuery` or `useMutation` call; grep how the sibling features do it and follow that.
- The fetch lives with the actual consumer. A page does not duplicate a fetch its child already owns, especially with different params, and nothing fetches a whole list to derive one boolean.
- After a write, patch the cache first, then update surgically, and invalidate only as a last resort.
- Prefer `mutate` with callbacks over `mutateAsync` with `await` when the resolved value only drives a side effect.

## Forms and state

- The form is the single source of truth. No `useState` shadowing a value the form already holds.
- Check the validation library's own API before hand-rolling a check, a regex, or a coercion. Most of them already exist there.
- New state lives at the lowest common ancestor of its actual consumers, never lifted because a parent might want it later.
- Two state updates whose order matters carry a one-line comment at the call site saying why.
- A child that needs two or more props derived from one hook the parent called should call the hook itself.

Detection criteria and per-box review failure modes live in the `## Review checklist` of the `react` skill (`conventions:react`), with the detail under its `## Review detail`. These rules are the statement of the convention; that checklist is how a diff gets graded against it.
