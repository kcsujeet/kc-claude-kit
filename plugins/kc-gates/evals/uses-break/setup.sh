#!/usr/bin/env bash
# A shop repo whose feature branch moves formatPrice from dollars to cents and updates the cart, the
# one caller it touches. The receipt and the product card, which the branch never touches, still
# pass dollars (§B8): their prices now show a hundred times too small. parseCents, added by the
# branch, is correct and should draw no finding.
set -euo pipefail

git init -q -b main
git config user.email eval@example.com
git config user.name "Eval Fixture"
mkdir -p src/money src/cart src/orders src/catalog
cat > src/money/formatPrice.ts <<'TS'
/** Formats an amount in dollars for display: 12.5 -> "$12.50". */
export function formatPrice(amount: number): string {
  return `$${amount.toFixed(2)}`
}
TS
cat > src/cart/summary.ts <<'TS'
import { formatPrice } from '../money/formatPrice'

export interface Cart {
  total: number
}

export function cartSummary(cart: Cart): string {
  return `Total: ${formatPrice(cart.total)}`
}
TS
cat > src/orders/receipt.ts <<'TS'
import { formatPrice } from '../money/formatPrice'

export interface Order {
  id: string
  total: number
}

export function receiptLine(order: Order): string {
  return `Order ${order.id}: ${formatPrice(order.total)}`
}
TS
cat > src/catalog/productCard.ts <<'TS'
import { formatPrice } from '../money/formatPrice'

export interface Product {
  name: string
  price: number
}

export function productCard(product: Product): string {
  return `${product.name} - ${formatPrice(product.price)}`
}
TS
printf '{ "name": "shop", "type": "module", "scripts": { "test": "vitest run" } }\n' > package.json
git add -A
git commit -q -m "Format prices in the cart, receipts and product cards"

git checkout -q -b feature/cents
cat > src/money/formatPrice.ts <<'TS'
/** Formats an amount in cents for display: 1250 -> "$12.50". Cents avoid float rounding. */
export function formatPrice(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`
}
TS
cat > src/money/parseCents.ts <<'TS'
/** Parses a typed price ("12.5", "$12.50", " 3 ") into cents, or null when it is not a price. */
export function parseCents(input: string): number | null {
  const trimmed = input.trim().replace(/^\$/, '')
  if (!/^\d+(\.\d{1,2})?$/.test(trimmed)) return null
  return Math.round(Number(trimmed) * 100)
}
TS
cat > src/cart/summary.ts <<'TS'
import { formatPrice } from '../money/formatPrice'

export interface Cart {
  totalCents: number
}

export function cartSummary(cart: Cart): string {
  return `Total: ${formatPrice(cart.totalCents)}`
}
TS
git add -A
git commit -q -m "Keep cart totals in cents"
