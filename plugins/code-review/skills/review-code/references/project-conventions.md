# Project-conventions gate

This is the plugin's per-repo extension point. Every other gate in this skill ships fixed rules; this one instead reads the *target repo's own* `.claude/review-conventions.md` and turns whatever it says into first-class review rules for that repo only.

## Purpose

The agent looks for `.claude/review-conventions.md` at the target repo root.

- **Present:** every rule in it becomes a gate box, walked exactly like a built-in rule.
- **Absent:** the gate is `PASS (N/A: no .claude/review-conventions.md in target repo)`. State plainly that the file was looked for and not found — don't invent conventions for a repo that hasn't written any down.

## Agent instructions

1. **Read the ENTIRE conventions file.** Not a skim, not the section that looks relevant to the diff — the whole file, same as any other owned reference.
2. **Treat every rule in it exactly like a built-in gate rule.** A single violation is a finding. Severity follows the built-in rubric (🔴 must-fix / 🟠 should-address / 🟡 low) unless the conventions file states its own severities, in which case those win.
3. **Verify each cited convention is real in that repo before flagging it.** Repo conventions files go stale — a rule can outlive the pattern it described. Before citing a rule in a finding, grep the target repo for 2–3 examples of the convention in current code. If the dominant current pattern contradicts the written rule, do not silently enforce the stale rule and do not silently drop it either — report it to the user as "conventions file may be stale" with the contradicting examples, and let the user decide.
4. **Walk the file's own checklist if it has one.** If `.claude/review-conventions.md` ends with its own `## Gate checklist`, walk it box-by-box exactly like this gate's own checklist below. If the file is prose-only with no checklist, derive one box per rule yourself and say so explicitly in the evidence (e.g. "no `## Gate checklist` in source file; boxes derived one-per-rule").
5. **Defer to built-ins on overlap.** If a rule in the conventions file duplicates a built-in gate (naming, clarity, structure, simplicity, datetime, react, i18n, verification), that finding is reported under the built-in gate, not here. Don't double-report the same violation under two gates.

## Format guide for repo authors

This section is what a repo author reads before writing `.claude/review-conventions.md`. Follow this shape so the file is gate-consumable, not just documentation.

- **One rule per section.** Don't bundle unrelated constraints under one heading — each gets its own box below and its own section here.
- **Principle first, examples second.** State the rule in one or two sentences before showing any code. Label code samples as illustrations of the principle, not the definition of it — the agent grades against the stated principle, and an example that drifts from prose over time is exactly the staleness §X2 exists to catch.
- **Each rule is a checklist of independent failure modes.** If a rule has two ways to violate it, that's two boxes, not one — same reasoning as the built-in gates (see `naming.md`'s §N1–§N4 split). Give each box its own N/A condition ("N/A: no new hooks in diff") so the agent never has to guess whether silence means pass or skip.
- **Cite a real path per rule.** Every rule needs at least one canonical example file from *this* repo, not a hypothetical. That path is what the agent greps around when verifying the rule is still live (rule 3 above).
- **End with a `## Gate checklist` block**, one box per rule, in the same `- [ ] §<id> <rule text> (N/A: <condition>)` shape used throughout this plugin's reference files.
- **Numbering is the repo's own.** Use any prefix that won't collide with this plugin's sections (`§C1`, `§P1`, whatever reads naturally) — the agent doesn't care about the letter, only that each box is independently checkable.

### Worked example

A rule for a hypothetical repo that keeps all API-calling hooks under one directory with a fixed naming convention:

```markdown
## §C1. API-calling hooks live in `src/data/` and are named `useFetchX`

Any hook that calls the network layer directly belongs in `src/data/`, not
beside the component that uses it, and its name starts with `useFetchX`
where `X` is the resource. This keeps every network call greppable from one
directory instead of scattered through feature folders.

Canonical example: `src/data/useFetchWidget.ts`.

Bad — network call inlined in a component-local hook:

    // src/features/widgets/useWidgetPanel.ts
    function useWidgetPanel(id: string) {
      const [widget, setWidget] = useState(null)
      useEffect(() => { api.get(`/widgets/${id}`).then(setWidget) }, [id])
      return widget
    }

Good — call lives in `src/data/`, named per convention:

    // src/data/useFetchWidget.ts
    export function useFetchWidget(id: string) {
      return useQuery(['widget', id], () => api.get(`/widgets/${id}`))
    }

## Gate checklist

- [ ] §C1 Every new hook that calls the network layer directly lives in `src/data/` and is named `useFetchX`. (N/A: no new network-calling hooks in diff)
```

## Gate checklist

- [ ] §X1 The target repo's `.claude/review-conventions.md` was read in full and every rule in it was walked against the diff, one box per rule, with per-box evidence. (N/A: no `.claude/review-conventions.md` in the target repo — state that the file was looked for)
- [ ] §X2 Each convention cited in a finding was verified against the repo (2–3 existing examples greped and cited); stale rules were reported as possibly-stale rather than enforced or dropped. (N/A: no findings from this gate)
