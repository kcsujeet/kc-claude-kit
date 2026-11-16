#!/usr/bin/env bash
# A shop repo whose feature branch moves two catalog entries from the beta category to the addon
# category. Four tests in untouched files (grant, notify, summary, csv) still build them as beta
# (they pass either way, the category is incidental there), and the new catalog test
# dereferences a lookup that can come back empty.
set -euo pipefail

git init -q -b main
git config user.email eval@example.com
git config user.name "Eval Fixture"
mkdir -p src/features src/accounts
cat > src/features/catalog.ts <<'TS'
export type FeatureCategory = 'core' | 'beta' | 'addon'

export interface FeatureEntry {
  key: string
  category: FeatureCategory
}

export const catalog: FeatureEntry[] = [
  { key: 'wishlist', category: 'core' },
  { key: 'preview-mode', category: 'beta' },
  { key: 'gift-wrap', category: 'beta' },
  { key: 'bulk-orders', category: 'beta' },
]
TS
cat > src/accounts/grant.ts <<'TS'
import type { FeatureEntry } from '../features/catalog'

export interface Account {
  id: string
  features: string[]
}

export function grantFeature(account: Account, entry: FeatureEntry): Account {
  return { ...account, features: [...account.features, entry.key] }
}
TS
cat > src/accounts/grant.test.ts <<'TS'
import { expect, it } from 'vitest'
import { grantFeature } from './grant'

it('adds the granted feature to the account', () => {
  const entry = { key: 'gift-wrap', category: 'beta' as const }
  expect(grantFeature({ id: 'a1', features: ['wishlist'] }, entry).features).toEqual([
    'wishlist',
    'gift-wrap',
  ])
})
TS
mkdir -p src/notifications src/reports src/exports
cat > src/notifications/notify.ts <<'TS'
import type { FeatureEntry } from '../features/catalog'

export function launchMessage(entry: FeatureEntry): string {
  return `${entry.key} is now available`
}
TS
cat > src/notifications/notify.test.ts <<'TS'
import { expect, it } from 'vitest'
import { launchMessage } from './notify'

it('announces the feature by its key', () => {
  expect(launchMessage({ key: 'bulk-orders', category: 'beta' })).toBe('bulk-orders is now available')
})
TS
cat > src/reports/summary.ts <<'TS'
import type { FeatureEntry } from '../features/catalog'

export function featureCount(entries: FeatureEntry[]): number {
  return new Set(entries.map((entry) => entry.key)).size
}
TS
cat > src/reports/summary.test.ts <<'TS'
import { expect, it } from 'vitest'
import { featureCount } from './summary'

it('counts each feature once', () => {
  const entries = [
    { key: 'gift-wrap', category: 'beta' as const },
    { key: 'gift-wrap', category: 'beta' as const },
    { key: 'wishlist', category: 'core' as const },
  ]
  expect(featureCount(entries)).toBe(2)
})
TS
cat > src/exports/csv.ts <<'TS'
import type { FeatureEntry } from '../features/catalog'

export function toCsv(entries: FeatureEntry[]): string {
  return entries.map((entry) => `${entry.key},${entry.category}`).join('\n')
}
TS
cat > src/exports/csv.test.ts <<'TS'
import { expect, it } from 'vitest'
import { toCsv } from './csv'

it('writes one line per entry', () => {
  expect(toCsv([{ key: 'wishlist', category: 'core' }, { key: 'bulk-orders', category: 'beta' }])).toBe(
    'wishlist,core\nbulk-orders,beta',
  )
})
TS
printf '{ "name": "shop", "type": "module", "scripts": { "test": "vitest run" } }\n' > package.json
git add -A
git commit -q -m "Add feature catalog, grants and invoice lines"

git checkout -q -b feature/addon-category

# gift-wrap and bulk-orders move from beta to addon. The four tests above still build them as
# beta entries, and the new catalog test dereferences a lookup that returns undefined for a
# missing key.
cat > src/features/catalog.ts <<'TS'
export type FeatureCategory = 'core' | 'beta' | 'addon'

export interface FeatureEntry {
  key: string
  category: FeatureCategory
}

export const catalog: FeatureEntry[] = [
  { key: 'wishlist', category: 'core' },
  { key: 'preview-mode', category: 'beta' },
  { key: 'gift-wrap', category: 'addon' },
  { key: 'bulk-orders', category: 'addon' },
]
TS
cat > src/features/catalog.test.ts <<'TS'
import { expect, it } from 'vitest'
import { catalog } from './catalog'

it('sells gift-wrap and bulk-orders as add-ons', () => {
  for (const key of ['gift-wrap', 'bulk-orders']) {
    expect(catalog.find((entry) => entry.key === key)!.category).toBe('addon')
  }
})
TS
git add -A
git commit -q -m "Move gift-wrap and bulk-orders to the addon category"
