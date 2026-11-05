#!/usr/bin/env bash
# A shop repo whose feature branch adds six units, each with one testing-rule violation a review
# should flag, and one unit (memberPrice) tested the way the rules ask, which it should not flag.
set -euo pipefail

git init -q -b main
git config user.email eval@example.com
git config user.name "Eval Fixture"
mkdir -p src
cat > src/types.ts <<'TS'
export interface Coupon {
  code: string
  percentOff: number
  expiresAt: Date
}
export interface Cart {
  subtotal: number
  isMember: boolean
}
TS
printf '{ "name": "shop", "type": "module", "scripts": { "test": "vitest run" } }\n' > package.json
git add -A
git commit -q -m "Add cart and coupon types"

git checkout -q -b feature/coupons
mkdir -p src/coupons src/badges src/shipping src/loyalty src/pricing tests/misc

# §T1: a new branch (an unknown code) that no test reaches.
cat > src/coupons/redeem.ts <<'TS'
import type { Cart, Coupon } from '../types'

export function redeem(cart: Cart, code: string, coupons: Coupon[]): number {
  const coupon = coupons.find((candidate) => candidate.code === code)
  if (!coupon) throw new Error(`Unknown coupon ${code}`)
  return cart.subtotal * (1 - coupon.percentOff / 100)
}
TS
cat > src/coupons/redeem.test.ts <<'TS'
import { expect, it } from 'vitest'
import { redeem } from './redeem'

it('takes the coupon percentage off the subtotal', () => {
  const coupons = [{ code: 'SPRING', percentOff: 20, expiresAt: new Date('2030-01-01') }]
  expect(redeem({ subtotal: 50, isMember: false }, 'SPRING', coupons)).toBe(40)
})
TS

# §T2: a state checked through a class name.
cat > src/badges/stockBadge.ts <<'TS'
export function renderStockBadge(stock: number): HTMLElement {
  const badge = document.createElement('span')
  badge.className = stock === 0 ? 'badge badge--sold-out' : 'badge'
  badge.textContent = stock === 0 ? 'Sold out' : `${stock} left`
  return badge
}
TS
cat > src/badges/stockBadge.test.ts <<'TS'
import { expect, it } from 'vitest'
import { renderStockBadge } from './stockBadge'

it('shows a sold-out badge when nothing is left', () => {
  expect(renderStockBadge(0).className).toContain('badge--sold-out')
})
TS

# §T3: a gate (free shipping for members) tested only with the condition met.
cat > src/shipping/shippingFee.ts <<'TS'
import type { Cart } from '../types'

export function shippingFee(cart: Cart): number {
  if (cart.isMember) return 0
  return 7
}
TS
cat > src/shipping/shippingFee.test.ts <<'TS'
import { expect, it } from 'vitest'
import { shippingFee } from './shippingFee'

it('ships free for members', () => {
  expect(shippingFee({ subtotal: 30, isMember: true })).toBe(0)
})
TS

# §T6: a bound where the value is known.
cat > src/loyalty/points.ts <<'TS'
export function pointsFor(subtotal: number): number {
  return Math.floor(subtotal / 10)
}
TS
cat > src/loyalty/points.test.ts <<'TS'
import { expect, it } from 'vitest'
import { pointsFor } from './points'

it('earns a point per ten spent', () => {
  expect(pointsFor(45)).toBeGreaterThan(0)
})
TS

# §T10: the code compares against now; the test doesn't freeze the clock.
cat > src/coupons/isExpired.ts <<'TS'
import type { Coupon } from '../types'

export function isExpired(coupon: Coupon): boolean {
  return coupon.expiresAt.getTime() < Date.now()
}
TS
cat > src/coupons/isExpired.test.ts <<'TS'
import { expect, it } from 'vitest'
import { isExpired } from './isExpired'

it('treats a coupon past its date as expired', () => {
  expect(isExpired({ code: 'OLD', percentOff: 10, expiresAt: new Date('2026-11-01') })).toBe(true)
})
TS

# §T5: a test filed away from its unit under an unrelated name.
cat > src/pricing/roundPrice.ts <<'TS'
export function roundPrice(amount: number): number {
  return Math.round(amount * 100) / 100
}
TS
cat > tests/misc/helpers.test.ts <<'TS'
import { expect, it } from 'vitest'
import { roundPrice } from '../../src/pricing/roundPrice'

it('rounds to cents', () => {
  expect(roundPrice(19.999)).toBe(20)
})
TS

# Clean: a member discount tested on both sides of its gate, with exact values, beside its unit.
cat > src/pricing/memberPrice.ts <<'TS'
import type { Cart } from '../types'

const MEMBER_DISCOUNT_PERCENT = 10

export function memberPrice(cart: Cart): number {
  if (!cart.isMember) return cart.subtotal
  return cart.subtotal * (1 - MEMBER_DISCOUNT_PERCENT / 100)
}
TS
cat > src/pricing/memberPrice.test.ts <<'TS'
import { expect, it } from 'vitest'
import { memberPrice } from './memberPrice'

it('takes ten percent off for members', () => {
  expect(memberPrice({ subtotal: 50, isMember: true })).toBe(45)
})

it('charges the full subtotal to everyone else', () => {
  expect(memberPrice({ subtotal: 50, isMember: false })).toBe(50)
})
TS
git add -A
git commit -q -m "Add coupons, badges, shipping, loyalty and pricing"
