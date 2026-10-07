import { describe, expect, mock, test } from 'claude-code/testing'

import { formatCost, formatModel, formatRemaining, formatTokens, usageColor } from '../hooks/format'

const HOUR = 3_600_000

describe('format', () => {
  test('tokens', async () => {
    expect([formatTokens(950), formatTokens(15_600), formatTokens(954_200), formatTokens(1_250_000)]).toEqual([
      '950',
      '15.6k',
      '954.2k',
      '1.3M',
    ])
  })

  test('model', async () => {
    expect([
      formatModel('claude-opus-5-5'),
      formatModel('claude-haiku-4-5-20251001'),
      formatModel('claude-sonnet-5-5[1m]'),
      formatModel('some-gateway-model'),
    ]).toEqual(['Opus 5.5', 'Haiku 4.5', 'Sonnet 5.5 1M', 'some-gateway-model'])
  })

  test('cost', async () => {
    expect(formatCost(4.321)).toBe('$4.32')
  })

  test('remaining time', async () => {
    const now = 0
    expect([
      formatRemaining(2 * HOUR + 40 * 60_000, now),
      formatRemaining(31 * HOUR, now),
      formatRemaining(12 * 60_000, now),
    ]).toEqual(['2h 40m', '1d 7h', '12m'])
  })

  test('usage color: ink below 70%, amber from 70%, red from 90%', async () => {
    expect([usageColor(69), usageColor(70), usageColor(89), usageColor(90), usageColor(100)]).toEqual([
      '#2b2b2b',
      '#7a4a00',
      '#7a4a00',
      '#a3141c',
      '#a3141c',
    ])
  })
})

const BRANCH_RESULT = { exitCode: 0, stdout: 'feat/usage-band\n', stderr: '', isStdoutTruncated: false, isStderrTruncated: false }

// Core's own drawing; in this band core draws nothing.
const EMPTY_BAND = { type: 'engine', ref: 0 } as const

const NOW = Date.parse('2026-10-03T10:00:00.000Z')
const iso = (ms: number) => new Date(ms).toISOString()

for (const surface of ['terminal', 'desktop'] as const) {
  test(`band draws model, context, limits, tokens and cost on ${surface}`, async ($, on) => {
    mock.clock(on, { now: NOW })
    on('ui.render', () => EMPTY_BAND as never)
    on('session.measure', ($, e) => ({ changed: [...e.changed] }))
    on('session.model', () => ({ value: 'claude-opus-5-5' }))
    on('process.run', () => ({ value: BRANCH_RESULT }))
    on('prompt.submit', ($, e) => ({ text: e.text }))
    on('turn.step', async function* ($, e) {
      return {
        turnId: e.turnId,
        index: e.index,
        answer: '',
        toolUses: [],
        stopReason: 'end_turn',
        usage: {
          model: e.model,
          input_tokens: 600,
          cache_creation_input_tokens: 15_000,
          output_tokens: 3_000,
          cache_read_input_tokens: 954_200,
        },
      }
    })

    await $.session.measure({
      context: { window: 1_000_000, tokens: 162_400, percent: 16 },
      rateLimits: [
        { kind: 'five_hour', percentUsed: 20, resetsAt: iso(NOW + 2 * HOUR + 40 * 60_000) },
        { kind: 'seven_day', percentUsed: 58, resetsAt: iso(NOW + 31 * HOUR) },
      ],
      cost: { usd: 4.32 },
      changed: ['rateLimits', 'cost'],
    })
    // A prompt is one of the moments the band reads the branch.
    await $.prompt.submit({ text: 'hi', wait: false, origin: { kind: 'composer' } })
    for await (const _ of $.turn.step({ turnId: 't1', index: 0, model: 'claude-opus-5-5', messageCount: 1 })) {
      // drain the stream
    }

    const ui = await $.ui.mount({
      plugin: 'usage-band',
      surface,
      component: 'AbovePrompt',
      props: {
        hasSurvey: false,
        isWorking: false,
        maxRows: 20,
        bodyColumns: 200,
        scroll: { offset: 0, bodyRows: 20 },
        view: {},
      },
    })
    const drawn = JSON.stringify(await ui.drawn())
    for (const shown of ['Opus 5.5', 'feat/usage-band', '16%', '162.4k/1.0M', '20%', '58%', '2h 40m', '1d 7h', '15.6k', '3.0k', '954.2k', '$4.32']) {
      expect(drawn).toContain(shown)
    }
  })
}

// What the plugins beneath draw in the shared band: image-preview's thumbnails, say.
const THUMBNAILS = { type: 'Text', props: {}, children: ['[Image #1]'] } as const
const BAND_PROPS = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 20,
  bodyColumns: 200,
  scroll: { offset: 0, bodyRows: 20 },
  view: {},
}

test('keeps what the plugins beneath drew, stacked above the pills', async ($, on) => {
  mock.clock(on, { now: NOW })
  on('ui.render', () => THUMBNAILS as never)

  const ui = await $.ui.mount({ plugin: 'usage-band', surface: 'terminal', component: 'AbovePrompt', props: BAND_PROPS })
  const drawn = await ui.drawn()

  expect(drawn).toMatchObject({ type: 'Box', props: { flexDirection: 'column' } })
  const column = drawn.type === 'Box' ? drawn : undefined
  expect(column?.children?.[0]).toEqual(THUMBNAILS)
  expect(JSON.stringify(column?.children?.[1])).toContain('↑ ')
  expect(column?.children?.[1]).toMatchObject({ type: 'Box', props: { flexWrap: 'wrap', rowGap: 1 } })
})

test('colors a percentage amber from 70% and red from 90%', async ($, on) => {
  mock.clock(on, { now: NOW })
  on('ui.render', () => EMPTY_BAND as never)
  on('session.measure', ($, e) => ({ changed: [...e.changed] }))

  await $.session.measure({
    context: { window: 200_000, tokens: 150_000, percent: 75 },
    rateLimits: [
      { kind: 'five_hour', percentUsed: 92 },
      { kind: 'seven_day', percentUsed: 10 },
    ],
    changed: ['rateLimits'],
  })

  const ui = await $.ui.mount({ plugin: 'usage-band', surface: 'terminal', component: 'AbovePrompt', props: BAND_PROPS })
  const drawn = JSON.stringify(await ui.drawn())

  expect(drawn).toContain('{"color":"#7a4a00","bold":true},"children":["75%"]')
  expect(drawn).toContain('{"color":"#a3141c","bold":true},"children":["92%"]')
  expect(drawn).toContain('{"color":"#2b2b2b","bold":true},"children":["10%"]')
})
