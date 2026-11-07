#!/usr/bin/env bash
# Tests scripts/trace-uses.sh against a small shop repo and a sibling storefront repo, both built
# in a scratch directory and changed by a real commit, so the diff is git's own.
set -euo pipefail

tests_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/harness.sh
. "$tests_dir/lib/harness.sh"
trace_uses="$(dirname "$tests_dir")/scripts/trace-uses.sh"

shop="$work_dir/shop"
storefront="$work_dir/storefront"
mkdir -p "$shop/src" "$shop/db/migrate" "$shop/app/models" "$shop/config" "$shop/spec/models" \
  "$storefront/src"

write() { mkdir -p "$(dirname "$1")"; cat > "$1"; }

write "$shop/src/price.ts" <<'EOF'
export function formatPrice(amount: number) {
  return `$${amount}`
}
EOF
write "$shop/src/cart.ts" <<'EOF'
import { formatPrice } from './price'

export const cartLabel = (total: number) => formatPrice(total)
EOF
write "$shop/src/cart.test.ts" <<'EOF'
import { cartLabel } from './cart'
test('label', () => expect(cartLabel(2)).toBe('$2'))
EOF
write "$shop/src/OrderCard.tsx" <<'EOF'
interface OrderCardProps {
  total: number
  currency: string
}

export function OrderCard({ total, currency }: OrderCardProps) {
  return <p>{total} {currency}</p>
}
EOF
write "$shop/src/Checkout.tsx" <<'EOF'
import { OrderCard } from './OrderCard'

export function Checkout() {
  return <OrderCard total={3} currency="EUR" />
}
EOF
write "$shop/src/receipt.ts" <<'EOF'
export function receiptLine(order: { currency: string }) {
  return order.currency
}
EOF
write "$shop/db/migrate/001_create_orders.rb" <<'EOF'
class CreateOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :orders
  end
end
EOF
write "$shop/app/models/order.rb" <<'EOF'
class Order < ApplicationRecord
  def shipped?
    fulfilment_state == "shipped"
  end
end
EOF
write "$shop/spec/models/order_spec.rb" <<'EOF'
RSpec.describe Order do
  it { expect(Order.new(fulfilment_state: "shipped")).to be_shipped }
end
EOF
write "$shop/config/routes.rb" <<'EOF'
Rails.application.routes.draw do
end
EOF
write "$storefront/src/refund.ts" <<'EOF'
export const refund = (id: string) => fetch(`/orders/${id}/refund`)
export const refundUrl = '/orders/:id/refund'
EOF

for repo in "$shop" "$storefront"; do
  git -C "$repo" init -q
  git -C "$repo" add -A
  git -C "$repo" -c user.email=t@example.com -c user.name=t commit -qm base
done

# The change: formatPrice takes cents, OrderCard drops its currency prop, a column is added and a
# route is added.
write "$shop/src/price.ts" <<'EOF'
export function formatPrice(amountInCents: number) {
  return `$${amountInCents / 100}`
}
EOF
write "$shop/src/OrderCard.tsx" <<'EOF'
interface OrderCardProps {
  total: number
}

export function OrderCard({ total }: OrderCardProps) {
  return <p>{total}</p>
}
EOF
write "$shop/db/migrate/002_add_fulfilment_state.rb" <<'EOF'
class AddFulfilmentState < ActiveRecord::Migration[7.1]
  def change
    add_column :orders, :fulfilment_state, :string, null: false, default: "new"
  end
end
EOF
write "$shop/config/routes.rb" <<'EOF'
Rails.application.routes.draw do
  post '/orders/:id/refund', to: 'refunds#create'
end
EOF
git -C "$shop" add -A
git -C "$shop" -c user.email=t@example.com -c user.name=t commit -qm change
git -C "$shop" diff HEAD~1 HEAD > "$work_dir/change.diff"

out=$(cd "$shop" && bash "$trace_uses" "$work_dir/change.diff" --also "$storefront")

# --- what the diff changes is listed by name ------------------------------------------------
expect_contains "a changed function is a name" "name formatPrice (definition, src/price.ts)" "$out"
expect_contains "a removed prop is a name" "name currency (member, src/OrderCard.tsx)" "$out"
expect_contains "a changed component is a name" "name OrderCard (definition, src/OrderCard.tsx)" "$out"
expect_contains "an added column is a name" "name fulfilment_state (field, db/migrate/002_add_fulfilment_state.rb)" "$out"
expect_contains "a route is a name" "name /orders/:id/refund (route, config/routes.rb)" "$out"
expect_eq "the table an add_column names is not a name" "" "$(printf '%s\n' "$out" | grep '^name orders ' || true)"
expect_eq "an option value is not a name" "" "$(printf '%s\n' "$out" | grep -E '^name (string|new) ' || true)"

# --- every use, in other files and the sibling repo ------------------------------------------
expect_contains "a caller in another file is a use" "  src/cart.ts:3: export const cartLabel = (total: number) => formatPrice(total)" "$out"
expect_contains "a caller passing the removed prop is a use" "  src/Checkout.tsx:4:   return <OrderCard total={3} currency=\"EUR\" />" "$out"
expect_contains "a model reading the new column is a use" "  app/models/order.rb:3:     fulfilment_state == \"shipped\"" "$out"
expect_contains "a use in the sibling repo is listed under its path" "$storefront/src/refund.ts:2: export const refundUrl = '/orders/:id/refund'" "$out"
expect_contains "a member read in an unrelated file is listed for judging" "  src/receipt.ts:2:   return order.currency" "$out"

# --- lines the diff adds, and a definition, are not uses -------------------------------------
expect_eq "a line the diff adds is not a use" "" "$(printf '%s\n' "$out" | grep -F 'src/price.ts:1:' || true)"
expect_eq "the migration's own line is not a use" "" "$(printf '%s\n' "$out" | grep -F '002_add_fulfilment_state.rb:3:' || true)"
expect_contains "the import of a changed function is a use" "  src/cart.ts:1: import { formatPrice } from './price'" "$out"
expect_contains "formatPrice has two uses (import and call)" "name formatPrice (definition, src/price.ts): 2 uses" "$out"

# --- the tests that cover the uses ------------------------------------------------------------
expect_contains "a use's own test file is listed" "  src/cart.test.ts" "$out"
expect_contains "a Ruby spec named after a use file is listed" "  spec/models/order_spec.rb" "$out"
expect_eq "the summary counts names, uses and tests" \
  "$(printf '%s\n' "$out" | grep -c '^name ') names" \
  "$(printf '%s\n' "$out" | sed -n 's/^summary: \([0-9]*\) names.*/\1 names/p')"
summary_uses=$(printf '%s\n' "$out" | sed -n 's/^summary: [0-9]* names, \([0-9]*\) uses.*/\1/p')
expect_eq "the summary's use count equals the listed uses" "$(printf '%s\n' "$out" | grep -cE '^  [^ ].*:[0-9]+: ')" "$summary_uses"

# --- a hunk that only changes a props type: the component it types is traced too ------------
props_only=$(printf '%s\n' '--- a/src/OrderCard.tsx' '+++ b/src/OrderCard.tsx' '@@ -1,3 +1,2 @@ interface OrderCardProps {' \
  '   total: number' '-  currency: string' ' }' | (cd "$shop" && bash "$trace_uses" -))
expect_contains "a hunk's enclosing type is a name (diff on stdin)" "name OrderCardProps (enclosing, src/OrderCard.tsx)" "$props_only"
expect_contains "a props type adds its component" "name OrderCard (component, src/OrderCard.tsx)" "$props_only"
expect_contains "the component's caller is a use" "  src/Checkout.tsx:4:   return <OrderCard total={3} currency=\"EUR\" />" "$props_only"

# --- --symbols traces names without a diff ----------------------------------------------------
named=$(cd "$shop" && bash "$trace_uses" --symbols 'cartLabel, receiptLine')
expect_contains "--symbols lists a named function's uses" "name cartLabel (named, -): 2 uses" "$named"
expect_contains "--symbols finds the test using it" "  src/cart.test.ts:1: import { cartLabel } from './cart'" "$named"
expect_contains "--symbols with no use says 0" "name receiptLine (named, -): 0 uses" "$named"

# --- usage ------------------------------------------------------------------------------------
set +e
bash "$trace_uses" >/dev/null 2>&1; no_args=$?
(cd "$shop" && bash "$trace_uses" "$work_dir/missing.diff" >/dev/null 2>&1); missing=$?
(cd "$work_dir" && bash "$trace_uses" --symbols x >/dev/null 2>&1); outside=$?
(cd "$shop" && bash "$trace_uses" "$work_dir/change.diff" --also "$work_dir" >/dev/null 2>&1); bad_also=$?
set -e
expect_eq "no arguments: exit 2" 2 "$no_args"
expect_eq "unreadable diff: exit 2" 2 "$missing"
expect_eq "outside a repo: exit 2" 2 "$outside"
expect_eq "--also that is not a repo: exit 2" 2 "$bad_also"

finish
