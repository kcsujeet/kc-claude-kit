import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, SessionMeasureInput, SessionRateLimit } from 'claude-code'

import type { Limit, Tokens, Usage } from '../types'
import { INK, formatCost, formatModel, formatRemaining, formatTokens, usageColor } from './format'

const usageAtom = atom({ plugin: 'usage-band', key: 'usage' } as const, {
  context: null,
  fiveHour: null,
  sevenDay: null,
  costUsd: null,
} as Usage)
const tokensAtom = atom({ plugin: 'usage-band', key: 'tokens' } as const, {
  input: 0,
  output: 0,
  cacheRead: 0,
} as Tokens)
const nowAtom = atom({ plugin: 'usage-band', key: 'now' } as const, 0)
const modelAtom = atom({ plugin: 'usage-band', key: 'model' } as const, null as string | null)
const branchAtom = atom({ plugin: 'usage-band', key: 'branch' } as const, null as string | null)

const PILL_PADDING_X = 2
// A blank row between pill rows once a narrow terminal wraps them.
const PILL_ROW_GAP = 1
const MUTED = '#5f6b66'

type Segment = { text: string; color: string; isBold?: boolean }

function findLimit(limits: readonly SessionRateLimit[], kind: string): Limit | null {
  const limit = limits.find((candidate) => candidate.kind === kind)
  if (limit === undefined) return null
  return { percentUsed: limit.percentUsed, resetsAt: limit.resetsAt }
}

// `$.session.usage()` and a `session.measure` event carry the same figures.
type Measurement = Pick<SessionMeasureInput, 'context' | 'rateLimits' | 'cost'>

function toUsage(measurement: Measurement): Usage {
  const { context, rateLimits, cost } = measurement
  return {
    context: { tokens: context.tokens ?? null, window: context.window, percent: context.percent ?? null },
    fiveHour: findLimit(rateLimits, 'five_hour'),
    sevenDay: findLimit(rateLimits, 'seven_day'),
    costUsd: cost?.usd ?? null,
  }
}

// The band is cosmetic: a failed lookup keeps the model last shown rather than
// failing the hook that asked.
async function refreshModel($: EngineInterface): Promise<void> {
  try {
    const model = await $.session.model()
    await update($, modelAtom, () => model)
  } catch {
    return
  }
}

// Empty outside a repository and on a detached HEAD, both shown as no pill.
async function refreshBranch($: EngineInterface): Promise<void> {
  try {
    const { exitCode, stdout } = await $.process.run(['git', 'branch', '--show-current'])
    const branch = exitCode === 0 ? stdout.trim() : ''
    await update($, branchAtom, () => (branch === '' ? null : branch))
  } catch {
    return
  }
}

export const register: Register = (on) => {
  on('session.start', async ($, e, next) => {
    const result = await next(e)
    const usage = await $.session.usage()
    await update($, usageAtom, () => toUsage(usage))
    const startedNow = await $.clock.now()
    await update($, nowAtom, () => startedNow)
    await refreshModel($)
    await refreshBranch($)
    $.clock.every(30_000, async () => {
      const tickNow = await $.clock.now()
      await update($, nowAtom, () => tickNow)
    })
    return result
  })

  on('session.measure', async ($, e, next) => {
    await update($, usageAtom, () => toUsage(e))
    const measuredNow = await $.clock.now()
    await update($, nowAtom, () => measuredNow)
    await refreshModel($)
    return next(e)
  })

  // Every model request, main thread and subagents alike, adds its usage.
  on('turn.step', async function* ($, e, next) {
    const result = yield* next(e)
    const stepUsage = result.usage
    if (stepUsage !== null) {
      const stepInput = stepUsage.input_tokens + stepUsage.cache_creation_input_tokens
      await update($, tokensAtom, (tokens) => ({
        input: tokens.input + stepInput,
        output: tokens.output + stepUsage.output_tokens,
        cacheRead: tokens.cacheRead + stepUsage.cache_read_input_tokens,
      }))
    }
    return result
  })

  // A /model switch shows as soon as the next prompt goes out; a branch switched
  // outside the session, by then too.
  on('prompt.submit', async ($, e, next) => {
    const result = await next(e)
    await refreshModel($)
    await refreshBranch($)
    return result
  })

  // A checkout the model runs shows as soon as the command returns.
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const result = await next(e)
    await refreshBranch($)
    return result
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)

    const usage = await read($, usageAtom)
    const tokens = await read($, tokensAtom)
    await read($, nowAtom) // subscribes the band to the 30s tick
    const now = await $.clock.now()
    const model = await read($, modelAtom)
    const branch = await read($, branchAtom)
    const { Box, Text } = $.ui.resolve(e)
    // Held to the band's own width so the row wraps instead of pushing the
    // transcript and the band's [-] past the terminal's edge.
    const bandWidth = e.props.bodyColumns

    const pill = (key: string, segments: Segment[], background: string) => (
      <Box key={key} backgroundColor={background} paddingX={PILL_PADDING_X} marginRight={1}>
        <Text backgroundColor={background}>
          {segments.map((segment, index) => (
            <Text key={`s${index}`} color={segment.color} bold={segment.isBold === true}>
              {segment.text}
            </Text>
          ))}
        </Text>
      </Box>
    )

    const limitPill = (key: string, icon: string, label: string, limit: Limit, background: string, accent: string) => {
      const resetsAtMs = limit.resetsAt === undefined ? null : Date.parse(limit.resetsAt)
      const hasReset = resetsAtMs !== null && !Number.isNaN(resetsAtMs)
      const segments: Segment[] = [
        { text: `${icon} `, color: accent },
        { text: `${label} `, color: MUTED },
        { text: `${Math.round(limit.percentUsed)}%`, color: usageColor(limit.percentUsed), isBold: true },
      ]
      if (hasReset) {
        segments.push({ text: `  ↻ ${formatRemaining(resetsAtMs, now)}`, color: MUTED })
      }
      return pill(key, segments, background)
    }

    const valuePill = (key: string, icon: string, value: string, background: string, accent: string) =>
      pill(
        key,
        [
          { text: `${icon} `, color: accent },
          { text: value, color: INK, isBold: true },
        ],
        background,
      )

    const pills = []
    if (model !== null) {
      pills.push(valuePill('model', '✦', formatModel(model), '#ececec', '#d97757'))
    }
    if (branch !== null) {
      pills.push(valuePill('branch', '⎇', branch, '#e6e1d8', '#7a5c3a'))
    }
    if (usage.context !== null && usage.context.percent !== null) {
      const { percent, tokens: contextTokens, window } = usage.context
      const fill = contextTokens === null ? '' : `  ${formatTokens(contextTokens)}/${formatTokens(window)}`
      pills.push(
        pill(
          'context',
          [
            { text: '◧ ', color: '#3b8ea5' },
            { text: 'ctx ', color: MUTED },
            { text: `${percent}%`, color: usageColor(percent), isBold: true },
            { text: fill, color: MUTED },
          ],
          '#d5e9ef',
        ),
      )
    }
    if (usage.fiveHour !== null) {
      pills.push(limitPill('five', '◔', '5h', usage.fiveHour, '#d3e6dd', '#3f8a6a'))
    }
    if (usage.sevenDay !== null) {
      pills.push(limitPill('seven', '▦', '7d', usage.sevenDay, '#e3dcf3', '#7a5cc4'))
    }
    pills.push(valuePill('in', '↑', formatTokens(tokens.input), '#f3dcd6', '#c0583e'))
    pills.push(valuePill('out', '↓', formatTokens(tokens.output), '#d9eadb', '#4a8a52'))
    pills.push(valuePill('cache', '≋', formatTokens(tokens.cacheRead), '#d9e0f6', '#4a63c4'))
    if (usage.costUsd !== null) {
      pills.push(valuePill('cost', '$', formatCost(usage.costUsd), '#f1e6cf', '#a8862e'))
    }

    // The band is shared: whatever the plugins beneath drew (image-preview's thumbnails) stays,
    // stacked above the pills, so the pills never hide it and an empty band adds no rows.
    const above = await next(e)

    return (
      <Box flexDirection="column">
        {above}
        <Box flexDirection="row" flexWrap="wrap" rowGap={PILL_ROW_GAP} width={bandWidth} paddingX={1} paddingTop={1}>
          {pills}
        </Box>
      </Box>
    )
  })
}
