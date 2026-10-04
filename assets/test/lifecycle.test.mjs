import test from "node:test"
import assert from "node:assert/strict"
import * as THREE from "three"
import Hook from "../src/hook.js"
import Hook2D from "../src/hook_2d.js"
import { DiceScene } from "../src/scene.js"
import { buildDie } from "../src/dice_factory.js"

const frames = new Map(), timers = new Map()
let next = 1
globalThis.requestAnimationFrame = fn => { const id = next++; frames.set(id, fn); return id }
globalThis.cancelAnimationFrame = id => frames.delete(id)
globalThis.setTimeout = fn => { const id = next++; timers.set(id, fn); return id }
globalThis.clearTimeout = id => timers.delete(id)

const context = new Proxy({}, { get: (_, key) => key === "canvas" ? {} : () => {} })
function element() {
  const node = { dataset: {}, style: {}, children: [], classList: { add() {} },
    appendChild(child) { this.children.push(child) },
    remove() { this.removed = true },
    getContext() { return context },
    querySelector(selector) { return selector === "canvas" ? this.children.find(c => c.tag === "canvas") : null },
    querySelectorAll() { return this.children.filter(c => c.dataset?.dicexDie) }
  }
  return node
}
globalThis.document = { hidden: false, addEventListener() {}, removeEventListener() {},
  createElement(tag) { return Object.assign(element(), { tag }) } }
globalThis.window = { addEventListener() {}, removeEventListener() {}, devicePixelRatio: 1 }

function host() {
  const stage = element(), el = element(), events = []
  el.id = "dice"
  el.querySelector = selector => selector === "[data-dicex-stage]" ? stage : null
  const hook = Object.assign(Object.create(Hook), { el, _id: el.id, _destroyed: false,
    pushEventTo(...args) { events.push(args) } })
  return { hook, stage, events }
}
const payload = value => ({ authoritative: true, groups: [{ sides: 20, rolls: [{ value }] }] })

test("loading coalesces to the latest roll without growing the retry queue", () => {
  const { hook } = host(), rolls = []
  hook._roll(payload(3)); hook._roll(payload(18))
  assert.equal(timers.size, 1)
  hook._scene = { spawnRoll(dice, options) { rolls.push({ dice, options }) }, dispose() {} }
  const [id, run] = timers.entries().next().value
  timers.delete(id); run()
  assert.deepEqual(rolls, [{ dice: [{ sides: 20, value: 18, kept: true }], options: { authoritative: true } }])
  assert.equal(timers.size, 0)
  hook.destroyed()
})

test("destroying during loading cancels retries and ignores late roll events", () => {
  const { hook } = host()
  hook._roll(payload(3)); hook.destroyed(); hook._roll(payload(18))
  assert.equal(timers.size, 0)
  assert.equal(hook._pending, null)
})

test("unsupported geometry rolls once in 2D with the exact value, then 3D resumes", () => {
  const { hook, stage, events } = host()
  const canvas = { style: {} }, spawned = []
  hook._canvas = canvas
  let disposed = 0, cleared = 0
  hook._scene = { dispose() { disposed++ }, clear() { cleared++ }, stop() {}, resize() {},
    spawnRoll(dice, options) { spawned.push({ dice, options }) } }
  hook.el.dataset.error = "old"
  hook._roll({ authoritative: true, nonce: 4, groups: [{ sides: 100, rolls: [{ value: 17 }] }] })
  assert.equal(disposed, 0)
  assert.equal(cleared, 1)
  assert.equal(canvas.style.display, "none")
  assert.equal(hook.el.dataset.renderer, "2d")
  assert.equal(hook.el.dataset.error, undefined)
  assert.equal(hook._flat._tumble[0].value, 17)
  assert.equal(stage.children.filter(c => !c.removed).length, 1)
  const [id, finish] = frames.entries().next().value
  frames.delete(id); finish(hook._flat._tumbleStart + 1600)
  assert.deepEqual(events[0].slice(1), ["dic_ex:settled:dice", { nonce: 4 }])

  hook._roll({ ...payload(9), nonce: 5 })
  assert.equal(canvas.style.display, "block")
  assert.equal(hook.el.dataset.renderer, undefined)
  assert.equal(stage.children.filter(c => !c.removed).length, 0)
  assert.equal(spawned.length, 1)
  assert.equal(hook._nonce, 5)
  hook.destroyed()
  assert.equal(frames.size, 0)
})

test("the 3D landed report carries the roll nonce", () => {
  const { hook, events } = host()
  hook._scene = { spawnRoll() {}, readLandedValues: () => [9], dispose() {} }
  hook._roll({ ...payload(9), nonce: 7 })
  hook._reportLanded()
  assert.deepEqual(events[0].slice(1), ["dic_ex:landed:dice", { values: [9], nonce: 7 }])
  hook.destroyed()
})

test("a die that never comes to rest is locked after the settle cap", () => {
  const s = scene()
  s.Rapier = { RigidBodyType: { Fixed: 1 } }
  const moving = { x: 3, y: 0, z: 0 }
  const die = { settled: false, mesh: { quaternion: new THREE.Quaternion() }, finalQuaternion: null,
    body: { linvel: () => moving, angvel: () => moving, setLinvel() {}, setAngvel() {}, setBodyType() {} } }
  for (let i = 0; i < 60 * 4; i++) s._maybeSettle(die, 1 / 60)
  assert.equal(die.settled, false)
  for (let i = 0; i < 60; i++) s._maybeSettle(die, 1 / 60)
  assert.equal(die.settled, true)
})

test("invalid palette recovers and initialization failure drains the pending roll", () => {
  const { hook } = host()
  hook.el.dataset.palette = "{broken"
  hook._initFailed = true
  hook._roll(payload(18))
  assert.equal(hook._fallback._theme, "obsidian")
  assert.equal(hook._fallback._tumble[0].value, 18)
  assert.equal(timers.size, 0)
  hook.destroyed()
  assert.equal(frames.size, 0)
  assert.equal(Hook2D._readPalette.call({ el: hook.el }), "obsidian")
})

function scene() {
  return Object.assign(Object.create(DiceScene.prototype), {
    THREE,
    canvas: { clientWidth: 300, clientHeight: 200 }, clock: { start() {}, getDelta() { return 1 / 60 } },
    dice: [], _loop() {}, _raf: null
  })
}

test("idle, hidden and zero-size scenes schedule no animation; an active roll wakes once", () => {
  const s = scene()
  s.start(); assert.equal(frames.size, 0)
  s.dice = [{ settled: false }]
  s.canvas.clientWidth = 0; s.start(); assert.equal(frames.size, 0)
  s.canvas.clientWidth = 300; document.hidden = true; s.start(); assert.equal(frames.size, 0)
  document.hidden = false; s.start(); s.start(); assert.equal(frames.size, 1)
  s.stop(); assert.equal(frames.size, 0)
})

test("the frame that settles a roll is the last frame", () => {
  const s = scene()
  s._stepPhysics = () => {}
  s._syncMeshes = () => { s.dice[0].settled = true }
  let renders = 0
  s.renderer = { render() { renders++ } }
  s.dice = [{ settled: false }]
  DiceScene.prototype._loop.call(s)
  assert.equal(renders, 1)
  assert.equal(frames.size, 0)
})

test("disposing releases the physics world and WebGL context exactly once", () => {
  const s = scene(), released = []
  s.clear = () => {}; s._disposeMesh = () => {}
  s.renderer = { dispose() { released.push("renderer") }, forceContextLoss() { released.push("context") } }
  s.world = { free() { released.push("physics") } }
  s.dispose(); s.dispose()
  assert.deepEqual(released, ["renderer", "context", "physics"])
  assert.equal(s.world, null)
})

for (const phase of ["context", "renderer", "physics", "table", "cleanup"]) {
  const title = phase === "cleanup"
    ? "a cleanup error preserves the initialization error and releases the remaining resources"
    : `failed ${phase} initialization releases every resource already allocated`
  test(title, () => {
    const failure = new Error(`failed ${phase}`), allocated = [], released = []
    const track = resource => allocated.push(resource)
    class Renderer {
      constructor() {
        if (phase === "context") throw failure
        track("renderer"); track("context"); this.shadowMap = {}
      }
      setPixelRatio() { if (phase === "renderer") throw failure }
      setSize() {}
      dispose() {
        released.push("renderer")
        if (phase === "cleanup") throw new Error("Renderer cleanup failed")
      }
      forceContextLoss() { released.push("context") }
    }
    class PhysicsWorld {
      constructor() { track("physics") }
      createRigidBody() { if (phase === "physics") throw failure; return {} }
      createCollider() {}
      free() { released.push("physics") }
    }
    class PlatformGeometry extends THREE.BoxGeometry {
      constructor(...args) {
        super(...args); track("platform geometry")
        this.addEventListener("dispose", () => released.push("platform geometry"))
      }
    }
    class PlatformMaterial extends THREE.MeshStandardMaterial {
      constructor(...args) {
        super(...args); track("platform material")
        this.addEventListener("dispose", () => released.push("platform material"))
      }
    }
    const graphics = { ...THREE, WebGLRenderer: Renderer, BoxGeometry: PlatformGeometry,
      MeshStandardMaterial: PlatformMaterial,
      GridHelper: class { constructor() { throw failure } }
    }
    const physics = { World: PhysicsWorld,
      RigidBodyDesc: { fixed: () => ({ setTranslation() { return this } }) },
      ColliderDesc: { cuboid: () => ({}) }
    }
    assert.throws(() => new DiceScene({ clientWidth: 300, clientHeight: 200 },
      graphics, physics, "obsidian"), error => error === failure)
    assert.deepEqual(released.sort(), allocated.sort())
    assert.equal(frames.size, 0)
  })
}

test("all supported faces present the requested value, including inward-wound d10", () => {
  for (const sides of [4, 6, 8, 10, 12, 20]) {
    const built = buildDie(sides, Array.from({ length: sides }, (_, i) => i + 1), "obsidian", THREE)
    assert.equal(built.faces.length, sides)
    const target = sides === 4 ? new THREE.Vector3(0, 6.5, 7).normalize() : new THREE.Vector3(0, 1, 0)
    for (const value of Array.from({ length: sides }, (_, i) => i + 1)) {
      const q = built.quaternionForValue(value)
      const visible = built.faces.reduce((best, face) => {
        const height = face.centroid.clone().applyQuaternion(q).dot(target)
        return !best || height > best.height ? { value: face.value, height } : best
      }, null)
      assert.equal(visible.value, value, `d${sides} value ${value}`)
    }
    built.mesh.geometry.dispose()
    built.mesh.material.forEach(m => { m.map.dispose(); m.dispose() })
  }
})

test("authoritative settling aligns body and mesh while default physics preserves orientation", () => {
  const s = scene()
  s.Rapier = { RigidBodyType: { Fixed: 1 } }
  const rotations = []
  const q = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), 1)
  const die = { mesh: { quaternion: new THREE.Quaternion() }, finalQuaternion: q, value: 18,
    body: { setRotation(q) { rotations.push(q) }, setLinvel() {}, setAngvel() {}, setBodyType() {} } }
  s._lockAtRest(die)
  assert.deepEqual(die.mesh.quaternion, q)
  assert.deepEqual(rotations, [q])
  s.dice = [die]; assert.deepEqual(s.readLandedValues(), [18])
  die.finalQuaternion = null
  s._lockAtRest(die)
  assert.equal(rotations.length, 1)
})
