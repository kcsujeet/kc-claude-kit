#!/usr/bin/env bash
# A React 19 shop repo whose feature branch seeds one realistic React-rule violation per
# component, and adds one component (OrderTotal) written the way the rules ask, which the review
# should not flag. main holds the order types and the read hook the components should use.
set -euo pipefail

git init -q -b main
git config user.email eval@example.com
git config user.name "Eval Fixture"
mkdir -p src/orders src/analytics
cat > package.json <<'JSON'
{
  "name": "shop",
  "type": "module",
  "dependencies": { "react": "^19.1.0", "react-dom": "^19.1.0", "@tanstack/react-query": "^5.59.0" }
}
JSON
cat > src/orders/types.ts <<'TS'
export interface OrderLine {
  sku: string
  name: string
  quantity: number
}
export interface Order {
  id: string
  totalCents: number
  lines: OrderLine[]
}
TS
cat > src/orders/useOrders.ts <<'TS'
import { useQuery } from '@tanstack/react-query'
import type { Order } from './types'

/** Reads the signed-in customer's orders. */
export function useOrders() {
  return useQuery({
    queryKey: ['orders'],
    queryFn: async (): Promise<Order[]> => (await fetch('/api/orders')).json(),
  })
}
TS
cat > src/analytics/track.ts <<'TS'
/** Sends one analytics event. */
export function track(event: string, properties: Record<string, string> = {}): void {
  navigator.sendBeacon('/api/events', JSON.stringify({ event, properties }))
}
TS
git add -A
git commit -q -m "Add order types, orders hook and analytics"

git checkout -q -b feature/order-screens

# §R3: an index key on lines the customer can reorder.
cat > src/orders/OrderLineList.tsx <<'TSX'
import type { OrderLine } from './types'

interface OrderLineListProps {
  lines: OrderLine[]
  onMoveUp: (sku: string) => void
}

export function OrderLineList({ lines, onMoveUp }: OrderLineListProps) {
  return (
    <ul>
      {lines.map((line, index) => (
        <li key={index}>
          {line.name} x {line.quantity}
          <button type="button" onClick={() => onMoveUp(line.sku)}>Move up</button>
        </li>
      ))}
    </ul>
  )
}
TSX

# §R10: a component that exists only for its effect.
cat > src/analytics/TrackOrdersView.tsx <<'TSX'
import { useEffect } from 'react'
import { track } from './track'

export function TrackOrdersView() {
  useEffect(() => {
    track('orders_viewed')
  }, [])
  return null
}
TSX

# §R11: a raw fetch inside a component, beside the read hook that already exists.
cat > src/orders/RecentOrders.tsx <<'TSX'
import { useEffect, useState } from 'react'
import type { Order } from './types'

export function RecentOrders() {
  const [orders, setOrders] = useState<Order[]>([])
  useEffect(() => {
    fetch('/api/orders')
      .then((response) => response.json())
      .then(setOrders)
  }, [])
  return <p>{orders.length} recent orders</p>
}
TSX

# §R16: a memo with nothing to compute.
cat > src/orders/OrdersHeading.tsx <<'TSX'
import { useMemo } from 'react'

export function OrdersHeading() {
  const heading = useMemo(() => 'Your orders', [])
  return <h1>{heading}</h1>
}
TSX

# §R20: forwardRef on React 19.
cat > src/orders/OrderSearchInput.tsx <<'TSX'
import { forwardRef } from 'react'

export const OrderSearchInput = forwardRef<HTMLInputElement, { placeholder: string }>(
  function OrderSearchInput({ placeholder }, ref) {
    return <input ref={ref} type="search" placeholder={placeholder} />
  },
)
TSX

# Clean: a small presentational component with a named export and a typed prop.
cat > src/orders/OrderTotal.tsx <<'TSX'
import type { Order } from './types'

interface OrderTotalProps {
  order: Order
}

/** Shows an order's total in dollars. */
export function OrderTotal({ order }: OrderTotalProps) {
  return <p>Total: ${(order.totalCents / 100).toFixed(2)}</p>
}
TSX
git add -A
git commit -q -m "Add order screens and order view tracking"
