#!/usr/bin/env bash
# Builds a static order email page that adds the sender's footer to the body and swaps it when the
# storefront changes, with drafts saved to localStorage. Every fresh path works: a new email gets
# one footer, a switch swaps it, a save keeps it. Reopening a saved draft after a reload appends the
# footer again, so it shows twice, and the next switch swaps only one of them.
set -euo pipefail

mkdir -p site
cat > TICKET.md <<'MD'
# ABC-1: Storefront footer on order emails

An order email ends with the footer of the storefront it is sent from. Switching storefront swaps
the footer for the new one. "Save draft" keeps the email so it can be finished later: opening the
page again brings the saved draft back.
MD

cat > site/compose.html <<'HTML'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Order email</title>
    <style>
      body { font-family: system-ui, sans-serif; margin: 24px; max-width: 640px; }
      label { display: block; margin: 12px 0 4px; }
      textarea { width: 100%; height: 220px; font: inherit; }
    </style>
  </head>
  <body>
    <h1>Order email</h1>
    <label for="storefront">Send from</label>
    <select id="storefront">
      <option value="garden">Garden Store</option>
      <option value="kitchen">Kitchen Store</option>
    </select>
    <label for="body">Message</label>
    <textarea id="body"></textarea>
    <p><button id="save" type="button">Save draft</button> <span id="status"></span></p>
    <script>
      const footers = {
        garden: '-- Garden Store, 12 Elm Road',
        kitchen: '-- Kitchen Store, 4 Mill Lane',
      }
      const select = document.getElementById('storefront')
      const body = document.getElementById('body')
      let currentFooter = null

      function addFooter(storefront) {
        currentFooter = footers[storefront]
        body.value = `${body.value}\n\n${currentFooter}`
      }

      select.addEventListener('change', () => {
        const next = footers[select.value]
        body.value = body.value.replace(currentFooter, next)
        currentFooter = next
      })

      document.getElementById('save').addEventListener('click', () => {
        localStorage.setItem('draft', JSON.stringify({ storefront: select.value, body: body.value }))
        document.getElementById('status').textContent = 'Saved'
      })

      const saved = JSON.parse(localStorage.getItem('draft') || 'null')
      if (saved) {
        select.value = saved.storefront
        body.value = saved.body
        addFooter(saved.storefront)
      } else {
        body.value = 'Hi, your order is on its way.'
        addFooter(select.value)
      }
    </script>
  </body>
</html>
HTML
