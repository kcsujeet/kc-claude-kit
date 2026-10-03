/**
 * How a thumbnail is drawn: a PNG file the terminal shows itself (kitty graphics), or
 * half-block Raster cells anywhere else; null when no preview could be made.
 */
export type Picture = { file: string } | { cells: string } | null

export type PastedImage = { number: number; columns: number; rows: number; picture: Picture }

declare module 'claude-code' {
  interface PluginState {
    'image-preview': { images: PastedImage[] }
  }
}
