#!/usr/bin/env bash
# A shop repo whose feature branch moves formatPrice from dollars to cents and updates five of its
# six callers. The order receipt email, which the branch never touches and which imports the
# formatter under another name, still passes dollars (§B8): its prices now show a hundred times too
# small. The cart summary, one of the callers the branch updates, is correct and draws no finding.
set -euo pipefail

git init -q -b main
git config user.email eval@example.com
git config user.name "Eval Fixture"
mkdir -p src/money src/cart src/catalog src/checkout src/wishlist src/search src/orders/emails

cat > src/money/formatPrice.ts <<'TS'
/** Formats an amount in dollars for display: 12.5 -> "$12.50". */
export function formatPrice(amount: number): string {
  return `$${amount.toFixed(2)}`
}
TS

# Writes a caller of formatPrice: <file> <type> <amount field> <function> <label>.
write_caller() {
  local file=$1 type=$2 field=$3 function_name=$4 label=$5
  cat > "$file" <<TS
import { formatPrice } from '../money/formatPrice'

export interface $type {
  name: string
  $field: number
}

export function $function_name(item: $type): string {
  return \`\${item.name} $label \${formatPrice(item.$field)}\`
}
TS
}
write_caller src/cart/summary.ts CartLine total cartSummary 'total:'
write_caller src/catalog/productCard.ts Product price productCard '-'
write_caller src/checkout/total.ts CheckoutLine amount checkoutLine 'due:'
write_caller src/wishlist/item.ts WishlistItem price wishlistItem 'at'
write_caller src/search/result.ts SearchHit price searchResult 'from'
cat > src/orders/emails/receiptEmail.ts <<'TS'
import { formatPrice as price } from '../../money/formatPrice'

export interface ReceiptOrder {
  id: string
  total: number
}

export function receiptEmailBody(order: ReceiptOrder): string {
  return `Thanks for your order ${order.id}. You paid ${price(order.total)}.`
}
TS
printf '{ "name": "shop", "type": "module", "scripts": { "test": "vitest run" } }\n' > package.json
git add -A
git commit -q -m "Format prices across the shop"

git checkout -q -b feature/cents
cat > src/money/formatPrice.ts <<'TS'
/** Formats an amount in cents for display: 1250 -> "$12.50". Cents avoid float rounding. */
export function formatPrice(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`
}
TS
for file in src/cart/summary.ts src/catalog/productCard.ts src/checkout/total.ts src/wishlist/item.ts src/search/result.ts; do
  sed -E 's/^  (total|price|amount): number$/  \1Cents: number/; s/formatPrice\(item\.(total|price|amount)\)/formatPrice(item.\1Cents)/' "$file" > "$file.new"
  mv "$file.new" "$file"
done
git add -A
git commit -q -m "Keep prices in cents"
