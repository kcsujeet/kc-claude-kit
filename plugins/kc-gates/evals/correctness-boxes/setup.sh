#!/usr/bin/env bash
# A shop repo whose feature branch makes six changes, each with one correctness-rule violation a
# review should flag, and adds one unit (priceRange) that handles its edge cases, which it should
# not flag. main holds the code two of the changes edit.
set -euo pipefail

git init -q -b main
git config user.email eval@example.com
git config user.name "Eval Fixture"
mkdir -p src/customers src/catalog
cat > src/customers/types.ts <<'TS'
export interface Address {
  line1: string
  city: string
}
export interface Customer {
  id: string
  name: string
  shippingAddress: Address
}
TS
cat > src/customers/greeting.ts <<'TS'
import type { Customer } from './types'

export function greeting(customer: Customer): string {
  return `Hello, ${customer.name || 'there'}`
}
TS
cat > src/customers/label.ts <<'TS'
import type { Customer } from './types'

export function shippingLabel(customer: Customer): string {
  return `${customer.name}\n${customer.shippingAddress.line1}\n${customer.shippingAddress.city}`
}
TS
cat > src/catalog/types.ts <<'TS'
export interface Product {
  id: string
  name: string
  price: number
  archived: boolean
  ratings: number[]
}
export interface Order {
  id: string
  productId: string
  status: 'open' | 'shipped' | 'cancelled' | 'refunded'
}
TS
printf '{ "name": "shop", "type": "module", "scripts": { "test": "vitest run" } }\n' > package.json
git add -A
git commit -q -m "Add customers and catalog"

git checkout -q -b feature/catalog-and-addresses

# §B15: `||` changed to `??`, so a saved empty name now greets "Hello, ".
sed -i.bak "s/customer.name || 'there'/customer.name ?? 'there'/" src/customers/greeting.ts && rm src/customers/greeting.ts.bak

# §B13: one shipping address becomes many; the label still picks "the" first one.
cat > src/customers/types.ts <<'TS'
export interface Address {
  line1: string
  city: string
  isDefault: boolean
}
export interface Customer {
  id: string
  name: string
  addresses: Address[]
}
TS
cat > src/customers/label.ts <<'TS'
import type { Customer } from './types'

export function shippingLabel(customer: Customer): string {
  const address = customer.addresses[0]
  return `${customer.name}\n${address.line1}\n${address.city}`
}
TS

# §B1: off-by-one past the end of the list.
cat > src/catalog/totals.ts <<'TS'
import type { Product } from './types'

export function cartTotal(products: Product[]): number {
  let total = 0
  for (let index = 0; index <= products.length; index++) {
    total += products[index].price
  }
  return total
}
TS

# §B2: an average over an empty list divides by zero.
cat > src/catalog/rating.ts <<'TS'
import type { Product } from './types'

export function averageRating(product: Product): number {
  const sum = product.ratings.reduce((total, rating) => total + rating, 0)
  return sum / product.ratings.length
}
TS

# §B7: the count drops archived products; the list it summarises leaves them out.
cat > src/catalog/listing.ts <<'TS'
import type { Product } from './types'

export function visibleProducts(products: Product[]): Product[] {
  return products.filter((product) => !product.archived)
}

export function visibleProductCount(products: Product[]): number {
  return products.length
}
TS

# §B14: a delete guard that cancelled and refunded orders also block.
cat > src/catalog/removeProduct.ts <<'TS'
import type { Order, Product } from './types'

export function removeProduct(products: Product[], orders: Order[], productId: string): Product[] {
  const hasOrders = orders.some((order) => order.productId === productId)
  if (hasOrders) throw new Error('This product has open orders and cannot be removed')
  return products.filter((product) => product.id !== productId)
}
TS

# §B16: a saved cart read back without its missing or older states.
cat > src/catalog/savedCart.ts <<'TS'
export interface SavedCart {
  productIds: string[]
  savedAt: string
}

export function loadSavedCart(storage: Storage): SavedCart {
  return JSON.parse(storage.getItem('cart') as string) as SavedCart
}
TS

# Clean: a price range that handles an empty catalog and a single product.
cat > src/catalog/priceRange.ts <<'TS'
import type { Product } from './types'

export function priceRange(products: Product[]): { lowest: number; highest: number } | null {
  if (products.length === 0) return null
  const prices = products.map((product) => product.price)
  return { lowest: Math.min(...prices), highest: Math.max(...prices) }
}
TS
git add -A
git commit -q -m "Add catalog totals, ratings, listing, removal and saved carts; several addresses per customer"
