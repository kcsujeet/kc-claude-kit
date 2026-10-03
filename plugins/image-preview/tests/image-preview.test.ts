import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import type { Engine } from 'claude-code/testing'

const TMP_ROOT = '/tmp/claude-502'
const IMAGES_DIR = `${TMP_ROOT}/-proj/sess-1/images`
// A 1x2 top-down 32-bit BMP: one cell, white over black.
const BMP_BASE64 = (() => {
  const bytes = new Uint8Array(54 + 8)
  const view = new DataView(bytes.buffer)
  view.setUint16(0, 0x424d, false)
  view.setUint32(10, 54, true)
  view.setInt32(18, 1, true)
  view.setInt32(22, -2, true)
  view.setUint16(28, 32, true)
  view.setUint32(54, 0xffffffff, true)
  view.setUint32(58, 0xff000000, true)
  return btoa(String.fromCharCode(...bytes))
})()
const BAND = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 20,
  bodyColumns: 120,
  scroll: { offset: 0, bodyRows: 19 },
  view: {},
}

const dirEntry = (name: string) => ({ name, kind: 'dir' as const, size: 0, mtimeMs: 0, isLink: false })
const fileEntry = (name: string) => ({ name, kind: 'file' as const, size: 10, mtimeMs: 1, isLink: false })

// What the band shows without this mod: another plugin's usage row, or nothing at all.
const USAGE_ROW = { type: 'Text', props: {}, children: ['usage 41%'] } as const
// Core's own drawing; in this band core draws nothing.
const EMPTY_BAND = { type: 'engine', ref: 0 } as const

type Session = { id: string }
// What `osascript` finds on the clipboard: a copied Finder file's path, or '' for anything else.
type Clipboard = { file: string }

function stubWorld(on: On, draft: { text: string }, env: Record<string, string> = {}, band: object = USAGE_ROW, session: Session = { id: 'sess-1' }, clipboard: Clipboard = { file: '' }) {
  mock.env(on, env)
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('ui.render', () => band as never)
  on('prompt.read', () => ({ value: { text: draft.text, cursor: draft.text.length } }))
  on('session.id', () => ({ value: session.id }))
  on('process.run', ($, e) => {
    const isSizeQuery = e.argv.includes('-g')
    let stdout = ''
    if (e.argv[0] === 'id') stdout = '502\n'
    if (e.argv[0] === 'osascript') stdout = `${clipboard.file}\n`
    if (isSizeQuery) stdout = 'pixelWidth: 100\n  pixelHeight: 200\n'
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  const imagesDirOf = (id: string) => `${TMP_ROOT}/-proj/${id}/images`
  on('fs.exists', ($, e) => ({ value: [TMP_ROOT, imagesDirOf(session.id)].includes(e.path) }))
  on('fs.list', ($, e) => {
    if (e.path === TMP_ROOT) return { value: [dirEntry('-proj')] }
    // Claude Code keeps a pasted image's own format: a PNG as n.png, a JPEG as n.jpg.
    return { value: [fileEntry('1.png'), fileEntry('2.jpg')] }
  })
  on('fs.read', () => ({ value: { base64: BMP_BASE64 } }))
}

test('draws a Raster thumbnail for each [Image #N] and keeps the band beneath it', async ($, on) => {
  const clock = mock.clock(on)
  const draft = { text: '' }
  stubWorld(on, draft)
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'image-preview', surface: 'terminal', component: 'AbovePrompt', props: BAND })
  expect(await ui.find({ key: 'image-1' })).toBeUndefined()

  draft.text = 'look [Image #1] '
  await clock.advance(300)
  expect((await ui.find({ key: 'image-1' }))?.type).toBe('Raster')
  expect(await ui.find({ type: 'Text', text: 'usage 41%' })).toBeDefined()

  draft.text = 'look '
  await clock.advance(300)
  expect(await ui.find({ key: 'image-1' })).toBeUndefined()
})

test('draws a pasted JPEG too', async ($, on) => {
  const clock = mock.clock(on)
  const draft = { text: 'see [Image #2]' }
  stubWorld(on, draft)
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'image-preview', surface: 'terminal', component: 'AbovePrompt', props: BAND })

  await clock.advance(300)
  expect((await ui.find({ key: 'image-2' }))?.type).toBe('Raster')
})

const KITTY_TERMINALS: Record<string, string>[] = [{ TERM: 'xterm-ghostty' }, { TERM: 'xterm-kitty' }, { KITTY_WINDOW_ID: '1' }]

for (const env of KITTY_TERMINALS) {
  test(`draws a sharp Image where the terminal speaks the kitty protocol (${JSON.stringify(env)})`, async ($, on) => {
    const clock = mock.clock(on)
    const draft = { text: 'see [Image #1] and [Image #2]' }
    stubWorld(on, draft, env)
    await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })
    const ui = await $.ui.mount({ plugin: 'image-preview', surface: 'terminal', component: 'AbovePrompt', props: BAND })

    await clock.advance(300)
    const png = await ui.find({ key: 'image-1' })
    const jpeg = await ui.find({ key: 'image-2' })
    expect(png?.type).toBe('Image')
    expect(png?.props).toMatchObject({ source: { file: `${IMAGES_DIR}/1.png`, format: 'png' } })
    // Image reads only PNG files, so a JPEG is drawn from a PNG copy.
    expect(jpeg?.props).toMatchObject({ source: { file: `${IMAGES_DIR}/../image-preview/2.png`, format: 'png' } })
  })
}

test('with nothing else in the band, draws only the thumbnails', async ($, on) => {
  const clock = mock.clock(on)
  const draft = { text: 'see [Image #1]' }
  stubWorld(on, draft, {}, EMPTY_BAND)
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'image-preview', surface: 'terminal', component: 'AbovePrompt', props: BAND })

  await clock.advance(300)
  const drawn = await ui.drawn()
  // No gap or padding of the mod's own, so an empty band beneath adds no rows.
  expect(drawn).toMatchObject({ type: 'Box', props: { flexDirection: 'column' } })
  const column = drawn.type === 'Box' ? drawn : undefined
  expect(column?.props).toEqual({ flexDirection: 'column' })
  expect(column?.children?.at(-1)).toEqual(EMPTY_BAND)
})

test('after /clear starts a new session, [Image #1] is the new session\'s image', async ($, on) => {
  const clock = mock.clock(on)
  const draft = { text: 'see [Image #1]' }
  const session = { id: 'sess-1' }
  stubWorld(on, draft, { TERM: 'xterm-ghostty' }, USAGE_ROW, session)
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'image-preview', surface: 'terminal', component: 'AbovePrompt', props: BAND })
  await clock.advance(300)
  expect((await ui.find({ key: 'image-1' }))?.props).toMatchObject({ source: { file: `${TMP_ROOT}/-proj/sess-1/images/1.png` } })

  // /clear: a new session id, its own images folder, numbering from 1 again.
  draft.text = ''
  await clock.advance(300)
  session.id = 'sess-2'
  draft.text = 'and [Image #1]'
  await clock.advance(300)
  expect((await ui.find({ key: 'image-1' }))?.props).toMatchObject({ source: { file: `${TMP_ROOT}/-proj/sess-2/images/1.png` } })
})

const FINDER_PHOTO = '/Users/me/Downloads/photo.png'
const PROMPT_ORIGIN = { kind: 'composer' } as const

async function pasteFinderFile($: Engine, on: On, file: string) {
  const clock = mock.clock(on)
  const draft = { text: '' }
  stubWorld(on, draft, { TERM: 'xterm-ghostty' }, USAGE_ROW, { id: 'sess-1' }, { file })
  on('prompt.submit', ($, e) => ({ text: e.text, context: e.context }))
  await $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'image-preview', surface: 'terminal', component: 'AbovePrompt', props: BAND })
  draft.text = 'see [Image #1]'
  await clock.advance(300)
  return ui
}

test('a copied Finder image previews the real file, not the icon Claude Code pasted', async ($, on) => {
  const ui = await pasteFinderFile($, on, FINDER_PHOTO)
  expect((await ui.find({ key: 'image-1' }))?.props).toMatchObject({ source: { file: FINDER_PHOTO } })
})

test('on send, Claude is told to read the real file behind the icon', async ($, on) => {
  await pasteFinderFile($, on, FINDER_PHOTO)
  const sent = await $.prompt.submit({ text: 'see [Image #1]', wait: false, origin: PROMPT_ORIGIN })
  expect('context' in sent ? sent.context : undefined).toEqual([
    `[Image #1] is only Finder's icon for a copied file, not the picture itself. The real image is ${FINDER_PHOTO}; read that file to see it.`,
  ])
})

test('a copied Finder file that is not an image is left alone', async ($, on) => {
  const ui = await pasteFinderFile($, on, '/Users/me/Downloads/report.pdf')
  expect((await ui.find({ key: 'image-1' }))?.props).toMatchObject({ source: { file: `${IMAGES_DIR}/1.png` } })
  const sent = await $.prompt.submit({ text: 'see [Image #1]', wait: false, origin: PROMPT_ORIGIN })
  expect('context' in sent ? sent.context : undefined).toBeUndefined()
})

test('a pasted image with no Finder file on the clipboard is left alone', async ($, on) => {
  const ui = await pasteFinderFile($, on, '')
  expect((await ui.find({ key: 'image-1' }))?.props).toMatchObject({ source: { file: `${IMAGES_DIR}/1.png` } })
})
