# Plan template

Any model can write this. `/autopilot:run` refuses a plan that breaks a rule below and says which.

```markdown
# <Plan title>

## Goal
One paragraph: what changes for whom, and why.

## Acceptance criteria
1. <A testable statement. Name the observable result: what the user sees, what is stored, what the API returns.>
2. <…>

## Work units
### U1: <title>
- Depends on: none
- Covers: AC1, AC2
<Scope: what this unit changes, in a few sentences. Each unit becomes one PR.>

### U2: <title>
- Depends on: U1
- Covers: AC3

## Out of scope
- <Things the agents must not do.>

## Notes
<Optional: links, constraints, prior decisions.>
```

Rules:
- Criteria are numbered `1.`, `2.` …; they become `AC1`, `AC2` ….
- Units are `### U<n>: <title>`, numbered from 1 in order.
- `Depends on:` is `none` or earlier units only (`U1, U2`). Dependent units become stacked PRs. Stacks are linear, so with several dependencies one of them must depend (directly or through others) on all the rest; the unit stacks on that one.
- `Covers:` lists criteria; every criterion is covered by at least one unit.
- `## Goal`, `## Acceptance criteria`, `## Work units` and `## Out of scope` are required.
