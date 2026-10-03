import { expect, test } from 'claude-code/testing'

import { base64ToBytes, bmpToRaster, fitCells } from '../hooks/raster'

// A top-down 32-bit BMP, BGRA pixels, as `sips -s format bmp` writes one.
function makeBmp(width: number, pixels: number[][]): Uint8Array {
  const height = pixels.length
  const pixelOffset = 54
  const bytes = new Uint8Array(pixelOffset + width * height * 4)
  const view = new DataView(bytes.buffer)
  view.setUint16(0, 0x424d, false)
  view.setUint32(10, pixelOffset, true)
  view.setInt32(18, width, true)
  view.setInt32(22, -height, true)
  view.setUint16(28, 32, true)
  pixels.flat().forEach((argb, i) => view.setUint32(pixelOffset + i * 4, argb, true))
  return bytes
}

function cellWords(cells: string): number[] {
  return [...new Uint32Array(base64ToBytes(cells).buffer)]
}

const RED = 0xffff0000
const BLUE = 0xff0000ff
const TRANSPARENT = 0x0000ff00
const DEFAULT_COLOR = 0x01000000

test('fitCells keeps a wide screenshot wide', () => {
  expect(fitCells({ width: 1035, height: 277 })).toEqual({ columns: 30, rows: 4 })
})

test('fitCells keeps a tall phone shot tall', () => {
  expect(fitCells({ width: 1170, height: 2532 })).toEqual({ columns: 4, rows: 4 })
})

test('bmpToRaster stacks two pixel rows into one half-block cell row', () => {
  const raster = bmpToRaster(makeBmp(2, [[RED, BLUE], [BLUE, TRANSPARENT]]))

  expect(raster?.columns).toBe(2)
  expect(raster?.rows).toBe(1)
  expect(cellWords(raster?.cells ?? '')).toEqual([0x2580, 0xff0000, 0x0000ff, 0x2580, 0x0000ff, DEFAULT_COLOR])
})

test('bmpToRaster refuses bytes that are not a BMP', () => {
  expect(bmpToRaster(new Uint8Array(64))).toBeNull()
})
