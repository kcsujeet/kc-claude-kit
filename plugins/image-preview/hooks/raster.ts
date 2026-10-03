export type PixelSize = { width: number; height: number }
export type CellSize = { columns: number; rows: number }
export type Raster = CellSize & { cells: string }

const MAX_COLUMNS = 32
const MAX_ROWS = 4
// A terminal cell is about twice as tall as it is wide.
const CELL_ASPECT = 2
const DEFAULT_COLOR = 0x01000000
const OPAQUE_ALPHA = 0x80

const UPPER_HALF_BLOCK = 0x2580

/** The cell box that fits MAX_COLUMNS x MAX_ROWS and keeps the image's shape. */
export function fitCells(size: PixelSize): CellSize {
  const scale = Math.min(MAX_COLUMNS / size.width, (MAX_ROWS * CELL_ASPECT) / size.height)
  const columns = Math.max(1, Math.round(size.width * scale))
  const rows = Math.max(1, Math.round((size.height * scale) / CELL_ASPECT))
  return { columns, rows }
}

/**
 * Turns an uncompressed 24- or 32-bit BMP (what `sips -s format bmp` writes) into Raster
 * cells: one upper-half block per cell, the top pixel as its foreground, the bottom as its
 * background. Returns null for anything else.
 */
export function bmpToRaster(bytes: Uint8Array): Raster | null {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
  const isBmp = bytes.length > 54 && view.getUint16(0, false) === 0x424d
  if (!isBmp) return null

  const pixelOffset = view.getUint32(10, true)
  const width = view.getInt32(18, true)
  const signedHeight = view.getInt32(22, true)
  const bitsPerPixel = view.getUint16(28, true)
  const bytesPerPixel = bitsPerPixel / 8
  const isSupported = bytesPerPixel === 3 || bytesPerPixel === 4
  if (!isSupported || width <= 0) return null

  const height = Math.abs(signedHeight)
  const isTopDown = signedHeight < 0
  const rowStride = Math.ceil((width * bytesPerPixel) / 4) * 4

  const colorAt = (x: number, y: number): number => {
    if (y >= height) return DEFAULT_COLOR
    const fileRow = isTopDown ? y : height - 1 - y
    const at = pixelOffset + fileRow * rowStride + x * bytesPerPixel
    const isTransparent = bytesPerPixel === 4 && view.getUint8(at + 3) < OPAQUE_ALPHA
    if (isTransparent) return DEFAULT_COLOR
    const blue = view.getUint8(at)
    const green = view.getUint8(at + 1)
    const red = view.getUint8(at + 2)
    return (red << 16) | (green << 8) | blue
  }

  const rows = Math.ceil(height / 2)
  const words = new Uint32Array(width * rows * 3)
  for (let row = 0; row < rows; row++) {
    for (let column = 0; column < width; column++) {
      const cell = (row * width + column) * 3
      words[cell] = UPPER_HALF_BLOCK
      words[cell + 1] = colorAt(column, row * 2)
      words[cell + 2] = colorAt(column, row * 2 + 1)
    }
  }

  const cells = bytesToBase64(new Uint8Array(words.buffer))
  return { columns: width, rows, cells }
}

export function base64ToBytes(base64: string): Uint8Array {
  return Uint8Array.from(atob(base64), char => char.charCodeAt(0))
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary)
}
