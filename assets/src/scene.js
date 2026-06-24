// The Three.js scene + Rapier physics world that hosts the dice.
//
// Flow: dice spawn with a random tumble, fall under gravity, bounce off the
// floor, and once they're nearly at rest we freeze the body exactly where the
// physics left it. The hook reads the landed face and the server recomputes the
// result from those physics values.

import { buildDie } from "./dice_factory.js"
import { getPalette } from "./pixel_textures.js"

// --- tweakable scene config -------------------------------------------------
// Edit these values first when tuning the 3D view. After changes, rebuild the
// package bundle and copy it into the demo (commands in the assistant summary).

const RENDERER = {
  antialias: false,
  alpha: true,
  maxPixelRatio: 2
}

const CAMERA = {
  fov: 42,
  near: 0.1,
  far: 100,
  position: [0, 9.4, 8.2],
  lookAt: [0, -1.2, -0.6]
}

const FOG = {
  color: 0x14101f,
  near: 12,
  far: 26
}

const LIGHTS = {
  key: {
    color: 0xfff0d0,
    intensity: 1.5,
    position: [5, 9, 4],
    shadowMapSize: 1024,
    shadowCamera: { near: 1, far: 30, left: -8, right: 8, top: 8, bottom: -8 }
  },
  fill: { color: 0x6a5acd, intensity: 0.5, position: [-6, 4, -3] },
  ambient: { color: 0x6a5acd, intensity: 1.1 },
  hemi: { sky: 0xb0a0ff, ground: 0x1a1326, intensity: 0.9 }
}

const PHYSICS = {
  gravity: { x: 0, y: -16, z: 0 },
  fixedDt: 1 / 60,
  maxSubsteps: 5
}

const SETTLE = {
  linSpeed: 0.05, // m/s — below this a die is linearly at rest
  angSpeed: 0.2, // rad/s — below this a die is angularly at rest
  time: 0.12 // seconds of continuous rest before locking
}

const TABLE = {
  floor: {
    halfExtents: [40, 5, 40],
    position: [0, -6.2, 0] // top surface y = -1.2
  },
  // Visible platform is 14x14, but the physical arena is inset so dice cannot
  // settle at front/side edges where the perspective camera cuts them off.
  arena: 5.4,
  wallThickness: 0.5,
  wallHeight: 9,
  wallY: 3.5,
  platform: {
    size: 14,
    height: 0.4,
    y: -1.4,
    color: 0x241a38,
    roughness: 0.95,
    metalness: 0
  },
  grid: {
    size: 14,
    divisions: 14,
    y: -1.19,
    centerColor: 0xb08a3e,
    gridColor: 0x3b2a63,
    opacity: 0.55
  }
}

const DICE_RENDER = {
  scale: 0.85,
  idle: [
    { sides: 20, value: 20, x: -1.6 },
    { sides: 6, value: 6, x: 0 },
    { sides: 8, value: 8, x: 1.6 }
  ]
}

const THROW = {
  spawnY: 5.6,
  spawnYStep: 0.75,
  linearVelocityRange: 5.2,
  angularVelocityRange: 24,
  linearDamping: 0.08,
  angularDamping: 0.045,
  spreadMax: 2.4,
  spreadPerDie: 0.4
}

const COLLIDER = {
  restitution: 0.52,
  friction: 0.68,
  fallbackBallRadius: 0.5
}

export class DiceScene {
  constructor(canvas, THREE, Rapier, theme) {
    this.THREE = THREE
    this.Rapier = Rapier
    this.theme = theme || "obsidian"
    this.dice = []
    this.clock = new THREE.Clock()
    this.onSettled = null // hook sets this; fired once when every rolled die finishes
    this._expectSettle = false
    this._settleReported = false

    this._initRenderer(canvas)
    this._initScene()
    this._initLights()
    this._initPhysics()
    this._loop = this._loop.bind(this)
  }

  setTheme(theme) {
    this.theme = theme || "obsidian"
    this._applyTableTheme()
  }

  _initRenderer(canvas) {
    const THREE = this.THREE
    this.canvas = canvas
    this.renderer = new THREE.WebGLRenderer({
      canvas,
      antialias: RENDERER.antialias,
      alpha: RENDERER.alpha
    })
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, RENDERER.maxPixelRatio))
    this.renderer.shadowMap.enabled = true
    this.renderer.shadowMap.type = THREE.BasicShadowMap
    this.resize()
  }

  _initScene() {
    const THREE = this.THREE
    this.scene = new THREE.Scene()
    const aspect = this.canvas.clientWidth / Math.max(1, this.canvas.clientHeight)
    this.camera = new THREE.PerspectiveCamera(CAMERA.fov, aspect, CAMERA.near, CAMERA.far)
    this.camera.position.set(...CAMERA.position)
    this.camera.lookAt(...CAMERA.lookAt)

    // pixel-art backdrop: a subtle gradient fog gives depth without assets
    this.scene.fog = new THREE.Fog(FOG.color, FOG.near, FOG.far)
    this.scene.background = null
  }

  _initLights() {
    const THREE = this.THREE
    const key = new THREE.DirectionalLight(LIGHTS.key.color, LIGHTS.key.intensity)
    key.position.set(...LIGHTS.key.position)
    key.castShadow = true
    key.shadow.mapSize.set(LIGHTS.key.shadowMapSize, LIGHTS.key.shadowMapSize)
    key.shadow.camera.near = LIGHTS.key.shadowCamera.near
    key.shadow.camera.far = LIGHTS.key.shadowCamera.far
    key.shadow.camera.left = LIGHTS.key.shadowCamera.left
    key.shadow.camera.right = LIGHTS.key.shadowCamera.right
    key.shadow.camera.top = LIGHTS.key.shadowCamera.top
    key.shadow.camera.bottom = LIGHTS.key.shadowCamera.bottom
    this.scene.add(key)

    const fill = new THREE.DirectionalLight(LIGHTS.fill.color, LIGHTS.fill.intensity)
    fill.position.set(...LIGHTS.fill.position)
    this.scene.add(fill)

    this.scene.add(new THREE.AmbientLight(LIGHTS.ambient.color, LIGHTS.ambient.intensity))

    // a hemisphere light lifts the shadows so dark dice stay readable
    const hemi = new THREE.HemisphereLight(LIGHTS.hemi.sky, LIGHTS.hemi.ground, LIGHTS.hemi.intensity)
    this.scene.add(hemi)
  }

  _initPhysics() {
    const { Rapier, THREE } = this
    this.world = new Rapier.World(PHYSICS.gravity)
    // fixed timestep, set once; the loop accumulates real dt and runs whole
    // substeps so the simulation is independent of the display refresh rate.
    this.world.timestep = PHYSICS.fixedDt
    this._fixedDt = PHYSICS.fixedDt
    this._accumulator = 0

    // Static geometry MUST be attached to a fixed rigid body for Rapier to
    // collide with it. A bare createCollider(desc) is not enough here.
    const makeStatic = (hx, hy, hz, x, y, z) => {
      const body = this.world.createRigidBody(
        Rapier.RigidBodyDesc.fixed().setTranslation(x, y, z)
      )
      this.world.createCollider(Rapier.ColliderDesc.cuboid(hx, hy, hz), body)
    }

    // thick floor: top surface matches the visible platform top
    makeStatic(...TABLE.floor.halfExtents, ...TABLE.floor.position)
    // Tall invisible walls contain the dice. The visible platform is larger,
    // but the physical arena is inset so dice cannot settle off-camera.
    makeStatic(TABLE.arena, TABLE.wallHeight, TABLE.wallThickness, 0, TABLE.wallY, TABLE.arena)
    makeStatic(TABLE.arena, TABLE.wallHeight, TABLE.wallThickness, 0, TABLE.wallY, -TABLE.arena)
    makeStatic(TABLE.wallThickness, TABLE.wallHeight, TABLE.arena, TABLE.arena, TABLE.wallY, 0)
    makeStatic(TABLE.wallThickness, TABLE.wallHeight, TABLE.arena, -TABLE.arena, TABLE.wallY, 0)

    const platform = new THREE.Mesh(
      new THREE.BoxGeometry(TABLE.platform.size, TABLE.platform.height, TABLE.platform.size),
      new THREE.MeshStandardMaterial({
        color: TABLE.platform.color,
        roughness: TABLE.platform.roughness,
        metalness: TABLE.platform.metalness,
        flatShading: true
      })
    )
    platform.position.set(0, TABLE.platform.y, 0)
    platform.receiveShadow = true
    this._platform = platform
    this.scene.add(platform)

    // bright pixel grid so the floor is unmistakably visible
    const grid = new THREE.GridHelper(
      TABLE.grid.size,
      TABLE.grid.divisions,
      TABLE.grid.centerColor,
      TABLE.grid.gridColor
    )
    grid.position.set(0, TABLE.grid.y, 0)
    grid.material.opacity = TABLE.grid.opacity
    grid.material.transparent = true
    this._grid = grid
    this.scene.add(grid)
    this._applyTableTheme()
  }

  _applyTableTheme() {
    if (!this.THREE) return
    const palette = getPalette(this.theme)
    if (this.scene?.fog) this.scene.fog.color.set(palette.faceEdge)
    if (this._platform) this._platform.material.color.set(palette.faceEdge)
    if (this._grid) {
      this._grid.material.color.set(palette.border)
      this._grid.material.vertexColors = false
      this._grid.material.needsUpdate = true
    }
  }

  // --- spawning -------------------------------------------------------------

  clear() {
    for (const d of this.dice) {
      this._disposeMesh(d.mesh)
      if (d.body) this.world.removeRigidBody(d.body)
    }
    this.dice = []
    this._expectSettle = false
  }

  // Dispose a mesh's GPU resources (geometry + every material + its textures).
  // Without this every roll leaks geometry and per-face CanvasTextures, since
  // Three.js does not GC GPU memory on garbage collection.
  _disposeMesh(mesh) {
    if (!mesh) return
    this.scene?.remove(mesh)
    mesh.geometry?.dispose()
    const mats = Array.isArray(mesh.material) ? mesh.material : [mesh.material]
    for (const m of mats) {
      m.map?.dispose()
      m.dispose()
    }
  }

  // Static dice placed on the stage so the scene is never empty before the
  // first roll. They have no physics body; _step leaves them where they are.
  spawnIdle() {
    const THREE = this.THREE
    this._expectSettle = false
    const faceValuesBySides = (s) => Array.from({ length: s }, (_, i) => i + 1)

    DICE_RENDER.idle.forEach((entry) => {
      const built = buildDie(entry.sides, faceValuesBySides(entry.sides), this.theme, THREE)
      const mesh = built.mesh
      mesh.scale.setScalar(DICE_RENDER.scale)
      mesh.position.set(entry.x, -0.6, 0)
      mesh.quaternion.copy(built.quaternionForValue(entry.value))
      this.scene.add(mesh)
      this.dice.push({ mesh, body: null, settled: true, idle: true })
    })
  }

  // `dice` is [{ sides, value, kept }] — one entry per die to show.
  spawnRoll(dice) {
    this.clear()
    const THREE = this.THREE
    this._expectSettle = true
    this._settleReported = false
    const faceValuesBySides = (s) => {
      if (s === 100) return Array.from({ length: 10 }, (_, i) => (i + 1) * 10)
      return Array.from({ length: s }, (_, i) => i + 1)
    }

    dice.forEach((entry, i) => {
      const built = buildDie(entry.sides, faceValuesBySides(entry.sides), this.theme, THREE)
      const mesh = built.mesh
      mesh.scale.setScalar(DICE_RENDER.scale)
      mesh.castShadow = true
      this.scene.add(mesh)

      const { body: bodyDesc, collider: colliderDesc } = this._makeBody(built, i, dice.length)
      const body = this.world.createRigidBody(bodyDesc)
      this.world.createCollider(colliderDesc, body)

      // Physics-truth engine: the die shows whatever face it lands on. We keep
      // the face table + read direction so we can read the landed value back.
      this.dice.push({
        mesh,
        body,
        settled: false,
        restTime: 0,
        faces: built.faces,
        readDown: entry.sides === 4
      })
    })
  }

  _makeBody(built, index, total) {
    const { Rapier } = this
    const dieScale = DICE_RENDER.scale

    // NOTE: in rapier 0.14 setLinvel takes 3 NUMBERS, but setAngvel takes ONE
    // {x,y,z} vector. Passing 3 numbers to setAngvel silently stores
    // {NaN,NaN,NaN} and the first world.step() poisons the whole body.
    const bodyDesc = Rapier.RigidBodyDesc.dynamic()
      .setTranslation(this._spawnX(index, total), THROW.spawnY + index * THROW.spawnYStep, 0)
      .setLinvel(
        (Math.random() - 0.5) * THROW.linearVelocityRange,
        0,
        (Math.random() - 0.5) * THROW.linearVelocityRange
      )
      .setAngvel({
        x: (Math.random() - 0.5) * THROW.angularVelocityRange,
        y: (Math.random() - 0.5) * THROW.angularVelocityRange,
        z: (Math.random() - 0.5) * THROW.angularVelocityRange
      })
      .setLinearDamping(THROW.linearDamping)
      .setAngularDamping(THROW.angularDamping)

    const colliderDesc = this._colliderFor(built, dieScale)
    return { body: bodyDesc, collider: colliderDesc }
  }

  // Build a collider from the die's actual convex hull so it lands flat on a
  // face and tumbles realistically (a ball collider would spin forever).
  _colliderFor(built, scale) {
    const { Rapier } = this
    const pos = built.mesh.geometry.attributes.position
    const points = new Float32Array(pos.count * 3)

    for (let i = 0; i < pos.count; i++) {
      points[i * 3] = pos.getX(i) * scale
      points[i * 3 + 1] = pos.getY(i) * scale
      points[i * 3 + 2] = pos.getZ(i) * scale
    }

    const desc =
      Rapier.ColliderDesc.convexHull(points) ||
      Rapier.ColliderDesc.ball(COLLIDER.fallbackBallRadius * scale)
    desc.setRestitution(COLLIDER.restitution)
    desc.setFriction(COLLIDER.friction)
    return desc
  }

  _spawnX(index, total) {
    const spread = Math.min(THROW.spreadMax, total * THROW.spreadPerDie)
    return total <= 1 ? 0 : -spread / 2 + (index / (total - 1)) * spread
  }

  // --- simulation -----------------------------------------------------------

  resize() {
    if (!this.canvas) return
    const w = this.canvas.clientWidth
    const h = this.canvas.clientHeight
    this.renderer.setSize(w, h, false)
    if (this.camera) {
      this.camera.aspect = w / Math.max(1, h)
      this.camera.updateProjectionMatrix()
    }
  }

  start() {
    if (this._raf) return
    this.clock.start()
    this._raf = requestAnimationFrame(this._loop)
  }

  stop() {
    if (this._raf) cancelAnimationFrame(this._raf)
    this._raf = null
  }

  dispose() {
    this.stop()
    this.clear()
    this._disposeMesh(this._platform)
    if (this._grid) {
      this.scene.remove(this._grid)
      this._grid.geometry?.dispose()
      this._grid.material?.dispose()
    }
    this.scene = null
    this.renderer.dispose()
    // Release the WebGL context promptly so GPU memory is reclaimed now, not
    // when the canvas is eventually GC'd.
    this.renderer.forceContextLoss?.()
  }

  _loop() {
    this._raf = requestAnimationFrame(this._loop)
    const dt = Math.min(this.clock.getDelta(), 1 / 30)
    this._stepPhysics(dt)
    this._syncMeshes(dt)
    this.renderer.render(this.scene, this.camera)
  }

  // Fixed-timestep integration with an accumulator: the world always advances
  // in 1/60 s chunks no matter the rAF cadence, so a 144 Hz monitor no longer
  // makes the dice fall ~2.4x too fast (nor a stall cause slow-mo).
  _stepPhysics(dt) {
    this._accumulator += dt
    let subs = 0
    while (this._accumulator >= this._fixedDt && subs < PHYSICS.maxSubsteps) {
      this.world.step()
      this._accumulator -= this._fixedDt
      subs++
    }
    if (subs >= PHYSICS.maxSubsteps) this._accumulator = 0 // drop backlog after a long stall
  }

  _syncMeshes(dt) {
    for (const d of this.dice) {
      // idle dice have no physics body — they stay where they were placed
      if (!d.body) continue

      const t = d.body.translation()
      d.mesh.position.set(t.x, t.y, t.z)

      if (!d.settled) {
        d.mesh.quaternion.set(
          d.body.rotation().x,
          d.body.rotation().y,
          d.body.rotation().z,
          d.body.rotation().w
        )
        this._maybeSettle(d, dt)
      }
    }

    // once every rolled die has physically settled, hand control back to the
    // hook so it can read the landed faces and report the real outcome.
    if (
      this._expectSettle &&
      !this._settleReported &&
      this.dice.length > 0 &&
      this.dice.every((d) => d.settled)
    ) {
      this._settleReported = true
      if (this.onSettled) this.onSettled()
    }
  }

  _maybeSettle(d, dt) {
    const lv = d.body.linvel()
    const av = d.body.angvel()
    const lin = Math.hypot(lv.x, lv.y, lv.z)
    const ang = Math.hypot(av.x, av.y, av.z)

    if (lin < SETTLE.linSpeed && ang < SETTLE.angSpeed) {
      d.restTime = (d.restTime || 0) + dt
      if (d.restTime >= SETTLE.time) this._lockAtRest(d)
    } else {
      d.restTime = 0
    }
  }

  _lockAtRest(d) {
    d.settled = true
    // freeze the body so it no longer jitters after the physical roll ends
    d.body.setLinvel({ x: 0, y: 0, z: 0 }, true)
    d.body.setAngvel({ x: 0, y: 0, z: 0 }, true)
    if (typeof d.body.setBodyType === "function") {
      d.body.setBodyType(this.Rapier.RigidBodyType.Fixed, true)
    }
  }

  // Read each rolled die's landed value by finding which of its faces is most
  // aligned with its current resting orientation. `upQuaternion` is the exact
  // orientation that presents a given face toward the read direction (+Y, or
  // the camera for a d4), so the closest upQuaternion == the face that's up.
  readLandedValues() {
    const THREE = this.THREE
    const wc = new THREE.Vector3()

    return this.dice.map((d) => {
      if (!d.faces || d.faces.length === 0) return 1
      // Resolve the landed face by world-space centroid height (lowest for a
      // d4, which reads its resting/bottom face). The centroid is winding-
      // independent, unlike the face normal: the trapezohedron (d10/d100) is
      // built with inward normals, so a normal-based read picked the OPPOSITE
      // face. Centroid height reliably picks the face that's actually on top.
      const wantMax = !d.readDown
      let best = d.faces[0]
      let bestY = wantMax ? -Infinity : Infinity
      for (const f of d.faces) {
        wc.copy(f.centroid).applyQuaternion(d.mesh.quaternion)
        const y = wc.y
        if ((wantMax ? y > bestY : y < bestY)) {
          bestY = y
          best = f
        }
      }
      return best.value
    })
  }
}
