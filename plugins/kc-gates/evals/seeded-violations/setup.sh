#!/usr/bin/env bash
# Builds a repo whose feature branch adds three clear convention violations:
# a nested ternary, an `as any` cast, and a predicate named as a noun.
set -euo pipefail

git init -q -b main
git config user.email eval@example.com
git config user.name "Eval Fixture"

mkdir -p src
cat > src/widget.ts <<'TS'
export type WidgetStatus = 'draft' | 'active' | 'archived'

export interface Widget {
  id: string
  ownerId: string
  status: WidgetStatus
  price: number
}
TS
cat > README.md <<'MD'
# widgets

Small widget helpers.
MD
git add -A
git commit -q -m "Add widget type"

git checkout -q -b feature/widget-helpers
cat > src/widget-helpers.ts <<'TS'
import type { Widget } from './widget'

export function ownerMatch(first: Widget, second: Widget): boolean {
  return first.ownerId === second.ownerId
}

export function describeWidget(widget: Widget): string {
  const label = widget.status === 'draft' ? 'Draft' : widget.status === 'active' ? 'Live' : 'Archived'
  const payload = JSON.parse(JSON.stringify(widget)) as any
  return `${label}: ${payload.price}`
}
TS
git add -A
git commit -q -m "Add widget helpers"
