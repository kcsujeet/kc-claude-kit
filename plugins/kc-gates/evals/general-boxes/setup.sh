#!/usr/bin/env bash
# A shop repo whose feature branch seeds one realistic violation per file for the gates every
# review runs (naming, clarity, structure, simplicity; §N4 and §S14 included), and adds one unit (orderStatusLabel)
# written the way their rules ask, which the review should not flag. main holds the money
# formatter one of the files duplicates.
set -euo pipefail

git init -q -b main
git config user.email eval@example.com
git config user.name "Eval Fixture"
mkdir -p src/money src/orders
cat > src/money/formatMoney.ts <<'TS'
/** Formats an amount in cents as dollars with two decimals, e.g. 1999 -> "$19.99". */
export function formatMoney(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`
}
TS
cat > src/orders/types.ts <<'TS'
export type OrderStatus = 'open' | 'shipped' | 'cancelled'
export interface Order {
  id: string
  status: OrderStatus
  totalCents: number
  carrier: 'ups' | 'fedex' | 'usps'
  customerEmail: string
}
TS
cat > src/orders/orderReport.ts <<'TS'
import type { Order } from './types'

/** One line per order for the daily operations email. */
export function buildOrderReport(orders: Order[]): string[] {
  return orders.map((order) => `${order.id}: ${order.status}`)
}
TS
# The order schema owns every validation rule for an order's fields; the form only calls it.
cat > src/orders/orderSchema.ts <<'TS'
export interface OrderInput {
  quantity: number
  note: string
}

/** Every validation rule for an order's fields; forms call this and show what it returns. */
export function validateOrderInput(input: OrderInput): string[] {
  const errors: string[] = []
  if (!Number.isInteger(input.quantity) || input.quantity < 1) errors.push('Quantity must be at least 1')
  if (input.quantity > 99) errors.push('Quantity must be at most 99')
  if (input.note.length > 200) errors.push('Note must be at most 200 characters')
  return errors
}
TS
cat > src/orders/orderForm.ts <<'TS'
import { validateOrderInput } from './orderSchema'
import type { OrderInput } from './orderSchema'

export function submitOrderForm(input: OrderInput, save: (input: OrderInput) => void): string[] {
  const errors = validateOrderInput(input)
  if (errors.length === 0) save(input)
  return errors
}
TS
printf '{ "name": "shop", "type": "module" }\n' > package.json
git add -A
git commit -q -m "Add money formatter, order types and the order report"

git checkout -q -b feature/order-tools
mkdir -p src/invoices src/shipping src/notifications src/catalog

# naming §N1: a type word for a role.
cat > src/orders/openOrders.ts <<'TS'
import type { Order } from './types'

export function getOpenOrders(orders: Order[]): Order[] {
  const data = orders.filter((order) => order.status === 'open')
  return data
}
TS

# naming §N6: a function named like a value.
cat > src/notifications/customerEmails.ts <<'TS'
import type { Order } from '../orders/types'

export function customerEmails(orders: Order[]): string[] {
  return [...new Set(orders.map((order) => order.customerEmail))]
}
TS

# clarity §C15: a nested ternary.
cat > src/orders/badgeTone.ts <<'TS'
import type { Order } from './types'

export function getBadgeTone(order: Order): string {
  return order.status === 'open' ? 'blue' : order.status === 'shipped' ? 'green' : 'grey'
}
TS

# clarity §C16: a bare timeout.
cat > src/notifications/retrySend.ts <<'TS'
export function scheduleRetry(send: () => void): void {
  setTimeout(send, 30000)
}
TS

# clarity §C17: a cast that asserts a shape the value doesn't have.
cat > src/orders/parseOrder.ts <<'TS'
import type { Order } from './types'

export function parseOrder(body: string): Order {
  return JSON.parse(body) as unknown as Order
}
TS

# structure §S5: a switch that selects a value.
cat > src/shipping/carrierName.ts <<'TS'
import type { Order } from '../orders/types'

export function getCarrierName(order: Order): string {
  switch (order.carrier) {
    case 'ups':
      return 'UPS'
    case 'fedex':
      return 'FedEx'
    default:
      return 'USPS'
  }
}
TS

# structure §S8: a default export.
cat > src/catalog/formatSku.ts <<'TS'
export default function formatSku(sku: string): string {
  return sku.trim().toUpperCase()
}
TS

# simplicity §P1: re-implements the money formatter main already has.
cat > src/invoices/invoiceTotal.ts <<'TS'
import type { Order } from '../orders/types'

export function getInvoiceTotal(order: Order): string {
  return `$${(order.totalCents / 100).toFixed(2)}`
}
TS

# simplicity §P2: a parameter nothing reads.
cat > src/shipping/shipOrder.ts <<'TS'
import type { Order } from '../orders/types'

export function shipOrder(order: Order, options: { express: boolean }): Order {
  return { ...order, status: 'shipped' }
}
TS

# structure §S14: a new rule (every line item must be in a pack of 6) added to the form, when the
# schema already owns every other rule for the quantity field and the form only calls it.
cat > src/orders/orderForm.ts <<'TS'
import { validateOrderInput } from './orderSchema'
import type { OrderInput } from './orderSchema'

export function submitOrderForm(input: OrderInput, save: (input: OrderInput) => void): string[] {
  const errors = validateOrderInput(input)
  if (input.quantity % 6 !== 0) errors.push('Quantity must be a multiple of 6')
  if (errors.length === 0) save(input)
  return errors
}
TS

# naming §N4: a qualifier that repeats the context the name already sits in (a footer-only model).
cat > src/notifications/storeFooter.ts <<'TS'
export interface StoreFooter {
  footerEmail: string
  footerPhone: string
}

export function renderStoreFooter(footer: StoreFooter): string {
  return `Questions? ${footer.footerEmail} or ${footer.footerPhone}`
}
TS

# Clean: a lookup object keyed by the domain type, exported by name and read directly.
cat > src/orders/orderStatusLabel.ts <<'TS'
import type { OrderStatus } from './types'

/** What each order status reads as in staff-facing lists. */
export const ORDER_STATUS_LABELS: Record<OrderStatus, string> = {
  open: 'Open',
  shipped: 'Shipped',
  cancelled: 'Cancelled',
}
TS
# The report now lists open orders with readable labels and the customers to contact.
cat > src/orders/orderReport.ts <<'TS'
import { customerEmails } from '../notifications/customerEmails'
import { getOpenOrders } from './openOrders'
import { ORDER_STATUS_LABELS } from './orderStatusLabel'
import type { Order } from './types'

/** One line per open order for the daily operations email, then the customers to contact. */
export function buildOrderReport(orders: Order[]): string[] {
  const openOrderLines = getOpenOrders(orders).map((order) => `${order.id}: ${ORDER_STATUS_LABELS[order.status]}`)
  return [...openOrderLines, `Customers: ${customerEmails(orders).join(', ')}`]
}
TS
git add -A
git commit -q -m "Add order, shipping, notification, invoice and catalog helpers"
