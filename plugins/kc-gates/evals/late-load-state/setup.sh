#!/usr/bin/env bash
# A shop repo whose feature branch keeps an order email's footer in step with its sender
# (correctness §B15, when each input arrives). main holds senderFor, which signs a draft as its
# storefront once the storefront list has loaded and as the shop until then. The branch adds a
# DraftEditor that appends the sender's footer on the first refresh and swaps footers whenever the
# sender changes. A saved storefront draft, whose body already ends with the storefront's footer,
# opened before the list loads: the first refresh signs it as the shop and appends the shop's
# footer; the next, with the list, swaps that for the storefront's, so it shows twice. The branch
# also adds subjectLine, which handles its edge cases and draws no finding.
set -euo pipefail

git init -q -b main
git config user.email eval@example.com
git config user.name "Eval Fixture"
mkdir -p src/drafts

cat > src/drafts/types.ts <<'TS'
export interface Sender {
  name: string
  footer: string
}
export interface Storefront extends Sender {
  id: string
}
export interface Shop extends Sender {
  id: string
}
export interface OrderDraft {
  orderNumber: string
  storefrontId: string | null
  body: string
}
TS
cat > src/drafts/sender.ts <<'TS'
import type { OrderDraft, Sender, Shop, Storefront } from './types'

/**
 * Who an order email goes out as: the draft's storefront when it has one, otherwise the shop.
 * `storefronts` is undefined until the storefront list has loaded.
 */
export function senderFor(draft: OrderDraft, storefronts: Storefront[] | undefined, shop: Shop): Sender {
  const storefront = storefronts?.find((candidate) => candidate.id === draft.storefrontId)
  return storefront ?? shop
}
TS
printf '{ "name": "shop", "type": "module", "scripts": { "test": "vitest run" } }\n' > package.json
git add -A
git commit -q -m "Add order drafts and their sender"

git checkout -q -b feature/sender-footer

cat > src/drafts/editor.ts <<'TS'
import { senderFor } from './sender'
import type { OrderDraft, Sender, Shop, Storefront } from './types'

/** Keeps a draft's footer in step with who it is sent as. */
export class DraftEditor {
  private sender: Sender | null = null

  constructor(
    private draft: OrderDraft,
    private readonly shop: Shop,
  ) {}

  /** Runs on every refresh of the storefront list and whenever the person picks a storefront. */
  refresh(storefronts: Storefront[] | undefined): OrderDraft {
    const next = senderFor(this.draft, storefronts, this.shop)
    if (this.sender === null) {
      if (!this.draft.body.endsWith(next.footer)) {
        this.draft = { ...this.draft, body: `${this.draft.body}\n\n${next.footer}` }
      }
    } else if (next.footer !== this.sender.footer) {
      this.draft = { ...this.draft, body: this.draft.body.replace(this.sender.footer, next.footer) }
    }
    this.sender = next
    return this.draft
  }

  pickStorefront(storefrontId: string | null, storefronts: Storefront[] | undefined): OrderDraft {
    this.draft = { ...this.draft, storefrontId }
    return this.refresh(storefronts)
  }
}
TS

# Clean: a subject line that handles a missing order number and a long storefront name.
cat > src/drafts/subject.ts <<'TS'
import type { OrderDraft, Sender } from './types'

const MAX_SENDER_LENGTH = 40

export function subjectLine(draft: OrderDraft, sender: Sender): string {
  const name = sender.name.length > MAX_SENDER_LENGTH ? `${sender.name.slice(0, MAX_SENDER_LENGTH - 1)}…` : sender.name
  return draft.orderNumber ? `Your order ${draft.orderNumber} from ${name}` : `Your order from ${name}`
}
TS
git add -A
git commit -q -m "Keep an order email's footer in step with its sender; add its subject line"
