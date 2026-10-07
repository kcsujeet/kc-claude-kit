export type Limit = { percentUsed: number; resetsAt?: string }
export type Context = { tokens: number | null; window: number; percent: number | null }
export type Usage = {
  context: Context | null
  fiveHour: Limit | null
  sevenDay: Limit | null
  costUsd: number | null
}
export type Tokens = { input: number; output: number; cacheRead: number }

declare module 'claude-code' {
  interface PluginState {
    'usage-band': { usage: Usage; tokens: Tokens; now: number; model: string | null; branch: string | null }
  }
}
