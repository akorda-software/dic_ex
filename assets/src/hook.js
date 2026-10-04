import * as THREE from "three"
import RAPIER from "@dimforge/rapier3d-compat"
import { DiceScene } from "./scene.js"
import DiceRoller2DHook from "./hook_2d.js"

// Phoenix LiveView hook. Register it in your app's hooks object:
//   import DiceRollerHook from "dic_ex"
//   const hooks = { DiceRoller: DiceRollerHook }
//   let liveSocket = new LiveSocket("/live", Socket, { hooks, ... })
//
// The hook owns a <canvas> (the `.dicex-stage` element) and listens for the
// "dic_ex:roll:<id>" event pushed by the DicExWeb.DiceRoller component.

// Geometry the 3D engine renders faithfully. Anything else (d100, d7, d2...)
// is shown in a transient 2D layer for that roll; the next standard roll
// returns to 3D.
const PHYSICAL_SIDES = [4, 6, 8, 10, 12, 20]

function diceOf(payload) {
  const dice = []
  for (const group of payload.groups || []) {
    if (!group.sides) continue
    for (const r of group.rolls || []) {
      dice.push({ sides: group.sides, value: r.value, kept: r.kept !== false })
    }
  }
  return dice
}

async function loadRapier() {
  await RAPIER.init()
  return RAPIER
}

const DiceRollerHook = {
  mounted() {
    this._id = this.el.id
    this._destroyed = false
    this._initFailed = false
    this._setup()
    this.handleEvent(`dic_ex:roll:${this._id}`, (payload) => this._roll(payload))
    this.handleEvent(`dic_ex:error:${this._id}`, (payload) => this._error(payload))
    window.addEventListener("resize", this._resizeHandler = () => this._scene?.resize())
  },

  destroyed() {
    this._destroyed = true
    this._pending = null
    if (this._retryTimer) {
      clearTimeout(this._retryTimer)
      this._retryTimer = null
    }
    window.removeEventListener("resize", this._resizeHandler)
    document.removeEventListener("visibilitychange", this._visibilityHandler)
    this._ro?.disconnect()
    this._scene?.dispose()
    this._fallback?.destroyed()
    this._flat?.destroyed()
    this._scene = null
  },

  async _setup() {
    const stage =
      this.el.querySelector("[data-dicex-stage]") ||
      this.el.querySelector("canvas")?.parentElement ||
      this.el

    // create the canvas once; phx-update="ignore" keeps LiveView from touching it
    let canvas = stage.querySelector("canvas")
    if (!canvas) {
      canvas = document.createElement("canvas")
      canvas.style.width = "100%"
      canvas.style.height = "100%"
      canvas.style.display = "block"
      stage.appendChild(canvas)
    }
    this._canvas = canvas

    try {
      const theme = this.el.dataset.palette ? JSON.parse(this.el.dataset.palette) : "obsidian"
      const rapier = await loadRapier()
      if (this._destroyed || this._fallback) return
      this._scene = new DiceScene(canvas, THREE, rapier, theme)
      // tell the LiveComponent exactly when the dice finish settling, so it can
      // reveal the result in sync with the animation (no fixed timer guess).
      this._scene.onSettled = () => this._reportLanded()
      this._scene.spawnIdle()

      // robust sizing: canvas can be 0x0 before layout settles
      this._ro = new ResizeObserver(() => this._scene?.resize())
      this._ro.observe(stage)
      this._scene.resize()
      this._visibilityHandler = () => {
        if (document.hidden) this._scene?.stop()
        else this._scene?.start()
      }
      document.addEventListener("visibilitychange", this._visibilityHandler)
    } catch (err) {
      if (this._destroyed) return
      this._initFailed = true
      console.error("[dicEx] scene init failed:", err)
      this._use2D()
    }
  },

  _roll(payload) {
    if (this._destroyed) return
    delete this.el.dataset.error
    if (this._fallback) return this._fallback._roll(payload)
    const dice = diceOf(payload)
    if (dice.length === 0) return
    if (dice.some(d => !PHYSICAL_SIDES.includes(d.sides))) return this._roll2D(payload)
    if (!this._scene) {
      // scene still initialising; schedule a single retry (deduped so multiple
      // roll events during the async Rapier load can't fan out into a timer
      // storm) and bail out once the hook is destroyed.
      this._pending = payload
      if (this._initFailed) return this._use2D()
      if (this._retryTimer) return
      this._retryTimer = setTimeout(() => {
        this._retryTimer = null
        if (this._destroyed) return
        if (this._pending) this._roll(this._pending)
      }, 80)
      return
    }
    this._pending = null
    this._hide2D()
    this._nonce = payload.nonce
    this._scene.spawnRoll(dice, { authoritative: payload.authoritative === true })
  },

  // Report the faces that are up. For an authoritative roll these are the
  // server's own values (a plain "settled" signal); in physics mode the server
  // validates them and recomputes the result around them. The nonce lets the
  // server drop reports from a superseded roll.
  _reportLanded() {
    const values = this._scene.readLandedValues()
    this.pushEventTo(this.el, `dic_ex:landed:${this._id}`, { values, nonce: this._nonce })
  },

  _make2D() {
    const flat = Object.assign(Object.create(DiceRoller2DHook), {
      el: this.el, _id: this._id, pushEventTo: this.pushEventTo.bind(this)
    })
    flat._setup()
    return flat
  },

  // One-off 2D roll for geometry the 3D engine can't show exactly. The 3D
  // scene stays alive (hidden) so the next standard roll goes back to it.
  _roll2D(payload) {
    if (this._retryTimer) clearTimeout(this._retryTimer)
    this._retryTimer = null
    this._pending = null
    this._scene?.clear()
    this._scene?.stop()
    if (this._canvas) this._canvas.style.display = "none"
    if (!this._flat) this._flat = this._make2D()
    this.el.dataset.renderer = "2d"
    this._flat._roll(payload)
  },

  _hide2D() {
    if (!this._flat) return
    this._flat._stopTumble()
    this._flat._clearStage()
    if (this._canvas) this._canvas.style.display = "block"
    delete this.el.dataset.renderer
    this._scene?.resize()
  },

  _use2D() {
    if (this._destroyed || this._fallback) return
    if (this._retryTimer) clearTimeout(this._retryTimer)
    this._retryTimer = null
    this._ro?.disconnect()
    this._scene?.dispose()
    this._scene = null
    this._canvas?.remove()
    // reuse a transient 2D layer if one exists; it becomes the permanent one
    this._fallback = this._flat || this._make2D()
    this._flat = null
    this.el.dataset.renderer = "2d"
    const pending = this._pending
    this._pending = null
    if (pending) this._fallback._roll(pending)
  },

  _error(payload) {
    this.el.dataset.error = payload?.message || "invalid"
  }
}

export default DiceRollerHook
