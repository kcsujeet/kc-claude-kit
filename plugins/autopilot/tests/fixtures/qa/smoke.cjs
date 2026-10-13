// Smoke script for qa-browser.sh: opens a URL, saves a screenshot.
const { chromium } = require('playwright')
;(async () => {
  const [url, out] = process.argv.slice(2)
  const browser = await chromium.launch({ headless: true })
  const page = await browser.newPage()
  await page.goto(url)
  await page.screenshot({ path: out })
  console.log(await page.title())
  await browser.close()
})().catch(error => { console.error(error); process.exit(1) })
