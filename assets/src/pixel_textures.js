// Pixel-art face textures drawn on a canvas with a tiny 3x5 bitmap font.
// Every texture is built procedurally so the package ships zero binary assets
// and the palette can be themed at runtime.

// 3x5 bitmap glyphs for 0-9. Each row is a 3-bit string.
const GLYPHS = {
  "0": ["111", "101", "101", "101", "111"],
  "1": ["010", "110", "010", "010", "111"],
  "2": ["111", "001", "111", "100", "111"],
  "3": ["111", "001", "111", "001", "111"],
  "4": ["101", "101", "111", "001", "001"],
  "5": ["111", "100", "111", "001", "111"],
  "6": ["111", "100", "111", "101", "111"],
  "7": ["111", "001", "010", "010", "010"],
  "8": ["111", "101", "111", "101", "111"],
  "9": ["111", "101", "111", "001", "111"]
}

// Themeable palettes. "obsidian" = dark draconic, "arcane" = parchment/gold,
// "dnd" = leather/brass with parchment dice.
export const THEMES = {
  obsidian: {
    face: "#1a1326",
    faceEdge: "#2d1f44",
    pip: "#e9d8a6",
    pipShadow: "#7a5fae",
    border: "#3b2a63",
    sheen: "#241a38"
  },
  arcane: {
    face: "#f4e4c1",
    faceEdge: "#d9c089",
    pip: "#3b2a63",
    pipShadow: "#9a7bd4",
    border: "#b08a3e",
    sheen: "#fff3d6"
  },
  dnd: {
    face: "#f3e2b3",
    faceEdge: "#8f5b2a",
    pip: "#2b160e",
    pipShadow: "#b98035",
    border: "#9f7635",
    sheen: "#fff1c9"
  }
}

const FACE_PX = 64 // logical texture resolution; upscaled for chunky pixels

// Resolve a theme into a full palette. Accepts a built-in name ("obsidian" /
// "arcane" / "dnd") OR a custom palette object (any subset of keys; merged over the
// obsidian defaults) so hosts can theme the dice without touching the bundle.
export function getPalette(theme) {
  if (theme && typeof theme === "object") return { ...THEMES.obsidian, ...theme }
  return THEMES[theme] || THEMES.obsidian
}

/**
 * Draw a single die face showing `value` onto a fresh canvas and return it.
 * Pure 2D-canvas work (no Three.js), so the 2D engine reuses the exact same
 * pixel-art look as the 3D textures without pulling in WebGL.
 */
export function drawFaceCanvas(value, theme) {
  const palette = getPalette(theme)
  const canvas = document.createElement("canvas")
  canvas.width = FACE_PX
  canvas.height = FACE_PX
  const ctx = canvas.getContext("2d")

  // Base fill with a subtle diagonal sheen for a low-poly look.
  ctx.fillStyle = palette.face
  ctx.fillRect(0, 0, FACE_PX, FACE_PX)

  ctx.fillStyle = palette.sheen
  ctx.beginPath()
  ctx.moveTo(0, 0)
  ctx.lineTo(FACE_PX, 0)
  ctx.lineTo(FACE_PX, FACE_PX * 0.32)
  ctx.lineTo(0, FACE_PX * 0.32)
  ctx.closePath()
  ctx.globalAlpha = 0.35
  ctx.fill()
  ctx.globalAlpha = 1

  // Pixel border frame.
  const b = 4
  drawPixelRect(ctx, b, b, FACE_PX - 2 * b, FACE_PX - 2 * b, palette.faceEdge)

  // Render the value with the bitmap font, centred.
  drawNumber(ctx, String(value), palette)

  return canvas
}

// Silhouette of each polyhedral die as a polygon in unit (0..1) coords, used by
// the 2D engine so every die reads as its real shape instead of a flat tile.
// Vertices are wound clockwise starting at the top.
const DIE_SHAPES = {
  4: [[0.5, 0.1], [0.9, 0.9], [0.1, 0.9]], // tetrahedron -> triangle
  6: [[0.1, 0.1], [0.9, 0.1], [0.9, 0.9], [0.1, 0.9]], // cube -> square
  8: [[0.5, 0.06], [0.94, 0.5], [0.5, 0.94], [0.06, 0.5]], // octahedron -> diamond
  10: [[0.5, 0.06], [0.92, 0.3], [0.74, 0.94], [0.26, 0.94], [0.08, 0.3]], // d10 -> kite
  12: [[0.5, 0.06], [0.94, 0.28], [0.78, 0.94], [0.22, 0.94], [0.06, 0.28]], // dodeca -> pentagon
  20: [[0.26, 0.1], [0.74, 0.1], [0.98, 0.5], [0.74, 0.9], [0.26, 0.9], [0.02, 0.5]] // icosa -> hexagon
}

const DIE_NUMBER_LAYOUTS = {
  // A square-centred 8px glyph touches the transparent corners of the triangle.
  4: { centerY: FACE_PX * 0.64, maxScale: 5 }
}

/**
 * Draw a die face shaped like its real polyhedron (triangle, diamond, hexagon…)
 * with a chunky pixel border and the centred bitmap-font number. The 2D-engine
 * counterpart of `drawFaceCanvas` (which stays square because the 3D renderer
 * maps it onto actual 3D geometry).
 */
export function drawDieFaceCanvas(value, sides, theme) {
  const palette = getPalette(theme)
  const canvas = document.createElement("canvas")
  canvas.width = FACE_PX
  canvas.height = FACE_PX
  const ctx = canvas.getContext("2d")
  ctx.imageSmoothingEnabled = false

  const shape = DIE_SHAPES[sides] || DIE_SHAPES[6]
  const trace = () => {
    ctx.beginPath()
    shape.forEach(([ux, uy], i) =>
      i === 0 ? ctx.moveTo(ux * FACE_PX, uy * FACE_PX) : ctx.lineTo(ux * FACE_PX, uy * FACE_PX)
    )
    ctx.closePath()
  }

  // themed fill + sheen, clipped to the die silhouette
  trace()
  ctx.save()
  ctx.clip()
  ctx.fillStyle = palette.face
  ctx.fillRect(0, 0, FACE_PX, FACE_PX)
  ctx.fillStyle = palette.sheen
  ctx.globalAlpha = 0.35
  ctx.fillRect(0, 0, FACE_PX, FACE_PX * 0.32)
  ctx.globalAlpha = 1
  ctx.restore()

  // chunky pixel border hugging the silhouette
  trace()
  ctx.lineWidth = 4
  ctx.lineJoin = "miter"
  ctx.strokeStyle = palette.faceEdge
  ctx.stroke()

  // centred bitmap-font number
  drawNumber(ctx, String(value), palette, DIE_NUMBER_LAYOUTS[sides])

  return canvas
}

/**
 * Build a THREE.CanvasTexture for a single die face showing `value`.
 * The texture is NearestFilter so the bitmap font stays crisp at any distance.
 */
export function makeFaceTexture(value, themeName, THREE) {
  const canvas = drawFaceCanvas(value, themeName)
  const tex = new THREE.CanvasTexture(canvas)
  tex.magFilter = THREE.NearestFilter // crisp up close (pixel-art)
  tex.minFilter = THREE.NearestMipmapLinearFilter // smooth shimmer at a distance
  tex.generateMipmaps = true
  tex.anisotropy = 4
  tex.colorSpace = THREE.SRGBColorSpace
  return tex
}

function drawPixelRect(ctx, x, y, w, h, fill) {
  ctx.fillStyle = fill
  ctx.fillRect(x, y, w, 2)
  ctx.fillRect(x, y + h - 2, w, 2)
  ctx.fillRect(x, y, 2, h)
  ctx.fillRect(x + w - 2, y, 2, h)
}

function drawNumber(ctx, text, palette, layout = {}) {
  const glyphs = text.split("").map((c) => GLYPHS[c]).filter(Boolean)
  if (glyphs.length === 0) return

  const glyphW = 3
  const glyphH = 5
  const maxScale = layout?.maxScale || 8
  const scale = Math.floor(Math.min(maxScale, FACE_PX / ((glyphs.length * glyphW + (glyphs.length - 1)) + 10)))
  const totalW = glyphs.length * glyphW * scale + (glyphs.length - 1) * scale
  const totalH = glyphH * scale
  const centerX = layout?.centerX ?? FACE_PX / 2
  const centerY = layout?.centerY ?? FACE_PX / 2
  const originX = Math.floor(centerX - totalW / 2)
  const originY = Math.floor(centerY - totalH / 2)

  glyphs.forEach((rows, gi) => {
    const gx = originX + gi * (glyphW * scale + scale)
    rows.forEach((row, ry) => {
      for (let cx = 0; cx < glyphW; cx++) {
        if (row[cx] === "1") {
          const px = gx + cx * scale
          const py = originY + ry * scale
          // drop shadow for depth, then pip colour
          ctx.fillStyle = palette.pipShadow
          ctx.fillRect(px + 1, py + 1, scale, scale)
          ctx.fillStyle = palette.pip
          ctx.fillRect(px, py, scale, scale)
        }
      }
    })
  })
}
