---
name: naming-noun-predicate
description: A review request for a TypeScript predicate named as a noun phrase fires the naming skill, and the reply flags the name.
tags: [naming, review, positive]
max_turns: 6
allowed_tools: [Skill, Read, Grep, Glob]
---

Review this TypeScript before I merge it. Anything you would change?

```ts
export const sameOwner = (a: Widget, b: Widget): boolean => a.ownerId === b.ownerId

export const listSharedWidgets = (widgets: Widget[], current: Widget): Widget[] =>
  widgets.filter((widget) => sameOwner(widget, current))
```
