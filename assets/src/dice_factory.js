// Builds low-poly polyhedral dice with per-face pixel-art textures and the
// quaternion used to present static dice with a chosen value facing up.
//
// Rolling dice are pure cosmetic theatre — the authoritative value comes from
// the Elixir roll shown by the LiveComponent once the physical dice settle.

const FACE_EPS = 0.02 // cosine tolerance for clustering coplanar triangles

import { makeFaceTexture } from "./pixel_textures.js"

// Build everything needed to render and orient one die type.
export function buildDie(sides, values, theme, THREE) {
  const geometry = makeGeometry(sides, THREE)
  const faces = clusterFaces(geometry, THREE, sides)
  assignValues(faces, values, THREE)
  applyFaceGroups(geometry, faces, THREE)
  const material = makeMultiMaterial(faces, theme, THREE)
  const mesh = new THREE.Mesh(geometry, material)
  mesh.castShadow = true

  // Static presentation: d4 is tilted toward the camera, every other die reads
  // the chosen value from the top face (+Y).
  return {
    mesh,
    faces,
    quaternionForValue: (value) => {
      const face = faces.find((f) => f.value === value)
      return face ? face.upQuaternion.clone() : new THREE.Quaternion()
    }
  }
}

// --- geometry ---------------------------------------------------------------

function makeGeometry(sides, THREE) {
  const r = 1
  let geo
  switch (sides) {
    case 4:
      geo = new THREE.TetrahedronGeometry(r, 0)
      break
    case 6:
      // bevelled cube would be nicer but a crisp cube fits the pixel aesthetic
      geo = new THREE.BoxGeometry(r * 1.4, r * 1.4, r * 1.4)
      break
    case 8:
      geo = new THREE.OctahedronGeometry(r * 1.1, 0)
      break
    case 12:
      geo = new THREE.DodecahedronGeometry(r, 0)
      break
    case 20:
      geo = new THREE.IcosahedronGeometry(r, 0)
      break
    case 10:
    case 100:
      geo = makeTrapezohedron(5, THREE)
      break
    default:
      geo = new THREE.IcosahedronGeometry(r, 0)
  }
  // Every downstream stage (face clustering, UVs, material groups, the convex
  // collider) assumes a NON-indexed buffer where each run of 3 vertices is one
  // triangle. The polyhedra already are, but BoxGeometry (the d6) is indexed —
  // flatten everything so the whole pipeline is consistent (no-op when flat).
  return geo.index ? geo.toNonIndexed() : geo
}

// A pentagonal trapezohedron (the classic d10 / d100 shape): two apexes and
// two staggered rings of 5 vertices, forming 10 kite faces. The ring offset is
// derived from the face-planarity condition: each kite must be perfectly flat,
// otherwise its two triangles split into separate faces and the d10 ends up
// with 20 faces / broken value orientation. With s1 = sin(π/n), s2 = sin(2π/n):
//   b/a = (2·s1 − s2) / (s2 + 2·s1)
function makeTrapezohedron(n, THREE) {
  const a = 1.0 // apex half-height
  const R = 1.0 // ring radius
  const s1 = Math.sin(Math.PI / n)
  const s2 = Math.sin((2 * Math.PI) / n)
  const b = (a * (2 * s1 - s2)) / (s2 + 2 * s1)

  const positions = []
  const top = [0, a, 0]
  const bottom = [0, -a, 0]
  const ringA = [] // upper ring, y = +b
  const ringB = [] // lower ring, y = -b, staggered half a step

  for (let i = 0; i < n; i++) {
    const a1 = (i / n) * Math.PI * 2
    const a2 = a1 + Math.PI / n
    ringA.push([Math.cos(a1) * R, b, Math.sin(a1) * R])
    ringB.push([Math.cos(a2) * R, -b, Math.sin(a2) * R])
  }

  for (let i = 0; i < n; i++) {
    const ni = (i + 1) % n
    // upper kite face: top, ringA[i], ringB[i], ringA[ni]
    pushQuad(positions, top, ringA[i], ringB[i], ringA[ni])
    // lower kite face: bottom, ringB[ni], ringA[ni], ringB[i]
    pushQuad(positions, bottom, ringB[ni], ringA[ni], ringB[i])
  }

  const geo = new THREE.BufferGeometry()
  geo.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3))
  geo.computeVertexNormals()
  geo.computeBoundingBox()
  return geo
}

function pushQuad(arr, a, b, c, d) {
  // two triangles per quad
  pushTri(arr, a, b, c)
  pushTri(arr, a, c, d)
}

function pushTri(arr, a, b, c) {
  arr.push(...a, ...b, ...c)
}

// --- face clustering --------------------------------------------------------

// Groups triangles whose normals are ~parallel into logical faces. Returns one
// entry per face with its average normal, centroid, and a list of triangle
// indices into the non-indexed position buffer.
function clusterFaces(geometry, THREE, sides) {
  const pos = geometry.attributes.position
  const triCount = pos.count / 3
  const faces = []

  // Every die is read from its top face (+Y). The d4 rests on a face with a
  // vertex up, so we tilt its value face toward the camera instead of burying
  // it against the floor (where it used to point to -Y and be invisible).
  const topTarget = new THREE.Vector3(0, 1, 0)
  const d4Target = new THREE.Vector3(0, 6.5, 7).normalize()
  const readTop = sides !== 4
  const tmp = new THREE.Vector3()

  for (let t = 0; t < triCount; t++) {
    const a = new THREE.Vector3().fromBufferAttribute(pos, t * 3)
    const b = new THREE.Vector3().fromBufferAttribute(pos, t * 3 + 1)
    const c = new THREE.Vector3().fromBufferAttribute(pos, t * 3 + 2)
    const normal = new THREE.Vector3()
      .subVectors(b, a)
      .cross(new THREE.Vector3().subVectors(c, a))
      .normalize()

    const centroid = new THREE.Vector3().add(a).add(b).add(c).multiplyScalar(1 / 3)

    const existing = faces.find((f) => f.normal.dot(normal) > 1 - FACE_EPS)
    if (existing) {
      existing.triangles.push(t)
      existing._sum.add(centroid)
      existing._sumN.add(normal)
      existing.count++
    } else {
      faces.push({
        triangles: [t],
        normal: normal.clone(),
        _sum: centroid.clone(),
        _sumN: normal.clone(),
        count: 1
      })
    }
  }

  // finalise averages + the quaternion that presents each face toward target
  for (const f of faces) {
    f.centroid = f._sum.clone().divideScalar(f.count)
    f.normal = f._sumN.clone().normalize()
    // Shortest rotation bringing this face's value to the read direction. We do
    // NOT force an in-plane yaw: that would make a stopped die visibly spin on
    // itself just to "straighten" the digit. Minimal rotation only.
    f.upQuaternion = quaternionAlign(f.normal, readTop ? topTarget : d4Target, THREE)
    delete f._sum
    delete f._sumN
  }

  return faces
}

// Quaternion rotating vector `from` onto `to` (shortest arc). Used to bring a
// face's value to the read direction (+Y, or toward the camera for the d4).
function quaternionAlign(from, to, THREE) {
  const q = new THREE.Quaternion()
  q.setFromUnitVectors(from.clone().normalize(), to.clone().normalize())
  return q
}

// --- value assignment -------------------------------------------------------

// Assigns face values honouring the opposite-faces-sum convention where the
// polyhedron has true opposite faces (cube, octa, dodeca, icosa, trapezohedron).
function assignValues(faces, values, THREE) {
  const sorted = [...faces].sort((a, b) => cmpNormal(a.normal, b.normal))
  const used = new Set()
  // opposite faces sum to (min + max): 1+10=11 for a d10, 10+100=110 for a d100
  const sum = values[0] + values[values.length - 1]

  // pair opposites
  for (const f of sorted) {
    if (used.has(f)) continue
    const opp = sorted.find(
      (g) => !used.has(g) && g !== f && g.normal.dot(f.normal) < -1 + FACE_EPS
    )
    assignNextPair(faces, f, opp, values, sum, used)
  }

  // any leftovers (e.g. tetrahedron has no opposites) get sequential values
  for (const f of sorted) {
    if (!("value" in f)) f.value = takeNextValue(values, used)
  }
}

function assignNextPair(faces, f, opp, values, sum, used) {
  const v = takeNextValue(values, used)
  f.value = v
  used.add(f)
  if (opp) {
    opp.value = sum - v
    used.add(opp)
  }
}

function takeNextValue(values, used) {
  for (const v of values) {
    if (!used.has(v)) {
      used.add(v)
      return v
    }
  }
  return values[0]
}

// Stable comparison of normals so clustering is deterministic across reloads.
function cmpNormal(a, b) {
  if (Math.abs(a.y - b.y) > 1e-4) return b.y - a.y
  if (Math.abs(a.x - b.x) > 1e-4) return b.x - a.x
  return b.z - a.z
}

// --- materials + UVs --------------------------------------------------------

function applyFaceGroups(geometry, faces, THREE) {
  geometry.clearGroups()
  const pos = geometry.attributes.position
  const uv = new Float32Array(pos.count * 2)

  faces.forEach((face, matIndex) => {
    for (const t of face.triangles) {
      geometry.addGroup(t * 3, 3, matIndex)
      // project the triangle into the face plane and normalise by its radius
      const a = new THREE.Vector3().fromBufferAttribute(pos, t * 3)
      const b = new THREE.Vector3().fromBufferAttribute(pos, t * 3 + 1)
      const c = new THREE.Vector3().fromBufferAttribute(pos, t * 3 + 2)
      const radius = Math.max(
        a.distanceTo(face.centroid),
        b.distanceTo(face.centroid),
        c.distanceTo(face.centroid)
      )
      // u is negated so the digit frame (right, up) = (-faceU, -faceV) is
      // right-handed with the face normal — otherwise the number renders as a
      // mirror image. (faceU × faceV == +N, so (faceU, -faceV) is left-handed.)
      const u = (v) => 0.5 - v.clone().sub(face.centroid).dot(faceU(face.normal, THREE)) / (radius * 2)
      const w = (v) => 0.5 - v.clone().sub(face.centroid).dot(faceV(face.normal, THREE)) / (radius * 2)
      uv[t * 3 * 2] = u(a)
      uv[t * 3 * 2 + 1] = w(a)
      uv[t * 3 * 2 + 2] = u(b)
      uv[t * 3 * 2 + 3] = w(b)
      uv[t * 3 * 2 + 4] = u(c)
      uv[t * 3 * 2 + 5] = w(c)
    }
  })

  geometry.setAttribute("uv", new THREE.BufferAttribute(uv, 2))
}

// Two in-plane axes for a given face normal — picks a stable tangent frame.
function faceU(normal, THREE) {
  const n = normal
  const ref = Math.abs(n.y) < 0.9 ? new THREE.Vector3(0, 1, 0) : new THREE.Vector3(1, 0, 0)
  return new THREE.Vector3().crossVectors(n, ref).normalize()
}

function faceV(normal, THREE) {
  return new THREE.Vector3().crossVectors(normal, faceU(normal, THREE)).normalize()
}

function makeMultiMaterial(faces, theme, THREE) {
  return faces.map((face) => {
    const tex = makeFaceTexture(face.value, theme, THREE)
    return new THREE.MeshStandardMaterial({
      map: tex,
      roughness: 0.55,
      metalness: 0.05,
      flatShading: true,
      side: THREE.DoubleSide
    })
  })
}
