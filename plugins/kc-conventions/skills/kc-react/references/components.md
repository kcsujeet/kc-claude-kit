# React: components

Review detail for react §R20, §R35, §R36 and §R37, moved out of `SKILL.md` to keep it under the line cap. The boxes are in `SKILL.md` under `## Review checklist`.

## §R20. React 19: `ref` is a prop, `forwardRef` is not needed

Check the project's React version first; this box applies from React 19. There `ref` is an ordinary prop, so new components take it in their props and never use `forwardRef`:

```tsx
// Flag
export const WidgetInput = forwardRef<WidgetInputHandle, WidgetInputProps>(({ label }, ref) => { /* ... */ })

// Prefer
interface WidgetInputProps { label: string; ref?: Ref<WidgetInputHandle> }
export const WidgetInput = ({ label, ref }: WidgetInputProps) => { /* ... */ }
```

**The half-migrated case is the one to look for:** a props type that already declares `ref?: Ref<T>` while the component is still wrapped in `forwardRef`. `forwardRef` strips `ref` out of props, so the declaration is unreachable and misleading.

## §R35. An empty slot reads as empty

A slot with nothing in it (no logo uploaded, no attachment, no photo) has to look unfilled at a glance. Two ways it goes wrong:

- **Styled like content.** A large tinted tile with a bold icon, the same frame and weight as a real image, reads as "uploaded". Use the muted, bordered look the codebase gives its other empty slots, and cite two of them.
- **The wrong icon.** The icon names what goes there: an image icon for a logo or a background, a document icon for a file, a person only for a person's photo. A generic default that happens to be a person tells the reader a profile picture is expected.

When the shared component's default icon is wrong for the slot, pass the right one in rather than changing the default for every caller.

## §R36. A record picker is the codebase's picker component

Most codebases have one picker component per kind of record (`OwnerAutocomplete`, `TagSelect`), each in its own file, taking the narrowing (a filter, a status, a parent) as props and passing it to the server. A new field that picks records reuses that component, or adds one in the same shape when none exists, rather than fetching inside the form and mapping an options list inline.

Copy what the existing pickers do: the props they take, the default field name, how ids are converted, and how they handle an empty list (a disabled picker with a reason, a hint). Cite two.

## §R37. Shared markup is a component, not a hook that returns it

When two components render the same labelled control, extract a component that takes what differs as props (`disabled`, a type, which options are allowed). A hook or helper that returns options with JSX labels, for each caller to drop into its own control, splits one piece of UI across files and still leaves each caller assembling the control. The exception is a codebase API that itself takes options with node labels, where similar call sites build them inline.
