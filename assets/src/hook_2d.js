// Phoenix LiveView hook: the 2D dice "engine". Same contract as the 3D hook
// (assets/src/hook.js) — it owns the .dicex-stage element, listens for the
// "dic_ex:roll" event pushed by DicExWeb.DiceRoller, tumbles the dice in 2D,
// and pushes "dic_ex:settled" back once every die stops so the LiveComponent
// reveals the authoritative Elixir result in sync.
//
// The visible "roll" is pure theatre: faces flip through random values with an
// ease-out cadence (fast, then slowing) and land exactly on the value Elixir
// already decided. The randomness you see is cosmetic; the truth is the server
// roll — identical to how the 3D engine treats the tumbling dice.

import { drawDieFaceCanvas } from "./pixel_textures.js"

const TUMBLE_MS = 1500 // total spin; tuned to feel like the 3D physical settle
const FACE_PX = 64 // matches pixel_textures FACE_PX; upscaled via CSS

const DiceRoller2DHook = {
  mounted() {
    this._id = this.el.id
    this._setup()
    this.handleEvent(`dic_ex:roll:${this._id}`, (payload) => this._roll(payload))
    this.handleEvent(`dic_ex:error:${this._id}`, (payload) => this._error(payload))
  },

  destroyed() {
    this._stopTumble()
  },

  _setup() {
    this._stage =
      this.el.querySelector("[data-dicex-stage]") || this.el
    this._theme = this._readPalette()
    this._tumble = null
    this._raf = null
    // bind the rAF callback once and reuse it. _stopTumble must NOT null this
    // (nulling it then calling .bind again caused the
    // "Cannot read properties of null (reading 'bind')" crash on every roll).
    this._boundTick = this._tick.bind(this)
    this._spawnIdle()
  },

  // The palette ships from Elixir as JSON in data-palette (a custom theme map
  // or a built-in name). Falls back to "obsidian" if absent.
  _readPalette() {
    const raw = this.el.dataset.palette
    return raw ? JSON.parse(raw) : "obsidian"
  },

  // Static dice placed on the stage before the first roll so it's never empty.
  _spawnIdle() {
    this._clearStage()
    const layout = [
      { sides: 20, value: 20 },
      { sides: 6, value: 6 },
      { sides: 8, value: 8 }
    ]
    for (const entry of layout) this._makeDie(entry.sides, entry.value, true)
  },

  _clearStage() {
    if (!this._stage) return
    for (const node of this._stage.querySelectorAll("[data-dicex-die]")) {
      node.remove()
    }
  },

  // Build one die DOM node (a tile wrapping a canvas) and append it.
  _makeDie(sides, value, kept) {
    const wrap = document.createElement("div")
    wrap.className = "dicex-die2d"
    wrap.dataset.dicexDie = "1"
    wrap.dataset.sides = String(sides)
    if (kept === false) wrap.classList.add("dicex-dropped")

    const canvas = document.createElement("canvas")
    canvas.width = FACE_PX
    canvas.height = FACE_PX
    canvas.className = "dicex-die2d-canvas"
    this._paint(canvas, value, sides)
    wrap.appendChild(canvas)

    this._stage.appendChild(wrap)
    return { wrap, canvas }
  },

  _paint(canvas, value, sides) {
    // Each die is drawn as its real silhouette (triangle / diamond / hexagon…)
    // so a mixed pool reads as different polyhedrals, not identical tiles.
    const face = drawDieFaceCanvas(value, sides, this._theme)
    const ctx = canvas.getContext("2d")
    ctx.imageSmoothingEnabled = false
    ctx.clearRect(0, 0, FACE_PX, FACE_PX)
    ctx.drawImage(face, 0, 0)
  },

  _randomFace(sides) {
    return 1 + Math.floor(Math.random() * sides)
  },

  _roll(payload) {
    this._stopTumble()
    this._clearStage()

    const dice = []
    for (const group of payload.groups || []) {
      if (!group.sides) continue
      for (const r of group.rolls || []) {
        dice.push({ sides: group.sides, value: r.value, kept: r.kept !== false })
      }
    }
    if (dice.length === 0) return

    this._tumble = dice.map((entry, i) => {
      const { canvas } = this._makeDie(entry.sides, 1, entry.kept)
      return {
        sides: entry.sides,
        value: entry.value,
        canvas,
        done: false,
        // small per-die phase offset so a pool doesn't flip in lockstep
        nextFlipAt: performance.now() + i * 30
      }
    })

    this._tumbleStart = performance.now()
    this._raf = requestAnimationFrame(this._boundTick)
  },

  _tick(now) {
    const t = Math.min(1, (now - this._tumbleStart) / TUMBLE_MS)
    const settled = t >= 1

    for (const d of this._tumble) {
      if (d.done) continue
      if (settled) {
        // final face is always the authoritative value from Elixir
        this._paint(d.canvas, d.value, d.sides)
        d.done = true
      } else if (now >= d.nextFlipAt) {
        this._paint(d.canvas, this._randomFace(d.sides), d.sides)
        // ease-out: flips are frequent at first, then space out (shedding spin)
        const gap = 45 + 300 * t * t + Math.random() * 40
        d.nextFlipAt = now + gap
      }
    }

    if (this._tumble.every((d) => d.done)) {
      this._raf = null
      this._tumble = null
      // tell the LiveComponent every die has stopped -> reveal the result
      this.pushEventTo(this.el, `dic_ex:settled:${this._id}`, {})
      return
    }
    this._raf = requestAnimationFrame(this._boundTick)
  },

  _stopTumble() {
    if (this._raf) cancelAnimationFrame(this._raf)
    this._raf = null
    this._tumble = null
  },

  _error(payload) {
    this.el.dataset.error = payload?.message || "invalid"
  }
}

export default DiceRoller2DHook
