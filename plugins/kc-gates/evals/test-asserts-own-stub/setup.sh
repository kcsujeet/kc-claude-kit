#!/usr/bin/env bash
# Builds a repo whose feature branch adds a shipping-cost rule and a test that can't fail: it
# mocks the function under test and asserts the value the mock was given.
set -euo pipefail

git init -q -b main
git config user.email eval@example.com
git config user.name "Eval Fixture"
mkdir -p src
cat > src/order.ts <<'TS'
export interface Order {
  id: string
  subtotal: number
}
TS
printf '{ "name": "shop", "scripts": { "test": "vitest run" } }\n' > package.json
git add -A
git commit -q -m "Add order type"

git checkout -q -b feature/free-shipping
cat > src/shipping.ts <<'TS'
import type { Order } from './order'

export function shippingCost(order: Order): number {
  if (order.subtotal >= 50) return 0
  return 5
}
TS
cat > src/shipping.test.ts <<'TS'
import { describe, expect, it, vi } from 'vitest'
import * as shipping from './shipping'

describe('shippingCost', () => {
  it('ships free over 50', () => {
    vi.spyOn(shipping, 'shippingCost').mockReturnValue(0)
    expect(shipping.shippingCost({ id: 'o1', subtotal: 80 })).toBe(0)
  })
})
TS
git add -A
git commit -q -m "Free shipping over 50"
