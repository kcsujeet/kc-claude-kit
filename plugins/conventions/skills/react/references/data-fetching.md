# React: data fetching

Review detail for react §R11-§R13, §R21-§R23 and §R27, moved out of `SKILL.md` to keep it under the line cap. The boxes are in `SKILL.md` under `## Review checklist`.

## §R11. Reads and writes live in separate hooks

No raw `fetch`/`axios`/`useMutation`/`useQuery` call inside a component — they belong in the project's data-hook layer. Grep how sibling features structure their read/write hooks before proposing a shape; match it. A hook that mixes a query and a mutation, or a component that inlines either, is a finding — point at the sibling pattern.

## §R12. Fetch ownership — by consumer, not convenience

When a read hook is added or moved, ask **where it belongs**, not just whether it works. The fetch should live with the component that actually *consumes* the data: single consumer → the consumer owns it; several siblings need it → lift to their nearest common parent.

Two failure modes:
- **Duplicated ownership** — a parent fetches a list a child already fetches for itself. With identical query keys the cache layer dedupes to one request, but **different params = different keys = two separate requests**, owned in two places that can drift.
- **Over-fetch for a derived flag** — pulling a full list only to compute a boolean (is-it-empty, show/hide a tab, gate a skeleton) is wasteful, and gating a whole page's skeleton on data only one section needs blocks the rest of the page.

```tsx
// Flag: parent fetches the whole list just to gate visibility, while a child
// already fetches (a filtered version of) the same data
const { data: items, isLoading } = useItems({ enabled })
if (isLoading) return <Skeleton />
// ...elsewhere: <ChildList /> independently calls useItems({ filter })

// Prefer: the consumer owns the fetch; let it render its own empty/loading state
```

Name the consumers in the review and ask whether the fetch is at the right altitude.

## §R13. Invalidation last resort; `mutate` + callbacks over `mutateAsync` + `await`

**Invalidation is a last resort.** Forcing a refetch is a network round-trip plus a loading flicker, and better tools usually exist. Order of preference: (1) the mutation returns the updated record — patch the cache directly on success; (2) a surgical cache update (add/remove/update one item in a list cache) without hitting the network; (3) only when neither is feasible, invalidate/refetch. (This is react-query framing since it's the dominant library; if the target repo uses SWR/RTK-Query or similar, map to its equivalents.) **Look first, flag second** — read what the mutation does and what the server returns before flagging; some invalidations are genuinely necessary (server-side cascading effects the client can't model).

**Prefer `mutate` + callbacks over `mutateAsync` + `await`.** Use `mutate(variables, { onSuccess, onError })` by default. Reach for `mutateAsync` + `await` only when: a subsequent statement in the same control flow genuinely depends on the resolved value and can't move into `onSuccess`; the caller's own contract requires returning a promise that resolves after the mutation completes; or multiple mutations must sequence in a way too tangled for nested `onSuccess`.

```ts
// Flag: resolved value only drives a side effect
const handleSubmit = async () => {
  const result = await someMutation.mutateAsync(variables)
  doSideEffect(result)
}

// Better
const handleSubmit = () => {
  someMutation.mutate(variables, { onSuccess: (result) => doSideEffect(result) })
}
```

Test: does the resolved value only drive a side effect (snackbar, redirect, cache patch, parent callback)? If yes, it belongs in `onSuccess` — errors flow through `onError` without a `try/catch` per call site, and pending/error state stays in sync automatically.

**Enumerate `mutateAsync` by grep, do not eyeball.** This box is graded on whether the hits were listed, not on whether they were noticed. Find them mechanically over the diff's added lines with the `mutate-async.sh` sweep (listed under `## Sweeps` in `SKILL.md`).

Emit one line per hit with a verdict:

```
grepped mutateAsync: 2 hits
- [FAIL] useSubmitOrder.ts:34: resolved value only drives a snackbar; switch to `mutate` + `onSuccess`
- [PASS] useCheckoutFlow.ts:52: awaited because the caller's own contract returns a promise after settlement
```

**Silence is not a pass:** a sweep that finds none must print `grepped mutateAsync: 0 hits` explicitly, so "no receipt" is never mistaken for "nothing there."

## §R21. A request's method matches its effect

A request that only reads and saves nothing uses GET. A read hook whose request goes out as POST, PUT or PATCH tells every reader, proxy and cache that it changes something, and it skips the HTTP caching a GET gets. The exception is input that genuinely cannot fit in a query string (a large or deeply nested filter the API only accepts as a body); say so in a comment where the request is made. Before flagging, check how the repo's API client already encodes arrays and nested objects in a query string; it often handles more than expected.

## §R22. A cache patch targets the narrowest key that shows the change

After a write, patch the cache entry that shows the changed record, and no wider. An update to one widget patches that widget's own key (`['widgets', widgetId]`) when that is where it is shown; the broad base key (`['widgets']`) is used only when lists that show the same record need the patch too, with a comment saying so. A broad patch or invalidation touches every cached list and detail under the key, re-rendering (or refetching) screens the change does not affect. The same goes for invalidation: invalidate the narrowest key that is stale.

## §R23. A write hook touches only its own resource

The hook that holds a resource's writes (`useWidgetActions`, or the repo's equivalent) calls that resource's requests and nothing else. When a widget screen also needs to change a gadget, the gadget mutation lives in the gadget's write hook beside its siblings, and the component composes the two, updating its own cached data in the call's `onSuccess`:

```ts
const { syncGadgetMutation } = useGadgetActions()

syncGadgetMutation.mutate(gadget.id, {
  onSuccess: (syncedGadget) => patchWidgetCache({ ...widget, gadget: syncedGadget })
})
```

A gadget request inside `useWidgetActions` hides a gadget write in the widget layer, where nobody looking for gadget writes will find it. Check the imports: a write hook that imports another resource's request module or hook is the tell.

## §R27. A read hook wires up every option it accepts

When the repo has a standard argument shape for read hooks (an `enabled` flag, query options such as `onSuccess`, a key override, extra query params), a new read hook accepts that shape, extended with its own fields, rather than re-declaring a subset. And it wires every field it accepts: a hook that takes the standard options but reads only `enabled` advertises an API it does not honour, and a caller's `onSuccess` silently never runs. Accept-and-ignore is dead surface. Compare with 2 sibling read hooks and pass each field through the way they do.
