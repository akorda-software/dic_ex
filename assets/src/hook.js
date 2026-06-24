import * as THREE from "three"
import RAPIER from "@dimforge/rapier3d-compat"
import { DiceScene } from "./scene.js"

// Phoenix LiveView hook. Register it in your app's hooks object:
//   import DiceRollerHook from "dic_ex"
//   const hooks = { DiceRoller: DiceRollerHook }
//   let liveSocket = new LiveSocket("/live", Socket, { hooks, ... })
//
// The hook owns a <canvas> (the `.dicex-stage` element) and listens for the
// "dic_ex:roll" event pushed by the DicExWeb.DiceRoller component.

async function loadRapier() {
  await RAPIER.init()
  return RAPIER
}

const DiceRollerHook = {
  mounted() {
    this._id = this.el.id
    this._setup()
    this.handleEvent(`dic_ex:roll:${this._id}`, (payload) => this._roll(payload))
    this.handleEvent(`dic_ex:error:${this._id}`, (payload) => this._error(payload))
    this.handleEvent("dic_ex:theme", (payload) => this._setTheme(payload))
    window.addEventListener("resize", this._resizeHandler = () => this._scene?.resize())
  },

  destroyed() {
    window.removeEventListener("resize", this._resizeHandler)
    this._ro?.disconnect()
    this._scene?.dispose()
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

    const theme = this.el.dataset.palette ? JSON.parse(this.el.dataset.palette) : "obsidian"
    try {
      const rapier = await loadRapier()
      this._scene = new DiceScene(canvas, THREE, rapier, theme)
      // tell the LiveComponent exactly when the dice finish settling, so it can
      // reveal the result in sync with the animation (no fixed timer guess).
      this._scene.onSettled = () => {
        // Physics-truth: report the faces that actually landed up so the server
        // recomputes the result around them and the visual stays honest.
        const values = this._scene.readLandedValues()
        this.pushEventTo(this.el, `dic_ex:landed:${this._id}`, { values })
      }
      this._scene.start()
      this._scene.spawnIdle()

      // robust sizing: canvas can be 0x0 before layout settles
      this._ro = new ResizeObserver(() => this._scene?.resize())
      this._ro.observe(stage)
      this._scene.resize()
    } catch (err) {
      console.error("[dicEx] scene init failed:", err)
    }
  },

  _roll(payload) {
    if (!this._scene) {
      // scene still initialising; retry shortly
      this._pending = payload
      setTimeout(() => this._pending && this._roll(this._pending), 80)
      return
    }
    this._pending = null
    const dice = []
    for (const group of payload.groups || []) {
      if (!group.sides) continue
      for (const r of group.rolls || []) {
        dice.push({ sides: group.sides, value: r.value, kept: r.kept !== false })
      }
    }
    if (dice.length === 0) return
    this._scene.spawnRoll(dice)
  },

  _error(payload) {
    this.el.dataset.error = payload?.message || "invalid"
  },

  _setTheme(payload) {
    // accept a custom palette map or a built-in name; repaint idle dice when idle
    const next = payload?.palette || payload?.theme
    if (!this._scene || !next) return
    this._scene.setTheme(next)
    if (!this._scene._expectSettle) {
      this._scene.clear()
      this._scene.spawnIdle()
    }
  }
}

export default DiceRollerHook
