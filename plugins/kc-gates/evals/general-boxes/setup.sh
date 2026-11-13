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
  placedAt: string
}
TS
cat > src/orders/orderReport.ts <<'TS'
import type { Order } from './types'

/** One line per order for the daily operations email. */
export function buildOrderReport(orders: Order[]): string[] {
  return orders.map((order) => `${order.id}: ${order.status}`)
}
TS
# The cancellation module owns every rule for whether an order can be cancelled; the handler only
# asks it and answers the request.
cat > src/orders/cancellation.ts <<'TS'
import type { Order } from './types'

/** Every rule for whether a customer may cancel an order. */
export function canCancelOrder(order: Order): boolean {
  return order.status === 'open'
}
TS
cat > src/orders/cancelOrderHandler.ts <<'TS'
import { canCancelOrder } from './cancellation'
import type { Order } from './types'

export function handleCancelOrder(order: Order): { status: number; message: string } {
  if (!canCancelOrder(order)) return { status: 409, message: 'This order can no longer be cancelled' }
  return { status: 200, message: 'Order cancelled' }
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

# structure §S14: a new rule (orders can only be cancelled within 30 minutes) written into the
# handler that calls the cancellation module, which owns every other cancellation rule.
cat > src/orders/cancelOrderHandler.ts <<'TS'
import { canCancelOrder } from './cancellation'
import type { Order } from './types'

const CANCEL_WINDOW_MINUTES = 30

export function handleCancelOrder(order: Order, now: Date): { status: number; message: string } {
  if (!canCancelOrder(order)) return { status: 409, message: 'This order can no longer be cancelled' }
  const minutesSincePlaced = (now.getTime() - new Date(order.placedAt).getTime()) / 60000
  if (minutesSincePlaced > CANCEL_WINDOW_MINUTES) {
    return { status: 409, message: 'Orders can only be cancelled within 30 minutes of placing them' }
  }
  return { status: 200, message: 'Order cancelled' }
}
TS

# naming §N4: the props of a customer card, each prefixed with the customer the card is already about.
cat > src/notifications/customerCard.ts <<'TS'
export interface CustomerCardProps {
  customerName: string
  customerEmail: string
}

export function renderCustomerCard(props: CustomerCardProps): string {
  return `${props.customerName} <${props.customerEmail}>`
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
