import {
  AdditiveBlending,
  AmbientLight,
  BoxGeometry,
  BufferGeometry,
  CanvasTexture,
  Color,
  ConeGeometry,
  CylinderGeometry,
  DirectionalLight,
  DoubleSide,
  Float32BufferAttribute,
  Group,
  Line,
  LineBasicMaterial,
  LineDashedMaterial,
  Mesh,
  MeshBasicMaterial,
  MeshStandardMaterial,
  PerspectiveCamera,
  PlaneGeometry,
  PointLight,
  Points,
  PointsMaterial,
  QuadraticBezierCurve3,
  Quaternion,
  RingGeometry,
  Scene,
  SphereGeometry,
  SRGBColorSpace,
  Vector3,
  WebGLRenderer,
} from "../vendor/three/three.module.min.js"

const UP = new Vector3(0, 1, 0)

const PAD_X = -3.05
const PAD_TOP = 0.1
const ESCAPE_Y = 7.05
const SURFACE_RADIUS = 34
const SURFACE_TOP = -0.35

const CAMERA_BASE = new Vector3(0.3, 3.5, 11.6)
const CAMERA_LOOK = new Vector3(0.3, 3.4, 0)

const PALETTES = {
  earth: {
    groundNear: 0x070d18,
    groundFar: 0x1d3a66,
    atmosphere: 0x3b82f6,
    light: 0x9dc1ff,
  },
  moon: {
    groundNear: 0x0b0e14,
    groundFar: 0x39414f,
    atmosphere: 0x94a3b8,
    light: 0xd7e1ec,
  },
  mars: {
    groundNear: 0x140a08,
    groundFar: 0x5c2a16,
    atmosphere: 0xfb923c,
    light: 0xffc09a,
  },
}

const PHASE_LABELS = {
  hold: "Pre-launch",
  ignition: "Ignition",
  misfire: "Ignition failure",
  ascent: "Powered ascent",
  coast: "Meco · tanks dry",
  fall: "Free fall",
  impact: "Impact",
  escape: "Orbit insertion",
  entry: "Entry",
  brake: "Powered descent",
  touchdown: "Touchdown",
  flameout: "Flameout",
  awaiting: "Awaiting plan",
}

const DURATION = {
  hold: 800,
  ignition: 650,
  misfire: 1600,
  escape: 800,
  coast: 800,
  touchdown: 900,
  entry: 700,
  brake: 1900,
}

function clamp01(value) {
  return Math.min(1, Math.max(0, value))
}

function easeInQuad(t) {
  return t * t
}

function easeOutQuad(t) {
  return 1 - (1 - t) * (1 - t)
}

function easeInOut(t) {
  return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2
}

function prefersReducedMotion() {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches
}

// The stage dramatises one manoeuvre: the step that runs the tank dry, or the
// first launch of a plan that completes.
function focusStep(mission) {
  const steps = mission.steps || []
  if (steps.length === 0) return null
  if (mission.failed_index !== null && mission.failed_index !== undefined) {
    return steps[mission.failed_index] || null
  }

  return steps.find((step) => step.action === "launch") || steps[0]
}

function buildProfile(mission) {
  const step = focusStep(mission)
  if (!step) return { mode: "idle", planet: "earth", coverage: 0, success: false, reference: 0 }

  const fallback = step.status === "completed" ? 1 : 0
  const coverage = clamp01(step.coverage == null ? fallback : step.coverage)

  return {
    mode: step.action === "launch" ? "launch" : "land",
    planet: step.planet || "earth",
    coverage,
    success: step.status === "completed",
    reference: step.altitude_reference || 0,
  }
}

function launchFlight(profile) {
  const start = new Vector3(PAD_X + 0.02, PAD_TOP, 0)
  const f = profile.coverage
  // Reach is the share of the full corridor the burn pays for; the gravity
  // turn is shaped by the control point, not by an extra curve on the reach.
  const reach = f

  // A gravity turn: barely downrange at low energy, pitching over hard on a
  // full burn.
  const apogee = new Vector3(
    start.x + 4.5 * reach,
    PAD_TOP + (ESCAPE_Y - PAD_TOP) * reach,
    0
  )

  const control = new Vector3(
    start.x + 0.2 * (apogee.x - start.x),
    start.y + 0.9 * (apogee.y - start.y),
    0
  )

  const height = Math.max(apogee.y - PAD_TOP, 0.02)
  const impact = new Vector3(Math.min(apogee.x + 1 + 2.2 * reach, 4.2), PAD_TOP, 0)

  return {
    kind: "launch",
    start,
    f,
    reach,
    success: profile.success,
    apogee,
    curve: new QuadraticBezierCurve3(start, control, apogee),
    meco: 0.78,
    height,
    impact,
    downrange: impact.x - apogee.x,
  }
}

function landingFlight(profile) {
  const f = profile.coverage
  const start = new Vector3(PAD_X + 0.02, ESCAPE_Y + 1, 0)
  const descentTop = new Vector3(start.x, ESCAPE_Y, 0)
  const pad = new Vector3(start.x, PAD_TOP, 0)
  const cutY = profile.success ? PAD_TOP : PAD_TOP + (descentTop.y - PAD_TOP) * (1 - f)

  return {
    kind: "land",
    start,
    descentTop,
    pad,
    f,
    success: profile.success,
    cut: new Vector3(start.x, cutY, 0),
    impact: new Vector3(start.x + 0.55 + 0.45 * (1 - f), PAD_TOP, 0),
  }
}

function buildFlight(profile) {
  if (profile.mode === "idle") return null
  return profile.mode === "launch" ? launchFlight(profile) : landingFlight(profile)
}

function alongCurve(curve, t, flame) {
  const value = clamp01(t)

  return {
    position: curve.getPoint(value),
    direction: curve.getTangent(value).normalize(),
    flame,
    tilt: 0,
  }
}

function padPose(position) {
  return { position: position.clone(), direction: UP.clone(), flame: 0, tilt: 0 }
}

function sampleFlight(flight, name, t) {
  const u = clamp01(t)

  if (flight.kind === "launch") {
    if (name === "hold") return padPose(flight.start)

    if (name === "ignition") {
      return {
        position: flight.start.clone().add(new Vector3(Math.sin(u * 80) * 0.012 * u, 0, 0)),
        direction: UP.clone(),
        flame: 0.2 + 0.8 * Math.min(1, u * 1.6),
        tilt: 0,
      }
    }

    if (name === "misfire") {
      return {
        position: flight.start.clone(),
        direction: UP.clone(),
        flame: Math.sin(u * 34) > 0.45 ? 0.55 : 0.04,
        tilt: 0,
      }
    }

    if (name === "ascent") {
      const span = flight.success ? 1 : flight.meco
      return alongCurve(flight.curve, Math.pow(u, 1.45) * span, 1)
    }

    if (name === "coast") {
      const pose = alongCurve(flight.curve, flight.meco + (1 - flight.meco) * easeOutQuad(u), 0)
      pose.flame = u < 0.12 && Math.sin(u * 80) > 0.5 ? 0.3 : 0
      return pose
    }

    if (name === "fall") {
      const position = new Vector3(
        flight.apogee.x + flight.downrange * u,
        flight.apogee.y - flight.height * u * u,
        0
      )

      return {
        position,
        direction: new Vector3(flight.downrange, -2 * flight.height * u, 0).normalize(),
        flame: 0,
        tilt: Math.sin(u * 9) * 0.08 * (1 - u),
      }
    }

    if (name === "escape") {
      const tangent = flight.curve.getTangent(1).normalize()

      return {
        position: flight.apogee.clone().add(tangent.clone().multiplyScalar(u * 4.2)),
        direction: tangent,
        flame: 1,
        tilt: 0,
      }
    }

    return {
      position: flight.impact.clone(),
      direction: UP.clone(),
      flame: 0,
      tilt: 0,
      hidden: true,
    }
  }

  if (name === "entry") {
    return {
      position: flight.start.clone().lerp(flight.descentTop, easeInQuad(u)),
      direction: UP.clone(),
      flame: 0.55,
      tilt: 0,
    }
  }

  if (name === "brake") {
    return {
      position: flight.descentTop.clone().lerp(flight.cut, easeOutQuad(u)),
      direction: UP.clone(),
      flame: 1,
      tilt: 0,
    }
  }

  if (name === "coast") {
    return {
      position: flight.cut.clone(),
      direction: UP.clone(),
      flame: 0.25 * (1 - u),
      tilt: 0,
    }
  }

  if (name === "fall") {
    const drop = flight.cut.y - flight.impact.y

    return {
      position: new Vector3(
        flight.cut.x + (flight.impact.x - flight.cut.x) * u,
        flight.cut.y - drop * u * u,
        0
      ),
      direction: UP.clone(),
      flame: 0,
      tilt: Math.sin(u * 12) * 0.12 * (1 - u),
    }
  }

  if (name === "touchdown") {
    return {
      position: flight.pad.clone(),
      direction: UP.clone(),
      flame: Math.max(0, 0.35 * (1 - u * 4)),
      tilt: 0,
    }
  }

  return {
    position: flight.impact.clone(),
    direction: UP.clone(),
    flame: 0,
    tilt: 0,
    hidden: true,
  }
}

function buildTimeline(profile, flight) {
  const phases = []
  let cursor = 0

  const add = (name, duration) => {
    phases.push({ name, start: cursor, duration })
    cursor += duration
  }

  if (profile.mode === "launch") {
    add("hold", DURATION.hold)
    add("ignition", DURATION.ignition)

    if (flight.f <= 0) {
      add("misfire", DURATION.misfire)
    } else if (profile.success) {
      add("ascent", 2400)
      add("escape", DURATION.escape)
    } else {
      add("ascent", 1200 + 1100 * flight.f)
      add("coast", DURATION.coast)
      add("fall", 700 + 700 * flight.f)
      add("impact", 1200)
    }
  } else {
    add("entry", DURATION.entry)
    add("brake", DURATION.brake)

    if (profile.success) {
      add("touchdown", DURATION.touchdown)
    } else {
      add("coast", 500)
      add("fall", 500 + 800 * (1 - flight.f))
      add("impact", 1200)
    }
  }

  return { phases, total: cursor, startedAt: performance.now() }
}

function staticPose(profile, flight) {
  if (!flight) return padPose(new Vector3(PAD_X + 0.02, PAD_TOP, 0))

  if (flight.kind === "launch") {
    if (flight.f <= 0) return padPose(flight.start)
    return alongCurve(flight.curve, 1, 0)
  }

  return { position: flight.cut.clone(), direction: UP.clone(), flame: 0, tilt: 0 }
}

// ---------------------------------------------------------------------------
// Stage pieces
// ---------------------------------------------------------------------------

function createSky() {
  const canvas = document.createElement("canvas")
  canvas.width = 4
  canvas.height = 256
  const context = canvas.getContext("2d")
  const gradient = context.createLinearGradient(0, 0, 0, 256)
  gradient.addColorStop(0, "#02040a")
  gradient.addColorStop(0.45, "#050a14")
  gradient.addColorStop(0.78, "#0a1322")
  gradient.addColorStop(1, "#121e30")
  context.fillStyle = gradient
  context.fillRect(0, 0, 4, 256)

  const texture = new CanvasTexture(canvas)
  texture.colorSpace = SRGBColorSpace

  const plane = new Mesh(
    new PlaneGeometry(80, 44),
    new MeshBasicMaterial({ map: texture, depthWrite: true })
  )
  plane.position.set(0, 9, -26)

  return { plane, texture }
}

function createStars() {
  const count = 720
  const positions = new Float32Array(count * 3)

  for (let i = 0; i < count; i++) {
    positions[i * 3] = (Math.random() - 0.5) * 46
    positions[i * 3 + 1] = Math.random() * 21 - 2
    positions[i * 3 + 2] = -18 - Math.random() * 6
  }

  const geometry = new BufferGeometry()
  geometry.setAttribute("position", new Float32BufferAttribute(positions, 3))

  return new Points(
    geometry,
    new PointsMaterial({
      color: 0xffffff,
      size: 1.5,
      sizeAttenuation: false,
      transparent: true,
      opacity: 0.75,
      depthWrite: false,
    })
  )
}

function createSun() {
  const group = new Group()

  const core = new Mesh(
    new SphereGeometry(0.22, 16, 16),
    new MeshBasicMaterial({ color: 0xfff6e2 })
  )

  const halo = new Mesh(
    new SphereGeometry(1.7, 20, 20),
    new MeshBasicMaterial({
      color: 0xffd9a0,
      transparent: true,
      opacity: 0.06,
      blending: AdditiveBlending,
      depthWrite: false,
    })
  )

  group.add(core, halo)
  group.position.set(-13, 11.5, -18)

  return group
}

function paintSurface(geometry, palette) {
  const position = geometry.attributes.position
  const existing = geometry.attributes.color
  const colors = existing ? existing.array : new Float32Array(position.count * 3)
  const near = new Color(palette.groundNear)
  const far = new Color(palette.groundFar)
  const color = new Color()

  for (let i = 0; i < position.count; i++) {
    const mix = clamp01((6 - position.getZ(i)) / 14)
    color.copy(near).lerp(far, mix)
    colors[i * 3] = color.r
    colors[i * 3 + 1] = color.g
    colors[i * 3 + 2] = color.b
  }

  if (existing) {
    existing.needsUpdate = true
  } else {
    geometry.setAttribute("color", new Float32BufferAttribute(colors, 3))
  }
}

function createPlanet() {
  const geometry = new SphereGeometry(SURFACE_RADIUS, 64, 40)
  const material = new MeshStandardMaterial({
    roughness: 1,
    metalness: 0,
    vertexColors: true,
    emissive: 0x1d3a66,
    emissiveIntensity: 0.16,
  })

  const mesh = new Mesh(geometry, material)
  mesh.position.set(0, SURFACE_TOP - SURFACE_RADIUS, 0)

  return { mesh, geometry, material }
}

function createPad() {
  const group = new Group()
  group.position.set(PAD_X, 0, 0)

  const steel = new MeshStandardMaterial({ color: 0x3b4657, roughness: 0.6, metalness: 0.6 })
  const darkSteel = new MeshStandardMaterial({ color: 0x232c3a, roughness: 0.85, metalness: 0.5 })
  const accent = new MeshBasicMaterial({
    color: 0x38bdf8,
    transparent: true,
    opacity: 0.4,
    blending: AdditiveBlending,
    depthWrite: false,
  })

  const deck = new Mesh(new CylinderGeometry(0.82, 0.94, 0.22, 30), darkSteel)
  deck.position.y = PAD_TOP - 0.11
  group.add(deck)

  const rim = new Mesh(new RingGeometry(0.62, 0.72, 44), accent)
  rim.rotation.x = -Math.PI / 2
  rim.position.y = PAD_TOP + 0.004
  group.add(rim)

  for (let i = 0; i < 4; i++) {
    const angle = (i / 4) * Math.PI * 2 + Math.PI / 4
    const leg = new Mesh(new BoxGeometry(0.1, 0.55, 0.1), steel)
    leg.position.set(Math.cos(angle) * 0.62, PAD_TOP - 0.4, Math.sin(angle) * 0.62)
    group.add(leg)
  }

  const tower = new Group()
  tower.position.x = -0.78

  for (const side of [-0.09, 0.09]) {
    const beam = new Mesh(new BoxGeometry(0.05, 2.4, 0.05), steel)
    beam.position.set(side, 0.9, 0)
    tower.add(beam)
  }

  for (let i = 0; i < 6; i++) {
    const bar = new Mesh(new BoxGeometry(0.23, 0.03, 0.03), steel)
    bar.position.set(0, 0.35 + i * 0.36, 0)
    tower.add(bar)
  }

  const beaconMaterial = new MeshBasicMaterial({ color: 0xff5252, transparent: true })
  const beacon = new Mesh(new SphereGeometry(0.045, 12, 12), beaconMaterial)
  beacon.position.set(0, 2.16, 0)
  tower.add(beacon)
  group.add(tower)

  const armPivot = new Group()
  armPivot.position.set(-0.68, 0.95, 0)

  const arm = new Mesh(new BoxGeometry(0.56, 0.055, 0.055), darkSteel)
  arm.position.x = 0.28
  armPivot.add(arm)

  const clamp = new Mesh(new BoxGeometry(0.06, 0.12, 0.12), steel)
  clamp.position.x = 0.53
  armPivot.add(clamp)
  group.add(armPivot)

  for (const side of [-1.55, 1.45]) {
    const mast = new Mesh(new BoxGeometry(0.05, 1.3, 0.05), steel)
    mast.position.set(side, 0.4, 0.05)
    group.add(mast)

    const lamp = new Mesh(new BoxGeometry(0.18, 0.11, 0.08), accent)
    lamp.position.set(side, 1.06, 0.05)
    group.add(lamp)
  }

  const padLight = new PointLight(0x9dc1ff, 6, 5.5)
  padLight.position.set(0, 1.4, 0.8)
  group.add(padLight)

  return { group, armPivot, beacon, beaconMaterial, accent, padLight }
}

function createShip() {
  const group = new Group()
  group.scale.setScalar(1.45)

  const white = new MeshStandardMaterial({ color: 0xe7edf6, roughness: 0.38, metalness: 0.25 })
  const panel = new MeshStandardMaterial({ color: 0x9aa8bd, roughness: 0.5, metalness: 0.45 })
  const dark = new MeshStandardMaterial({ color: 0x1b2433, roughness: 0.8, metalness: 0.4 })
  const glass = new MeshStandardMaterial({
    color: 0x0f2e4a,
    emissive: 0x38bdf8,
    emissiveIntensity: 1.1,
    roughness: 0.15,
    metalness: 0.6,
  })

  for (let i = 0; i < 3; i++) {
    const angle = (i / 3) * Math.PI * 2
    const bell = new Mesh(new CylinderGeometry(0.035, 0.07, 0.14, 14, 1, true), dark)
    bell.position.set(Math.cos(angle) * 0.055, 0.09, Math.sin(angle) * 0.055)
    group.add(bell)
  }

  const booster = new Mesh(new CylinderGeometry(0.13, 0.145, 0.6, 26), white)
  booster.position.y = 0.46
  group.add(booster)

  for (const y of [0.22, 0.62]) {
    const band = new Mesh(new CylinderGeometry(0.148, 0.148, 0.028, 26), panel)
    band.position.y = y
    group.add(band)
  }

  for (let i = 0; i < 3; i++) {
    const angle = (i / 3) * Math.PI * 2 + Math.PI / 2
    const fin = new Mesh(new BoxGeometry(0.045, 0.3, 0.19), panel)
    fin.position.set(Math.cos(angle) * 0.16, 0.26, Math.sin(angle) * 0.16)
    fin.rotation.y = -angle
    group.add(fin)
  }

  const interstage = new Mesh(new CylinderGeometry(0.135, 0.135, 0.07, 26), dark)
  interstage.position.y = 0.79
  group.add(interstage)

  const upper = new Mesh(new CylinderGeometry(0.115, 0.115, 0.3, 26), white)
  upper.position.y = 0.97
  group.add(upper)

  const windowFrame = new Mesh(new CylinderGeometry(0.045, 0.045, 0.025, 18), panel)
  windowFrame.rotation.x = Math.PI / 2
  windowFrame.position.set(0, 1, 0.112)
  group.add(windowFrame)

  const windowGlass = new Mesh(new CylinderGeometry(0.032, 0.032, 0.03, 18), glass)
  windowGlass.rotation.x = Math.PI / 2
  windowGlass.position.set(0, 1, 0.119)
  group.add(windowGlass)

  const fairing = new Mesh(new ConeGeometry(0.115, 0.4, 26), white)
  fairing.position.y = 1.32
  group.add(fairing)

  const beacon = new Mesh(new SphereGeometry(0.022, 10, 10), glass)
  beacon.position.y = 1.53
  group.add(beacon)

  const legs = new Group()

  for (let i = 0; i < 4; i++) {
    const angle = (i / 4) * Math.PI * 2 + Math.PI / 4
    const leg = new Mesh(new BoxGeometry(0.028, 0.3, 0.028), panel)
    leg.position.set(Math.cos(angle) * 0.2, 0.08, Math.sin(angle) * 0.2)
    leg.rotation.z = -Math.cos(angle) * 0.45
    leg.rotation.x = Math.sin(angle) * 0.45
    legs.add(leg)
  }

  legs.visible = false
  group.add(legs)

  const flame = new Group()

  const plume = (radius, height, color, opacity) => {
    const cone = new Mesh(
      new ConeGeometry(radius, height, 18, 1, true),
      new MeshBasicMaterial({
        color,
        transparent: true,
        opacity,
        blending: AdditiveBlending,
        depthWrite: false,
        side: DoubleSide,
      })
    )
    cone.position.y = -height / 2
    return cone
  }

  flame.add(
    plume(0.115, 0.85, 0xff8a3d, 0.45),
    plume(0.075, 0.6, 0xffb45c, 0.7),
    plume(0.035, 0.34, 0xdcf3ff, 0.95)
  )
  flame.visible = false
  group.add(flame)

  const flameLight = new PointLight(0xff9a4d, 0, 6)
  flameLight.position.y = -0.5
  group.add(flameLight)

  return { group, flame, flameLight, legs, beacon }
}

function createRing(color) {
  return new Mesh(
    new RingGeometry(0.08, 0.14, 48),
    new MeshBasicMaterial({
      color,
      transparent: true,
      opacity: 0,
      side: DoubleSide,
      blending: AdditiveBlending,
      depthWrite: false,
    })
  )
}

function createBurst(options) {
  const positions = new Float32Array(options.count * 3)

  const geometry = new BufferGeometry()
  geometry.setAttribute("position", new Float32BufferAttribute(positions, 3))

  const material = new PointsMaterial({
    color: options.color,
    size: options.size,
    transparent: true,
    opacity: 0,
    depthWrite: false,
    blending: AdditiveBlending,
  })

  const points = new Points(geometry, material)
  points.frustumCulled = false
  points.visible = false

  return {
    points,
    geometry,
    material,
    positions,
    velocities: new Float32Array(options.count * 3),
    count: options.count,
    life: options.life,
    gravity: options.gravity,
    spread: options.spread,
    speed: options.speed,
    rise: options.rise,
    age: 0,
    active: false,
  }
}

function spawnBurst(burst, origin, scale = 1) {
  burst.age = 0
  burst.active = true
  burst.points.visible = true
  burst.material.opacity = 1

  for (let i = 0; i < burst.count; i++) {
    const angle = Math.random() * Math.PI * 2
    const radius = Math.random() * burst.spread
    const velocity = burst.speed * (0.35 + Math.random()) * scale

    burst.positions[i * 3] = origin.x + Math.cos(angle) * radius
    burst.positions[i * 3 + 1] = origin.y + Math.random() * radius * 0.4
    burst.positions[i * 3 + 2] = origin.z + Math.sin(angle) * radius
    burst.velocities[i * 3] = Math.cos(angle) * velocity
    burst.velocities[i * 3 + 1] = (Math.random() * 0.9 + burst.rise) * velocity
    burst.velocities[i * 3 + 2] = Math.sin(angle) * velocity * 0.65
  }

  burst.geometry.attributes.position.needsUpdate = true
}

function updateBurst(burst, delta) {
  if (!burst.active) return

  burst.age += delta
  const progress = burst.age / burst.life

  if (progress >= 1) {
    burst.active = false
    burst.points.visible = false
    return
  }

  for (let i = 0; i < burst.count; i++) {
    burst.velocities[i * 3 + 1] -= burst.gravity * delta
    burst.positions[i * 3] += burst.velocities[i * 3] * delta
    burst.positions[i * 3 + 1] += burst.velocities[i * 3 + 1] * delta
    burst.positions[i * 3 + 2] += burst.velocities[i * 3 + 2] * delta
  }

  burst.geometry.attributes.position.needsUpdate = true
  burst.material.opacity = 1 - progress
}

function createTrail() {
  const max = 480
  const positions = new Float32Array(max * 3)

  const geometry = new BufferGeometry()
  geometry.setAttribute("position", new Float32BufferAttribute(positions, 3))
  geometry.setDrawRange(0, 0)

  const material = new LineBasicMaterial({ color: 0x38bdf8, transparent: true, opacity: 0.85 })
  const line = new Line(geometry, material)
  line.frustumCulled = false

  return { line, geometry, material, positions, count: 0, max }
}

function clearGroup(group) {
  for (const object of group.children.slice()) {
    group.remove(object)
    if (object.geometry) object.geometry.dispose()
    if (object.material) object.material.dispose()
  }
}

// ---------------------------------------------------------------------------
// Scene
// ---------------------------------------------------------------------------

function createScene(root) {
  const canvas = root.querySelector("canvas")
  let renderer

  try {
    renderer = new WebGLRenderer({ canvas, antialias: true })
  } catch (_error) {
    canvas.parentElement.innerHTML =
      '<div class="flex h-full items-center justify-center text-sm text-white/50">' +
      "3D view unavailable on this device.</div>"
    return null
  }

  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2))

  const scene = new Scene()
  scene.background = new Color(0x02040a)

  const camera = new PerspectiveCamera(40, 1, 0.1, 120)
  camera.position.copy(CAMERA_BASE)
  camera.lookAt(CAMERA_LOOK)

  scene.add(new AmbientLight(0x9aa8bd, 0.85))

  const keyLight = new DirectionalLight(0xfff1dc, 2.4)
  keyLight.position.set(-8, 9, 8)
  scene.add(keyLight)

  const rimLight = new DirectionalLight(0x60a5fa, 0.9)
  rimLight.position.set(7, 3, -5)
  scene.add(rimLight)

  const sky = createSky()
  scene.add(sky.plane)
  scene.add(createStars())
  scene.add(createSun())

  const planet = createPlanet()
  scene.add(planet.mesh)

  const pad = createPad()
  scene.add(pad.group)

  const ship = createShip()
  scene.add(ship.group)

  const previewGroup = new Group()
  scene.add(previewGroup)

  const trail = createTrail()
  scene.add(trail.line)

  const impactRing = createRing(0xffb45c)
  const successRing = createRing(0x34d399)
  impactRing.visible = false
  successRing.visible = false
  scene.add(impactRing, successRing)

  const impactFlash = new Mesh(
    new SphereGeometry(0.18, 16, 16),
    new MeshBasicMaterial({
      color: 0xffe6c0,
      transparent: true,
      opacity: 0,
      blending: AdditiveBlending,
      depthWrite: false,
    })
  )
  impactFlash.visible = false
  scene.add(impactFlash)

  const sparks = createBurst({
    count: 120,
    color: 0xffb45c,
    size: 0.11,
    life: 1.1,
    gravity: 5,
    spread: 0.16,
    speed: 4,
    rise: 0.4,
  })

  const dust = createBurst({
    count: 100,
    color: 0xdbe4f0,
    size: 0.42,
    life: 2.2,
    gravity: 0.35,
    spread: 0.42,
    speed: 1.6,
    rise: 0.6,
  })

  scene.add(sparks.points, dust.points)

  const quaternion = new Quaternion()
  const instant = prefersReducedMotion()

  let profile = { mode: "idle", planet: "earth", coverage: 0, success: false }
  let flight = null
  let playback = null
  let activePhase = null
  let destroyed = false
  let shake = 0
  let parallaxTarget = { x: 0, y: 0 }
  let parallax = { x: 0, y: 0 }
  let lastFrame = performance.now()

  const phaseEl = root.querySelector("#scene-phase")
  const altitudeEl = root.querySelector("#scene-altitude")
  const altitudeFill = root.querySelector("#scene-altitude-fill")

  let currentPlanet = null

  function setPlanet(name) {
    if (currentPlanet === name) return
    currentPlanet = name

    const palette = PALETTES[name] || PALETTES.earth
    paintSurface(planet.geometry, palette)
    planet.material.emissive.setHex(palette.atmosphere)
    planet.material.emissiveIntensity = 0.16
    pad.accent.color.setHex(palette.atmosphere)
    pad.padLight.color.setHex(palette.light)
    rimLight.color.setHex(palette.atmosphere)
  }

  function setPhase(label) {
    if (phaseEl) phaseEl.textContent = label
  }

  function setAltitude(y) {
    const fraction = clamp01((y - PAD_TOP) / (ESCAPE_Y - PAD_TOP))
    const altitude = Math.round(fraction * (profile.reference || 0))

    if (altitudeEl) altitudeEl.textContent = `${altitude} km`
    if (altitudeFill) altitudeFill.style.height = `${fraction * 100}%`
  }

  function phaseLabel(name) {
    if (name === "coast") return profile.mode === "land" ? PHASE_LABELS.flameout : PHASE_LABELS.coast
    return PHASE_LABELS[name] || name
  }

  function resize() {
    const width = Math.max(root.clientWidth, 1)
    const height = Math.max(root.clientHeight, 1)
    renderer.setSize(width, height, false)
    camera.aspect = width / height
    camera.updateProjectionMatrix()
  }

  const observer = new ResizeObserver(resize)
  observer.observe(root)
  resize()

  function onPointerMove(event) {
    const rect = root.getBoundingClientRect()
    parallaxTarget = {
      x: ((event.clientX - rect.left) / rect.width - 0.5) * 0.55,
      y: ((event.clientY - rect.top) / rect.height - 0.5) * 0.25,
    }
  }

  function onPointerLeave() {
    parallaxTarget = { x: 0, y: 0 }
  }

  root.addEventListener("pointermove", onPointerMove)
  root.addEventListener("pointerleave", onPointerLeave)

  function addPreviewLine(points, color, opacity, dashSize = 0.16, gapSize = 0.14) {
    const geometry = new BufferGeometry().setFromPoints(points)
    const material = new LineDashedMaterial({
      color,
      dashSize,
      gapSize,
      transparent: true,
      opacity,
    })
    const line = new Line(geometry, material)
    line.computeLineDistances()
    previewGroup.add(line)
  }

  function clearPreview() {
    clearGroup(previewGroup)
    impactRing.visible = false
    successRing.visible = false
    impactFlash.visible = false
  }

  function drawLaunchPreview() {
    if (flight.f <= 0) return

    addPreviewLine(flight.curve.getPoints(64), 0x38bdf8, 0.45, 0.18, 0.16)

    if (flight.success) return

    const fallPoints = []

    for (let i = 0; i <= 32; i++) {
      const u = i / 32
      fallPoints.push(
        new Vector3(
          flight.apogee.x + flight.downrange * u,
          flight.apogee.y - flight.height * u * u,
          0
        )
      )
    }

    addPreviewLine(fallPoints, 0xef4444, 0.6, 0.12, 0.1)
    addApogeeMarker(flight.apogee)
  }

  function drawLandingPreview() {
    addPreviewLine([flight.descentTop, flight.cut], 0x38bdf8, 0.5)

    if (flight.success) return

    addPreviewLine([flight.cut, flight.impact], 0xef4444, 0.6, 0.12, 0.1)
    addApogeeMarker(flight.cut)
  }

  function addApogeeMarker(point) {
    addPreviewLine(
      [new Vector3(-5.6, point.y, 0), new Vector3(5.6, point.y, 0)],
      0xf59e0b,
      0.12,
      0.14,
      0.16
    )

    addPreviewLine(
      [new Vector3(point.x - 0.9, point.y, 0), new Vector3(point.x + 0.9, point.y, 0)],
      0xf59e0b,
      0.5,
      0.06,
      0.06
    )

    const marker = new Mesh(
      new RingGeometry(0.06, 0.09, 32),
      new MeshBasicMaterial({
        color: 0xf59e0b,
        transparent: true,
        opacity: 0.75,
        side: DoubleSide,
        blending: AdditiveBlending,
        depthWrite: false,
      })
    )
    marker.position.copy(point)
    marker.lookAt(camera.position)
    previewGroup.add(marker)
  }

  function resetTrail() {
    trail.count = 0
    trail.geometry.setDrawRange(0, 0)
  }

  function pushTrail(position, color) {
    if (trail.count >= trail.max) return

    if (trail.count > 0) {
      const index = (trail.count - 1) * 3
      const distance = Math.hypot(
        position.x - trail.positions[index],
        position.y - trail.positions[index + 1],
        position.z - trail.positions[index + 2]
      )

      if (distance < 0.035) return
    }

    const index = trail.count * 3
    trail.positions[index] = position.x
    trail.positions[index + 1] = position.y
    trail.positions[index + 2] = position.z
    trail.count += 1

    trail.geometry.setDrawRange(0, trail.count)
    trail.geometry.attributes.position.needsUpdate = true
    trail.material.color.setHex(color)
  }

  function applyPose(pose) {
    if (!pose) {
      ship.group.visible = false
      ship.flame.visible = false
      return
    }

    ship.group.position.copy(pose.position)

    if (pose.tilt) {
      ship.group.position.x += Math.sin(pose.tilt) * 0.05
    }

    quaternion.setFromUnitVectors(UP, pose.direction.clone().normalize())
    ship.group.quaternion.copy(quaternion)

    if (pose.tilt) ship.group.rotateZ(pose.tilt)

    ship.group.visible = !pose.hidden
    ship.flame.visible = pose.flame > 0.02 && !pose.hidden
    ship.flame.scale.set(1, 0.85 + pose.flame * 0.35, 1)
    ship.flameLight.intensity = pose.flame * 6
  }

  function showRing(ring, position, progress, maxScale) {
    ring.visible = progress < 1
    ring.position.copy(position)
    ring.lookAt(camera.position)
    ring.scale.setScalar(1 + progress * maxScale)
    ring.material.opacity = 0.9 * (1 - progress)
  }

  function enterPhase(phase) {
    if (phase.name === "impact") {
      shake = 0.6
      spawnBurst(sparks, flight.impact, 1)
      spawnBurst(dust, flight.impact, 1.1)
    }

    if (phase.name === "ignition") {
      spawnBurst(dust, new Vector3(PAD_X, PAD_TOP - 0.05, 0), 0.7)
    }

    if (phase.name === "touchdown") {
      spawnBurst(dust, new Vector3(PAD_X, PAD_TOP - 0.05, 0), 0.6)
    }
  }

  function setMission(mission) {
    clearPreview()
    resetTrail()

    profile = buildProfile(mission)
    flight = buildFlight(profile)
    activePhase = null
    shake = 0
    playback = null

    for (const burst of [sparks, dust]) {
      burst.active = false
      burst.age = 0
      burst.points.visible = false
      burst.material.opacity = 0
    }

    setPlanet(profile.planet)
    ship.legs.visible = profile.mode === "land"
    ship.flame.visible = false
    ship.beacon.visible = true
    pad.armPivot.rotation.z = profile.mode === "land" ? 0.85 : 0
    ship.group.visible = true

    if (flight) {
      if (flight.kind === "launch") drawLaunchPreview()
      else drawLandingPreview()
    }

    if (!flight) {
      applyPose(padPose(new Vector3(PAD_X + 0.02, PAD_TOP, 0)))
      setPhase(PHASE_LABELS.awaiting)
      setAltitude(PAD_TOP)
      return
    }

    if (instant) {
      const pose = staticPose(profile, flight)
      applyPose(pose)
      setPhase(
        profile.success
          ? flight.kind === "launch"
            ? PHASE_LABELS.escape
            : PHASE_LABELS.touchdown
          : flight.f <= 0
            ? PHASE_LABELS.misfire
            : phaseLabel("coast")
      )
      setAltitude(pose.position.y)
      return
    }

    playback = buildTimeline(profile, flight)
    applyPose(padPose(flight.start || new Vector3(PAD_X, PAD_TOP, 0)))
    setPhase(PHASE_LABELS.hold)
    setAltitude(PAD_TOP)
  }

  function updatePlayback(now, delta) {
    if (!playback) return

    const elapsed = Math.min(now - playback.startedAt, playback.total)
    const phases = playback.phases
    const last = phases[phases.length - 1]

    let phase = last
    for (const candidate of phases) {
      if (elapsed < candidate.start + candidate.duration) {
        phase = candidate
        break
      }
    }

    const localT = clamp01((elapsed - phase.start) / phase.duration)

    if (phase !== activePhase) {
      enterPhase(phase)
      activePhase = phase
    }

    setPhase(phaseLabel(phase.name))

    if (phase.name === "ignition") {
      pad.armPivot.rotation.z = 0.85 * easeInOut(localT)
    } else if (phase.name !== "hold") {
      pad.armPivot.rotation.z = 0.85
    }

    const pose = sampleFlight(flight, phase.name, localT)
    applyPose(pose)
    setAltitude(pose.position.y)

    const trailColor =
      phase.name === "fall" || phase.name === "impact"
        ? 0xef4444
        : phase.name === "coast"
          ? 0xf59e0b
          : 0x38bdf8

    if (phase.name !== "impact" && phase.name !== "touchdown" && phase.name !== "misfire") {
      pushTrail(pose.position, trailColor)
    }

    if (phase.name === "impact") {
      showRing(impactRing, flight.impact, localT, 5)

      const flash = clamp01(localT / 0.22)
      impactFlash.visible = localT < 0.22
      impactFlash.position.copy(flight.impact)
      impactFlash.scale.setScalar(1 + flash * 3.5)
      impactFlash.material.opacity = (1 - flash) * 0.95
    } else {
      impactFlash.visible = false
    }

    if (phase.name === "touchdown") {
      showRing(successRing, flight.pad, localT, 3)
    }

    if (phase.name === "escape") {
      showRing(successRing, pose.position, localT * 0.6, 2.5)
    }

    if (phase === last && elapsed >= playback.total) {
      if (phase.name === "impact") {
        ship.group.visible = false
        ship.flame.visible = false
      }

      if (phase.name === "escape") {
        ship.group.visible = false
        ship.flame.visible = false
      }

      if (phase.name === "misfire") {
        ship.flame.visible = false
      }
    }

    updateBurst(sparks, delta)
    updateBurst(dust, delta)
  }

  function updateIdle(now) {
    applyPose(padPose(new Vector3(PAD_X + 0.02, PAD_TOP, 0)))

    if (!instant) {
      const puff = Math.sin(now / 1400)

      if (puff > 0.995 && !dust.active) {
        spawnBurst(dust, new Vector3(PAD_X, PAD_TOP, 0), 0.18)
      }
    }

    setPhase(PHASE_LABELS.awaiting)
    setAltitude(PAD_TOP)
    updateBurst(dust, 0.016)
  }

  renderer.setAnimationLoop((now) => {
    if (destroyed) return

    const delta = Math.min((now - lastFrame) / 1000, 0.05)
    lastFrame = now

    if (playback) updatePlayback(now, delta)
    else if (flight) {
      /* static pose already applied */
    } else updateIdle(now)

    pad.beacon.visible = Math.sin(now / 260) > -0.2

    parallax.x += (parallaxTarget.x - parallax.x) * 0.04
    parallax.y += (parallaxTarget.y - parallax.y) * 0.04

    const shakeX = shake > 0 ? Math.sin(now / 18) * 0.05 * shake : 0
    const shakeY = shake > 0 ? Math.cos(now / 21) * 0.04 * shake : 0
    shake = Math.max(0, shake - delta * 1.6)

    camera.position.set(
      CAMERA_BASE.x + parallax.x + shakeX,
      CAMERA_BASE.y + parallax.y + shakeY + Math.sin(now / 9000) * 0.03,
      CAMERA_BASE.z
    )
    camera.lookAt(CAMERA_LOOK)

    planet.mesh.rotation.y += 0.004 * delta

    renderer.render(scene, camera)
  })

  function destroy() {
    destroyed = true
    renderer.setAnimationLoop(null)
    observer.disconnect()

    root.removeEventListener("pointermove", onPointerMove)
    root.removeEventListener("pointerleave", onPointerLeave)

    clearPreview()
    resetTrail()

    scene.traverse((object) => {
      if (object.geometry) object.geometry.dispose()
      if (!object.material) return

      const materials = Array.isArray(object.material) ? object.material : [object.material]
      for (const material of materials) material.dispose()
    })

    sky.texture.dispose()
    renderer.dispose()
  }

  return { setMission, destroy }
}

// ---------------------------------------------------------------------------
// LiveView hook
// ---------------------------------------------------------------------------

export default {
  mounted() {
    this.payload = JSON.parse(this.el.dataset.mission)
    this.view = createScene(this.el)
    if (this.view) this.view.setMission(this.payload)

    this.handleEvent("mission:update", ({ mission }) => this.schedule(mission))
  },

  schedule(mission) {
    clearTimeout(this.timer)

    this.timer = setTimeout(() => {
      if (this.view) this.view.setMission(mission)
    }, 180)
  },

  destroyed() {
    clearTimeout(this.timer)
    if (this.view) this.view.destroy()
    this.view = null
  },
}
