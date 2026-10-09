# React: forms

Review detail for react §R14 and §R24-§R26, moved out of `SKILL.md` to keep it under the line cap. The boxes are in `SKILL.md` under `## Review checklist`.

## §R14. Form is the single source of truth; validate via the library's own API

**No `useState` shadowing a form-held value.** When a form-bound input already holds a value, don't keep a parallel `useState` just to read it in a handler.

- **One-shot read** (submit handler, onClick): the library's one-shot getter (e.g. `getValues('foo')`), or the submit handler's own data argument. Note: a one-shot getter does not subscribe — it won't re-render the component when the value changes, unlike a reactive watch.
- **Reactive read** (a dependent field, a preview that must update live): the library's reactive watch equivalent (e.g. `useWatch`).

```tsx
// Flag: shadows the form value with parallel state
const [selected, setSelected] = useState<Foo>()
const handleChange = (foo?: Foo) => setSelected(foo)
const handleSubmit = methods.handleSubmit(() => selected && mutate(selected))
return <FooAutocomplete onChange={handleChange} />

// Better: read straight from the form
const handleSubmit = methods.handleSubmit((data) => data.foo && mutate(data.foo))
return <FooAutocomplete />
```

Why: two sources of truth get out of sync (a form reset, `defaultValues`, or a programmatic `setValue` all bypass the `useState`); the `onChange` that updates local state is a dead wrapper around the form's own `onChange`. **Flag whenever** a `useState<DomainRecord>` sits adjacent to a form-bound input with an `onChange` that just calls the setter — the setter, the state, and the handler are all redundant.

**Validation schemas: check the library's API before hand-rolling.** Whatever validation library the target repo uses (zod, yup, and similar), any hand-rolled `check`/`refine`/inline regex/`.length`/manual `Number(...)` comparison that re-implements something the library already ships natively is a finding, regardless of data type. Before flagging, open the library's own API docs and look for a native validator/transform covering the same rule.

- Coerce the input once in a `transform`, then validate with native rules — don't sprinkle `Number(value)` inside every check.
- Optionality/blank handling uses the library's own `optional`/`nullable`/`nullish` combinators, not a hand-written short-circuit.
- Any surviving hand-rolled check should be genuinely custom (cross-field, a domain invariant, a conditional requirement) — say so in the finding, so the reader knows it was considered, not missed.

```ts
// Flag: manual coercion repeated inside checks
check((v) => Number(v) >= 0) // and again in another check

// Better: coerce once, validate with the library's native actions
pipe(union([string(), number()]), transform((v) => (v === '' ? 0 : Number(v))), minValue(0))
```

## §R24. A form-state hook returns form plumbing only

The hook that sets up a form (`useWidgetForm`, or the repo's equivalent) returns the form's plumbing: the form methods, submit and discard handlers, and the saving state. Logic that belongs to one field (fetching its options, reacting to another field, holding a lookup's results in state) lives in that field's own component, or in the form component when it is small. Everything about the field then reads top to bottom in one file, and the hook stays about the form. A form hook that returns field data or field handlers (`gadgetOptions`, `loadOwnerGadgets`, `onPickGadget`) fails.

## §R25. A watch subscription lives in the smallest component that renders from it

A form watch (`useWatch`, `watch`, or the library's equivalent) re-renders the component that calls it on every change. Called in a small fields component, only that component updates; called in the form or its setup hook, every keystroke re-renders the whole form and every child. So each watch, and each piece of field state, lives in the smallest component that renders from it, and a child reads shared form values itself through the form context instead of the parent watching them and passing them down as props.

```tsx
// Flag: the form watches a value only one child renders from
const ownerId = useWatch({ control: methods.control, name: 'owner_id' })
<WidgetGadgetFields ownerId={ownerId} />

// Prefer: the child subscribes itself
const WidgetGadgetFields = () => {
  const ownerId = useWatch({ name: 'owner_id' })
  // ...
}
```

A watch high up passes only when that component renders from the value too.

## §R26. A form editing a record seeds the related record, not just its id

A picker bound to an id field (`owner_id`) usually renders its selected label from the related record held in form state (`owner`). A form that edits an existing record seeds both halves in its default values; cloning the whole record gets this for free. Two findings follow:

- **Default values that cherry-pick ids** (`{ owner_id: widget.owner_id }`) drop the record. The label renders while the selected option happens to be in the fetched page of options, then blanks out as soon as the list is searched or paginated.
- **A label prop hand-built from that same record** (`defaultOption={{ value: widget.owner.id, label: widget.owner.name }}`) is a dead wrapper once the record is seeded.

Read how the repo's picker renders its selection before flagging, and cite it.
