#!/usr/bin/env bash
# Builds a repo whose feature branch shows an order's carrier in two places. Both read one carrier
# list, which comes back empty with isError set when it fails to load. The badge handles that; the
# edit field handles only loading, so on a failed load it names a working carrier "Carrier removed".
set -euo pipefail

git init -q -b main
git config user.email eval@example.com
git config user.name "Eval Fixture"
mkdir -p src/orders
cat > src/orders/types.ts <<'TS'
export interface Carrier {
  id: string
  name: string
}
export interface Order {
  id: string
  carrierId: string | null
}
TS
cat > src/orders/carriers.ts <<'TS'
import type { Carrier } from './types'

export interface CarrierList {
  carriers: Carrier[]
  isLoading: boolean
  isError: boolean
}

/** The organization's carriers. While loading, and when the request fails, the list is empty. */
export async function loadCarriers(fetchCarriers: () => Promise<Carrier[]>): Promise<CarrierList> {
  try {
    return { carriers: await fetchCarriers(), isLoading: false, isError: false }
  } catch {
    return { carriers: [], isLoading: false, isError: true }
  }
}
TS
printf '{ "name": "shop", "type": "module", "scripts": { "test": "vitest run" } }\n' > package.json
git add -A
git commit -q -m "Add carriers"

git checkout -q -b feature/order-carrier
cat > src/orders/carrierBadge.ts <<'TS'
import type { CarrierList } from './carriers'
import type { Order } from './types'

/** The carrier shown on an order's card, or nothing until the carriers can be told apart. */
export function getCarrierBadgeLabel(order: Order, list: CarrierList): string | null {
  if (!order.carrierId) return null
  // Until the carriers load, or when they fail to, a removed carrier can't be told from a working one.
  if (list.isLoading || list.isError) return null

  const carrier = list.carriers.find((each) => each.id === order.carrierId)
  return carrier ? carrier.name : 'Carrier removed'
}
TS
cat > src/orders/carrierField.ts <<'TS'
import type { CarrierList } from './carriers'
import type { Order } from './types'

export interface CarrierOption {
  value: string
  label: string
}

/** The options of the order form's Carrier field, keeping the saved carrier even once it's removed. */
export function getCarrierOptions(order: Order, list: CarrierList): CarrierOption[] {
  const options = list.carriers.map((carrier) => ({ value: carrier.id, label: carrier.name }))
  const isSavedCarrierListed = list.carriers.some((each) => each.id === order.carrierId)

  if (order.carrierId && !isSavedCarrierListed) {
    options.push({ value: order.carrierId, label: list.isLoading ? '' : 'Carrier removed' })
  }

  return options
}
TS
git add -A
git commit -q -m "Show the order's carrier on its card and in its form"
