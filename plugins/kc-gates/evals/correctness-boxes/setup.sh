#!/usr/bin/env bash
# A shop repo whose feature branch makes ten changes (four of them for §B4, §B17, §B2 and §B18), each with one correctness-rule violation a
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
mkdir -p src/notifications src/team src/imports
cat > src/catalog/tax.ts <<'TS'
/** Tax owed on an order's line totals, in cents. */
export function getTax(lineTotalsCents: number[], ratePercent: number): number {
  const total = lineTotalsCents.reduce((sum, cents) => sum + cents, 0)
  return Math.round((total * ratePercent) / 100)
}
TS
cat > src/notifications/signature.ts <<'TS'
export interface NotificationSettings {
  shopName: string
  signature: string
}

/** The sign-off on order emails: the shop's own text, or the shop's name when it is left blank. */
export function getSignature(settings: NotificationSettings): string {
  return settings.signature.trim() || settings.shopName
}
TS
cat > src/team/users.ts <<'TS'
export interface TeamUser {
  id: string
  name: string
  deactivatedAt: string | null
}

/** Who an order can be assigned to: deactivated users are left out. */
export function getAssignableUsers(users: TeamUser[]): TeamUser[] {
  return users.filter((user) => user.deactivatedAt === null)
}
TS
cat > src/imports/baseImporter.ts <<'TS'
export interface ImportRow {
  sku: string
  name: string
}

export class BaseImporter {
  importRows(rows: ImportRow[]): ImportRow[] {
    return rows.map((row) => {
      this.beforeSave(row)
      return this.save(row)
    })
  }

  protected beforeSave(_row: ImportRow): void {}

  protected save(row: ImportRow): ImportRow {
    return row
  }
}
TS
cat > src/imports/productImporter.ts <<'TS'
import { BaseImporter } from './baseImporter'
import type { ImportRow } from './baseImporter'

export class ProductImporter extends BaseImporter {
  protected beforeSave(row: ImportRow): void {
    if (!row.sku) throw new Error('Every imported product needs a SKU')
  }
}
TS
printf '{ "name": "shop", "type": "module", "scripts": { "test": "vitest run" } }\n' > package.json
git add -A
git commit -q -m "Add customers and catalog"

git checkout -q -b feature/catalog-and-addresses

# §B4: main fixes tax rounding after this branch was cut; the branch edits the same file, and its
# merge of main keeps the branch's copy of the file, so the fix is gone while the merge ran clean.
git checkout -q main
cat > src/catalog/tax.ts <<'TS'
/** Tax owed on an order's line totals, in cents. */
export function getTax(lineTotalsCents: number[], ratePercent: number): number {
  // Round per line, as the invoice shows each line's tax.
  return lineTotalsCents.reduce((sum, cents) => sum + Math.round((cents * ratePercent) / 100), 0)
}
TS
git commit -q -am "Round tax per line item"
git checkout -q feature/catalog-and-addresses
cat > src/catalog/tax.ts <<'TS'
/** Tax owed on an order's line totals, in cents; an exempt customer owes none. */
export function getTax(lineTotalsCents: number[], ratePercent: number, exempt = false): number {
  if (exempt) return 0
  const total = lineTotalsCents.reduce((sum, cents) => sum + cents, 0)
  return Math.round((total * ratePercent) / 100)
}
TS
git commit -q -am "Add tax exemptions"
git merge --no-commit --no-ff main > /dev/null 2>&1 || true
git checkout HEAD -- src/catalog/tax.ts
git commit -q -m "Merge main into feature/catalog-and-addresses"

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

# §B17: a new reply-to name with no fallback on blank, while the signature beside it falls back to
# the shop's name.
cat > src/notifications/replyToName.ts <<'TS'
import type { NotificationSettings } from './signature'

export function getReplyToName(settings: NotificationSettings & { replyToName: string }): string {
  return settings.replyToName
}
TS

# §B2: a new team directory and count over every user, deactivated ones included.
cat > src/team/teamList.ts <<'TS'
import type { TeamUser } from './users'

export function getTeamNames(users: TeamUser[]): string[] {
  return users.map((user) => user.name)
}

export function getTeamSize(users: TeamUser[]): number {
  return users.length
}
TS

# §B18: the override loops in batches and no longer calls super.importRows, so the base class never
# calls beforeSave and the SKU check silently stops running; nothing in the diff mentions it.
cat > src/imports/productImporter.ts <<'TS'
import { BaseImporter } from './baseImporter'
import type { ImportRow } from './baseImporter'

const BATCH_SIZE = 100

export class ProductImporter extends BaseImporter {
  importRows(rows: ImportRow[]): ImportRow[] {
    const saved: ImportRow[] = []
    for (let start = 0; start < rows.length; start += BATCH_SIZE) {
      saved.push(...rows.slice(start, start + BATCH_SIZE).map((row) => this.save(row)))
    }
    return saved
  }

  protected beforeSave(row: ImportRow): void {
    if (!row.sku) throw new Error('Every imported product needs a SKU')
  }
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
