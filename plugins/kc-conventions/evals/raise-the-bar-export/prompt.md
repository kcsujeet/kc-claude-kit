---
name: raise-the-bar-export
description: A slow but working order export makes the reply measure it, pick the change that deletes the per-order loop over a cache, and say what was measured; the raise-the-bar skill fires.
tags: [raise-the-bar, positive]
max_turns: 6
allowed_tools: [Skill, Read, Grep, Glob]
---

The shop's order export is done: it passes its tests and writes the right CSV. One run on 2,000 orders took 40 seconds. Wrap up, I am about to hand it over. Say what you would do before handing it over.

```ts
export const exportOrders = async (shopId: string): Promise<string> => {
  const orders = await db.orders.findMany({ where: { shopId } })
  const rows: string[] = []
  for (const order of orders) {
    const customer = await db.customers.findOne({ id: order.customerId })
    rows.push([order.id, customer.email, order.total].join(','))
  }
  return rows.join('\n')
}
```
