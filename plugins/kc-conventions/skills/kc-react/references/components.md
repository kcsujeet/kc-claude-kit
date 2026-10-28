# React: components

Review detail for react §R20 and §R35, moved out of `SKILL.md` to keep it under the line cap. The boxes are in `SKILL.md` under `## Review checklist`.

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
