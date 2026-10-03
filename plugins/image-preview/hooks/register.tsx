import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { PastedImage } from '../types'
import { base64ToBytes, bmpToRaster, fitCells } from './raster'
import type { CellSize } from './raster'

// The draft is polled rather than hooked on prompt.edit: claude-image-view found that an
// image paste raises no edit until the next keystroke.
const POLL_MS = 300
const IMAGE_PLACEHOLDER = /\[Image #(\d+)\]/g
const NO_PREVIEW_COLUMNS = 12

const images = atom({ plugin: 'image-preview', key: 'images' } as const, [] as PastedImage[])

// The images folder belongs to one session: /clear starts a new one, numbered from 1 again.
let found: { sessionId: string; dir: string } | null = null
let isRefreshing = false
// Keyed by image path, so a new session's #1 never reuses the old session's.
const previews = new Map<string, PastedImage>()
// Same keys: the copied Finder file behind a pasted icon, or null once checked and not one.
const finderFiles = new Map<string, string | null>()

const IMAGE_EXTENSION = /\.(png|jpe?g|heic|heif|gif|tiff?|bmp|webp)$/i
// The path of a file copied in Finder, or '' for anything else on the clipboard. Checking
// the clipboard's types first matters: plain text coerces to a file URL (`hello` → `/hello`).
const COPIED_FILE_SCRIPT = [
  'repeat with entry in (clipboard info)',
  'if item 1 of entry is «class furl» then return POSIX path of (the clipboard as «class furl»)',
  'end repeat',
  'return ""',
]

async function findTmpRoot($: EngineInterface): Promise<string> {
  const fromEnv = await $.env.get('CLAUDE_CODE_TMPDIR')
  if (fromEnv !== undefined) return fromEnv

  const { stdout } = await $.process.run(['id', '-u'])
  const uid = stdout.trim()
  return `/tmp/claude-${uid}`
}

// Claude Code writes pasted images to <tmp>/<project-slug>/<session-id>/images/<n>.<ext>.
async function findImagesDir($: EngineInterface, sessionId: string): Promise<string | null> {
  const tmpRoot = await findTmpRoot($)
  const projects = await $.fs.list(tmpRoot).catch(() => [])

  for (const project of projects) {
    const candidate = `${tmpRoot}/${project.name}/${sessionId}/images`
    const isMatch = project.kind === 'dir' && (await $.fs.exists(candidate))
    if (isMatch) return candidate
  }
  return null
}

// Claude Code keeps each paste in its own format (n.png, n.jpg, ...), so find it by number.
async function findImageFile($: EngineInterface, dir: string, number: number): Promise<string | null> {
  const files = await $.fs.list(dir)
  const file = files.find(entry => entry.kind === 'file' && entry.name.startsWith(`${number}.`))
  return file === undefined ? null : `${dir}/${file.name}`
}

// Terminals that draw real pictures over the kitty graphics protocol announce themselves:
// Ghostty with TERM=xterm-ghostty (ghostty.org/docs/help/terminfo), kitty with
// TERM=xterm-kitty and KITTY_WINDOW_ID (sw.kovidgoyal.net/kitty/glossary).
async function drawsPictures($: EngineInterface): Promise<boolean> {
  const [term, kittyWindowId] = await Promise.all([$.env.get('TERM'), $.env.get('KITTY_WINDOW_ID')])
  const isGhostty = term === 'xterm-ghostty'
  const isKitty = term === 'xterm-kitty' || kittyWindowId !== undefined
  return isGhostty || isKitty
}

// Image reads only PNG files, so anything else gets a PNG copy.
async function asPng($: EngineInterface, image: string, previewDir: string, number: number): Promise<string> {
  if (image.endsWith('.png')) return image

  const png = `${previewDir}/${number}.png`
  await $.process.run(['sips', '-s', 'format', 'png', image, '--out', png])
  return png
}

// The mod's environment cannot decode a PNG or JPEG, so macOS `sips` resamples it to a
// small uncompressed BMP, two stacked pixels per cell, which raster.ts turns into half blocks.
async function asCells($: EngineInterface, image: string, previewDir: string, number: number, box: CellSize) {
  const bmp = `${previewDir}/${number}.bmp`
  const pixelWidth = String(box.columns)
  const pixelHeight = String(box.rows * 2)
  const resample = ['sips', '-z', pixelHeight, pixelWidth, '-s', 'format', 'bmp', image, '--out', bmp]
  await $.process.run(resample)

  const { base64 } = await $.fs.read(bmp, { as: 'bytes' })
  return bmpToRaster(base64ToBytes(base64))
}

// Copying an image file in Finder puts the file's icon on the clipboard, and ctrl+v pastes
// that icon. Read right after the paste, the clipboard still names the real file.
async function copiedFinderImage($: EngineInterface): Promise<string | null> {
  const argv = ['osascript', ...COPIED_FILE_SCRIPT.flatMap(line => ['-e', line])]
  const { stdout } = await $.process.run(argv)
  const path = stdout.trim()
  return IMAGE_EXTENSION.test(path) ? path : null
}

async function makePreview($: EngineInterface, dir: string, number: number, image: string): Promise<PastedImage> {
  const info = await $.process.run(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', image])
  const width = Number(/pixelWidth: (\d+)/.exec(info.stdout)?.[1])
  const height = Number(/pixelHeight: (\d+)/.exec(info.stdout)?.[1])
  const hasSize = width > 0 && height > 0
  if (!hasSize) return { number, columns: NO_PREVIEW_COLUMNS, rows: 1, picture: null }

  const box = fitCells({ width, height })
  const { columns, rows } = box
  const previewDir = `${dir}/../image-preview`
  await $.process.run(['mkdir', '-p', previewDir])

  if (await drawsPictures($)) {
    const file = await asPng($, image, previewDir, number)
    return { number, columns, rows, picture: { file } }
  }

  const raster = await asCells($, image, previewDir, number, box)
  if (raster === null) return { number, columns, rows, picture: null }
  return { number, columns: raster.columns, rows: raster.rows, picture: { cells: raster.cells } }
}

async function currentImagesDir($: EngineInterface): Promise<string | null> {
  const sessionId = await $.session.id()
  if (found?.sessionId === sessionId) return found.dir

  const dir = await findImagesDir($, sessionId)
  found = dir === null ? null : { sessionId, dir }
  return dir
}

async function previewFor($: EngineInterface, number: number): Promise<PastedImage | null> {
  const dir = await currentImagesDir($)
  if (dir === null) return null

  const key = `${dir}/${number}`
  const cached = previews.get(key)
  if (cached !== undefined) return cached

  if (!finderFiles.has(key)) {
    const finderFile = await copiedFinderImage($).catch(() => null)
    finderFiles.set(key, finderFile)
  }
  const image = finderFiles.get(key) ?? (await findImageFile($, dir, number))
  if (image === null) return null

  const preview = await makePreview($, dir, number, image).catch(() => null)
  if (preview !== null) previews.set(key, preview)
  return preview
}

async function refresh($: EngineInterface) {
  const { text } = await $.prompt.read()
  const numbers = imageNumbersIn(text)

  const next: PastedImage[] = []
  for (const number of numbers) {
    const preview = await previewFor($, number)
    if (preview !== null) next.push(preview)
  }

  const current = await read($, images)
  const toKey = (list: PastedImage[]) => list.map(image => image.number).join(',')
  const isUnchanged = toKey(current) === toKey(next)
  if (!isUnchanged) await update($, images, () => next)
}

function imageNumbersIn(text: string): number[] {
  const numbers = [...text.matchAll(IMAGE_PLACEHOLDER)].map(match => Number(match[1]))
  return [...new Set(numbers)]
}

// What Claude reads beside the prompt: for each pasted Finder icon, where the real image is.
async function finderFileNotes($: EngineInterface, text: string): Promise<string[]> {
  const dir = await currentImagesDir($)
  if (dir === null) return []

  const notes: string[] = []
  for (const number of imageNumbersIn(text)) {
    const finderFile = finderFiles.get(`${dir}/${number}`)
    if (typeof finderFile !== 'string') continue
    notes.push(
      `[Image #${number}] is only Finder's icon for a copied file, not the picture itself. The real image is ${finderFile}; read that file to see it.`,
    )
  }
  return notes
}

async function refreshOnce($: EngineInterface) {
  if (isRefreshing) return
  isRefreshing = true
  try {
    await refresh($)
  } finally {
    isRefreshing = false
  }
}

export const register: Register = on => {
  on('session.start', ($, e, next) => {
    $.clock.every(POLL_MS, () => refreshOnce($).catch(() => {}))
    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    await update($, images, () => [])
    const notes = await finderFileNotes($, e.text)
    if (notes.length === 0) return next(e)

    return next({ ...e, context: [...(e.context ?? []), ...notes] })
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const pasted = await read($, images)
    const isQuiet = e.props.hasSurvey || pasted.length === 0
    if (isQuiet || e.surface !== 'terminal') return next(e)

    const { Box, Image, Raster, Text } = $.ui.resolve(e)
    // Whatever else draws in this band (another plugin's status row) stays, under the thumbnails.
    const below = await next(e)

    return (
      <Box flexDirection="column">
        <Box flexDirection="row" columnGap={1}>
          {pasted.map(image => {
            const label = `#${image.number}`
            const pictureOf = ({ number, columns, rows, picture }: PastedImage) => {
              const key = `image-${number}`
              if (picture === null) return <Text dimColor>no preview</Text>
              if ('file' in picture) {
                const source = { file: picture.file, format: 'png' as const }
                return <Image key={key} source={source} columns={columns} rows={rows} alt={`[Image #${number}]`} />
              }
              return <Raster key={key} columns={columns} rows={rows} cells={picture.cells} />
            }
            return (
              <Box flexDirection="column" alignItems="center" borderStyle="round" borderDimColor>
                {pictureOf(image)}
                <Text dimColor>{label}</Text>
              </Box>
            )
          })}
        </Box>
        {below}
      </Box>
    )
  })
}
