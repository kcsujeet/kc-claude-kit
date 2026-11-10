#!/usr/bin/env bash
# A shop repo whose feature branch makes eight changes, each with one correctness-rule violation a
# review should flag, and adds one unit (priceRange) that handles its edge cases, which it should
# not flag. main holds the code two of the changes edit.
set -euo pipefail

git init -q -b main
git config user.email eval@example.com
git config user.name "Eval Fixture"
mkdir -p src/customers src/catalog src/reminders src/shops
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
cat > src/reminders/types.ts <<'TS'
export interface User {
  id: string
  active: boolean
  emailConnected: boolean
}
export interface Reminder {
  id: string
  senderUserId: string
  sendAt: Date
  body: string
}
TS
cat > src/reminders/dueReminders.ts <<'TS'
import type { Reminder, User } from './types'

/** The reminders the scheduler sends now: due, and from a sender who can still send. */
export function dueReminders(reminders: Reminder[], users: Map<string, User>, now: Date): Reminder[] {
  return reminders.filter((reminder) => {
    const sender = users.get(reminder.senderUserId)
    return reminder.sendAt <= now && sender?.active === true && sender.emailConnected
  })
}
TS
cat > src/shops/types.ts <<'TS'
export interface Shop {
  id: string
  slug: string
  features: Record<string, boolean>
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

# §B17: reminders can now be sent from a store's own address, but the scheduler still
# requires the writer's own active account and connected email, so store reminders from a writer
# without one never go out.
cat > src/reminders/types.ts <<'TS'
export interface User {
  id: string
  active: boolean
  emailConnected: boolean
}
export interface Store {
  id: string
  emailAddress: string
}
export interface Reminder {
  id: string
  senderUserId: string
  /** Set when the reminder goes out from the store's address instead of the writer's own. */
  storeId?: string
  sendAt: Date
  body: string
}
TS
cat > src/reminders/scheduleStoreReminder.ts <<'TS'
import type { Reminder, Store, User } from './types'

/** Schedules a reminder sent from the store's address on behalf of the user who wrote it. */
export function scheduleStoreReminder(author: User, store: Store, body: string, sendAt: Date): Reminder {
  return { id: crypto.randomUUID(), senderUserId: author.id, storeId: store.id, sendAt, body }
}
TS

# §B18: a custom storefront domain behind a feature flag; the settings page checks the flag, the
# link builder used by order emails reads the saved domain whatever the flag says.
cat > src/shops/types.ts <<'TS'
export interface Shop {
  id: string
  slug: string
  features: Record<string, boolean>
  customDomain?: string
}
TS
cat > src/shops/customDomainSettings.ts <<'TS'
import type { Shop } from './types'

/** Whether the shop's settings page offers a custom storefront domain. */
export function canUseCustomDomain(shop: Shop): boolean {
  return shop.features.customDomains === true
}
TS
cat > src/shops/links.ts <<'TS'
import type { Shop } from './types'

/** The storefront address order emails link to. */
export function storefrontUrl(shop: Shop): string {
  return shop.customDomain ? `https://${shop.customDomain}` : `https://shops.example.com/${shop.slug}`
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
