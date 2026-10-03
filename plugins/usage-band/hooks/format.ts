const MINUTE = 60_000
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR

export function formatTokens(count: number): string {
  if (count >= 1_000_000) return `${(count / 1_000_000).toFixed(1)}M`
  if (count >= 1_000) return `${(count / 1_000).toFixed(1)}k`
  return String(count)
}

export function formatCost(usd: number): string {
  return `$${usd.toFixed(2)}`
}

/** Time left until `resetsAt`, as "2h 40m", "1d 7h" or "12m". */
export function formatRemaining(resetsAtMs: number, nowMs: number): string {
  const remaining = Math.max(0, resetsAtMs - nowMs)
  const days = Math.floor(remaining / DAY)
  const hours = Math.floor((remaining % DAY) / HOUR)
  const minutes = Math.floor((remaining % HOUR) / MINUTE)

  if (days > 0) return `${days}d ${hours}h`
  if (hours > 0) return `${hours}h ${minutes}m`
  return `${minutes}m`
}

const MODEL_ID = /^claude-([a-z]+)-(\d+)-(\d+)(?:-\d{8})?(\[1m\])?$/

/** "claude-opus-5-5" as "Opus 5.5", "claude-haiku-4-5-20251001" as "Haiku 4.5"; any other id as given. */
export function formatModel(modelId: string): string {
  const match = MODEL_ID.exec(modelId)
  if (match === null) return modelId

  const [, family = '', major, minor, longContext] = match
  const familyName = family.charAt(0).toUpperCase() + family.slice(1)
  const contextSuffix = longContext === undefined ? '' : ' 1M'
  return `${familyName} ${major}.${minor}${contextSuffix}`
}
