#!/usr/bin/env bash
# A shop repo whose feature branch seeds one realistic datetime or i18n violation per file, and
# adds one unit (formatDeliveryDate, with its `deliveryCount` key) done the way the rules ask,
# which the review should not flag. main holds the i18n setup, the shared namespace and the
# store settings the clean unit reads.
set -euo pipefail

git init -q -b main
git config user.email eval@example.com
git config user.name "Eval Fixture"
mkdir -p src/i18n src/settings messages
cat > README.md <<'MD'
# shop

Translations: `messages/en.json` is the source locale. Every other locale file is generated from
it by the translation service on merge; never edit those by hand.
MD
cat > messages/en.json <<'JSON'
{
  "common": {
    "cancel": "Cancel",
    "save": "Save"
  },
  "orders": {
    "title": "Orders"
  }
}
JSON
cat > messages/fr.json <<'JSON'
{
  "common": {
    "cancel": "Annuler",
    "save": "Enregistrer"
  },
  "orders": {
    "title": "Commandes"
  }
}
JSON
cat > src/i18n/t.ts <<'TS'
import { IntlMessageFormat } from 'intl-messageformat'
import messages from '../../messages/en.json'

/** Looks up a message by dotted key and formats it as ICU MessageFormat with `values`. */
export function t(key: string, values: Record<string, string | number> = {}): string {
  const template = key.split('.').reduce<unknown>((node, part) => (node as Record<string, unknown>)[part], messages)
  return String(new IntlMessageFormat(String(template), 'en').format(values))
}
TS
cat > src/settings/storeSettings.ts <<'TS'
/** The store's own settings, chosen by its owner. */
export interface StoreSettings {
  timeZone: string
  locale: string
  hour12: boolean
}
TS
mkdir -p src/orders
cat > src/orders/deliverySummary.ts <<'TS'
/** Lines for an order's delivery section. */
export function describeDeliveries(deliverAts: Date[]): string[] {
  return deliverAts.map((deliverAt) => deliverAt.toString())
}
TS
printf '{ "name": "shop", "type": "module", "dependencies": { "intl-messageformat": "^10.7.0" } }\n' > package.json
git add -A
git commit -q -m "Add i18n setup and store settings"

git checkout -q -b feature/order-dates-and-copy
mkdir -p src/orders src/returns src/api

# datetime §D1: hand-rolled day arithmetic.
cat > src/returns/returnDeadline.ts <<'TS'
export function getReturnDeadline(deliveredAt: Date): Date {
  return new Date(deliveredAt.getTime() + 30 * 24 * 60 * 60 * 1000)
}
TS

# datetime §D3: an instant sent to the backend truncated to a date.
cat > src/api/scheduleDelivery.ts <<'TS'
export async function scheduleDelivery(orderId: string, deliverAt: Date): Promise<void> {
  await fetch(`/api/orders/${orderId}/delivery`, {
    method: 'POST',
    body: JSON.stringify({ deliver_at: deliverAt.toISOString().slice(0, 10) }),
  })
}
TS

# datetime §D6: a time zone hardcoded instead of read from the store's settings.
cat > src/orders/cutoffTime.ts <<'TS'
export function formatCutoff(cutoff: Date): string {
  return cutoff.toLocaleTimeString('en-US', { timeZone: 'America/New_York', hour: 'numeric', minute: '2-digit' })
}
TS

# i18n §I2: a generated locale edited by hand.
python3 - <<'PY'
import json
for name, value in (("en", "Track order"), ("fr", "Suivre la commande")):
    path = f"messages/{name}.json"
    data = json.load(open(path))
    data["orders"]["track"] = value
    json.dump(data, open(path, "w"), indent=2, ensure_ascii=False)
    open(path, "a").write("\n")
PY

# i18n §I6: a countable noun without an ICU plural.
python3 - <<'PY'
import json
path = "messages/en.json"
data = json.load(open(path))
data["orders"]["itemCount"] = "{count} items"
data["orders"]["shipped"] = "shipped"
data["orders"]["cancelOrder"] = "Cancel"
data["common"]["delivery"] = "{count, plural, one {# delivery} other {# deliveries}}"
json.dump(data, open(path, "w"), indent=2, ensure_ascii=False)
open(path, "a").write("\n")
PY
cat > src/orders/itemCount.ts <<'TS'
import { t } from '../i18n/t'

export function describeItemCount(count: number): string {
  return t('orders.itemCount', { count })
}
TS

# i18n §I7: a sentence glued from fragments.
cat > src/orders/shippedNotice.ts <<'TS'
import { t } from '../i18n/t'

export function getShippedNotice(orderNumber: string): string {
  return t('orders.title') + ' ' + orderNumber + ' ' + t('orders.shipped')
}
TS

# i18n §I3: a new key duplicating the shared `common.cancel`.
cat > src/orders/cancelButtonLabel.ts <<'TS'
import { t } from '../i18n/t'

export function getCancelButtonLabel(): string {
  return t('orders.cancelOrder')
}
TS

# Clean: dates formatted in the store's own time zone, locale and clock, and a real ICU plural.
cat > src/orders/formatDeliveryDate.ts <<'TS'
import type { StoreSettings } from '../settings/storeSettings'

export function formatDeliveryDate(deliverAt: Date, settings: StoreSettings): string {
  return new Intl.DateTimeFormat(settings.locale, {
    timeZone: settings.timeZone,
    hour12: settings.hour12,
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(deliverAt)
}
TS
cat > src/orders/deliverySummary.ts <<'TS'
import { t } from '../i18n/t'
import type { StoreSettings } from '../settings/storeSettings'
import { formatDeliveryDate } from './formatDeliveryDate'

/** Lines for an order's delivery section: how many, then each in the store's own time. */
export function describeDeliveries(deliverAts: Date[], settings: StoreSettings): string[] {
  const countLine = t('common.delivery', { count: deliverAts.length })
  const dateLines = deliverAts.map((deliverAt) => formatDeliveryDate(deliverAt, settings))
  return [countLine, ...dateLines]
}
TS
git add -A
git commit -q -m "Add order dates, delivery scheduling and order copy"
