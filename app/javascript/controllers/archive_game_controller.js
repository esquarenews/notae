import { Controller } from "@hotwired/stimulus"
import * as THREE from "three"

const FRAGMENT_COUNT = 7
const PLAYER_SPEED = 8.5
const SENTINEL_SPEED = 0.72
const HAZARD_RADIUS = 1.45
const FRAGMENT_RADIUS = 1.05
const INDEX_RADIUS = 1.75
const SENTINEL_HIT_DAMAGE = 24
const SENTINEL_HIT_COOLDOWN = 0.78
const SENTINEL_KNOCKBACK = 2.2
const LEVEL_SPEED_STEP = 0.1
const PLAYER_LEVEL_SPEED_STEP = 0.035
const LEVEL_INTEGRITY_BONUS = 18
const TOUCH_DRAG_THRESHOLD = 16
const PLAY_BOUNDS = Object.freeze({
  minX: -14.5,
  maxX: 14.5,
  minZ: -16.4,
  maxZ: 14.2
})
const PLAYER_START = Object.freeze({ x: 0, y: 0.82, z: -1.5 })

export default class extends Controller {
  static targets = [
    "canvas",
    "status",
    "level",
    "fragments",
    "integrity",
    "depth",
    "soundButton",
    "screenFlash",
    "eventCue"
  ]
  static values = {
    exitUrl: String
  }

  connect() {
    this.keys = new Set()
    this.clock = new THREE.Clock()
    this.pointer = new THREE.Vector2()
    this.pointerTarget = null
    this.touchMoveVector = new THREE.Vector3()
    this.touchPointerId = null
    this.touchStart = null
    this.touchDragging = false
    this.running = false
    this.gameOver = false
    this.won = false
    this.hitFlash = 0
    this.lastSentinelHitAt = -Infinity
    this.level = 1
    this.soundEnabled = false
    this.audioContext = null
    this.masterGain = null
    this.musicTimer = null
    this.musicStep = 0
    this.feedbackEffects = []
    this.eventCueTimer = null

    this.boundKeydown = (event) => this.handleKeydown(event)
    this.boundKeyup = (event) => this.handleKeyup(event)
    this.boundResize = () => this.resize()
    this.boundPointerdown = (event) => this.handlePointerdown(event)
    this.boundPointermove = (event) => this.handlePointermove(event)
    this.boundPointerup = (event) => this.handlePointerup(event)

    window.addEventListener("keydown", this.boundKeydown)
    window.addEventListener("keyup", this.boundKeyup)
    window.addEventListener("resize", this.boundResize)
    this.canvasTarget.addEventListener("pointerdown", this.boundPointerdown)
    this.canvasTarget.addEventListener("pointermove", this.boundPointermove)
    this.canvasTarget.addEventListener("pointerup", this.boundPointerup)
    this.canvasTarget.addEventListener("pointercancel", this.boundPointerup)

    this.buildScene()
    this.restart()
    this.updateSoundButton()
  }

  disconnect() {
    window.removeEventListener("keydown", this.boundKeydown)
    window.removeEventListener("keyup", this.boundKeyup)
    window.removeEventListener("resize", this.boundResize)
    this.canvasTarget.removeEventListener("pointerdown", this.boundPointerdown)
    this.canvasTarget.removeEventListener("pointermove", this.boundPointermove)
    this.canvasTarget.removeEventListener("pointerup", this.boundPointerup)
    this.canvasTarget.removeEventListener("pointercancel", this.boundPointerup)

    if (this.animationFrame) {
      window.cancelAnimationFrame(this.animationFrame)
      this.animationFrame = null
    }

    this.stopMusic()
    this.audioContext?.close?.()
    this.audioContext = null
    this.masterGain = null
    this.clearEventCue()
    this.clearFeedbackEffects()
    this.disposeScene()
  }

  restart() {
    this.level = 1
    this.integrity = 100
    this.startLevel("Level 1. Recover the lost fragments.")
  }

  startLevel(statusText) {
    this.keys.clear()
    this.pointerTarget = null
    this.touchMoveVector.set(0, 0, 0)
    this.touchPointerId = null
    this.touchStart = null
    this.touchDragging = false
    this.fragmentsCollected = 0
    this.depth = 0
    this.hitFlash = 0
    this.lastSentinelHitAt = -Infinity
    this.gameOver = false
    this.won = false
    this.running = true
    this.clearEventCue()
    this.clearFeedbackEffects()

    this.resetSceneObjects()
    this.randomizeFragments()
    this.randomizeSentinels()
    this.updateHud(statusText)
    this.element.focus({ preventScroll: true })

    if (!this.animationFrame) {
      this.clock.start()
      this.animate()
    }
  }

  buildScene() {
    this.scene = new THREE.Scene()
    this.scene.background = new THREE.Color(0x111413)
    this.scene.fog = new THREE.FogExp2(0x111413, 0.036)

    this.camera = new THREE.PerspectiveCamera(50, 1, 0.1, 180)
    this.camera.position.set(0, 9.5, 13.5)

    this.renderer = new THREE.WebGLRenderer({
      canvas: this.canvasTarget,
      antialias: true,
      alpha: false,
      powerPreference: "high-performance"
    })
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2))
    this.renderer.shadowMap.enabled = true
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap

    this.raycaster = new THREE.Raycaster()
    this.floorPlane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0)

    this.archiveGroup = new THREE.Group()
    this.fragmentGroup = new THREE.Group()
    this.sentinelGroup = new THREE.Group()
    this.feedbackGroup = new THREE.Group()
    this.scene.add(this.archiveGroup, this.fragmentGroup, this.sentinelGroup, this.feedbackGroup)

    this.buildLights()
    this.buildRoom()
    this.buildAtmosphere()
    this.buildPlayer()
    this.buildFragments()
    this.buildSentinels()
    this.buildIndexGate()
    this.resize()
  }

  buildLights() {
    this.scene.add(new THREE.HemisphereLight(0xdbe7df, 0x1b1610, 1.35))

    const keyLight = new THREE.DirectionalLight(0xffe3aa, 2.6)
    keyLight.position.set(-8, 15, 7)
    keyLight.castShadow = true
    keyLight.shadow.mapSize.width = 2048
    keyLight.shadow.mapSize.height = 2048
    keyLight.shadow.camera.near = 1
    keyLight.shadow.camera.far = 40
    keyLight.shadow.camera.left = -24
    keyLight.shadow.camera.right = 24
    keyLight.shadow.camera.top = 24
    keyLight.shadow.camera.bottom = -24
    this.scene.add(keyLight)

    const archiveGlow = new THREE.PointLight(0x46d7a7, 2.2, 28, 1.6)
    archiveGlow.position.set(0, 5, -12)
    this.scene.add(archiveGlow)

    const indexLight = new THREE.PointLight(0xffb84d, 0.6, 18, 2)
    indexLight.position.set(0, 2.8, -17.2)
    this.indexLight = indexLight
    this.scene.add(indexLight)

    this.boundaryLights = []
    const cornerPositions = [
      [PLAY_BOUNDS.minX, 1.1, PLAY_BOUNDS.minZ],
      [PLAY_BOUNDS.maxX, 1.1, PLAY_BOUNDS.minZ],
      [PLAY_BOUNDS.minX, 1.1, PLAY_BOUNDS.maxZ],
      [PLAY_BOUNDS.maxX, 1.1, PLAY_BOUNDS.maxZ]
    ]
    cornerPositions.forEach((position) => {
      const light = new THREE.PointLight(0x82dfbd, 0.48, 7, 1.8)
      light.position.set(position[0], position[1], position[2])
      this.boundaryLights.push(light)
      this.scene.add(light)
    })
  }

  buildRoom() {
    const floorTexture = this.createFloorTexture()
    floorTexture.wrapS = THREE.RepeatWrapping
    floorTexture.wrapT = THREE.RepeatWrapping
    floorTexture.repeat.set(10, 10)

    const floorMaterial = new THREE.MeshStandardMaterial({
      color: 0x1d221f,
      map: floorTexture,
      roughness: 0.72,
      metalness: 0.04,
      emissive: 0x07120f,
      emissiveIntensity: 0.1
    })
    const floor = new THREE.Mesh(new THREE.PlaneGeometry(46, 46, 80, 80), floorMaterial)
    floor.rotation.x = -Math.PI / 2
    floor.receiveShadow = true
    this.archiveGroup.add(floor)

    const gridMaterial = new THREE.LineBasicMaterial({
      color: 0x58756d,
      transparent: true,
      opacity: 0.22
    })
    const grid = new THREE.GridHelper(44, 44, 0x7bbba9, 0x48605a)
    grid.material = gridMaterial
    grid.position.y = 0.015
    this.archiveGroup.add(grid)

    const wallMaterial = new THREE.MeshStandardMaterial({
      color: 0x22201b,
      roughness: 0.86,
      metalness: 0.02
    })
    const backWall = new THREE.Mesh(new THREE.BoxGeometry(46, 13, 0.6), wallMaterial)
    backWall.position.set(0, 6.35, -21)
    backWall.receiveShadow = true
    this.archiveGroup.add(backWall)

    const shelfMaterial = new THREE.MeshStandardMaterial({
      color: 0x3c3126,
      roughness: 0.64,
      metalness: 0.05
    })
    const paperMaterial = new THREE.MeshStandardMaterial({
      color: 0xd9cab2,
      roughness: 0.7,
      metalness: 0.01
    })

    for (let side = -1; side <= 1; side += 2) {
      for (let row = 0; row < 5; row += 1) {
        const shelf = new THREE.Mesh(new THREE.BoxGeometry(2.1, 0.3, 32), shelfMaterial)
        shelf.position.set(side * 20.2, 1.3 + row * 2.2, -3.5)
        shelf.castShadow = true
        shelf.receiveShadow = true
        this.archiveGroup.add(shelf)
      }

      for (let index = 0; index < 34; index += 1) {
        const height = 0.75 + ((index % 5) * 0.16)
        const page = new THREE.Mesh(new THREE.BoxGeometry(0.2, height, 0.85), paperMaterial)
        page.position.set(side * 19.35, 1.05 + (index % 5) * 2.18, -18 + index * 1.05)
        page.rotation.y = side * (Math.PI / 2 + ((index % 3) - 1) * 0.06)
        page.castShadow = true
        this.archiveGroup.add(page)
      }
    }

    const aisleMaterial = new THREE.MeshStandardMaterial({
      color: 0x314841,
      roughness: 0.55,
      metalness: 0.18,
      emissive: 0x0a3229,
      emissiveIntensity: 0.18
    })

    for (let index = 0; index < 9; index += 1) {
      const marker = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.08, 2.6), aisleMaterial)
      marker.position.set(-12 + index * 3, 0.08, 5.5)
      marker.receiveShadow = true
      this.archiveGroup.add(marker)
    }

    this.buildBoundary()
  }

  createFloorTexture() {
    const canvas = document.createElement("canvas")
    canvas.width = 512
    canvas.height = 512
    const context = canvas.getContext("2d")
    context.fillStyle = "#19201c"
    context.fillRect(0, 0, canvas.width, canvas.height)

    for (let y = 0; y < canvas.height; y += 32) {
      const shade = 24 + ((y / 32) % 3) * 6
      context.fillStyle = `rgba(${shade}, ${shade + 18}, ${shade + 12}, 0.28)`
      context.fillRect(0, y, canvas.width, 18)
    }

    context.strokeStyle = "rgba(130, 223, 189, 0.2)"
    context.lineWidth = 2
    for (let line = 0; line <= canvas.width; line += 64) {
      context.beginPath()
      context.moveTo(line, 0)
      context.lineTo(line, canvas.height)
      context.moveTo(0, line)
      context.lineTo(canvas.width, line)
      context.stroke()
    }

    context.strokeStyle = "rgba(248, 211, 138, 0.16)"
    context.lineWidth = 3
    context.strokeRect(46, 46, 420, 420)
    context.strokeRect(118, 118, 276, 276)

    const texture = new THREE.CanvasTexture(canvas)
    texture.colorSpace = THREE.SRGBColorSpace
    return texture
  }

  buildBoundary() {
    this.boundaryGroup = new THREE.Group()
    const width = PLAY_BOUNDS.maxX - PLAY_BOUNDS.minX
    const depth = PLAY_BOUNDS.maxZ - PLAY_BOUNDS.minZ
    const centerX = (PLAY_BOUNDS.minX + PLAY_BOUNDS.maxX) / 2
    const centerZ = (PLAY_BOUNDS.minZ + PLAY_BOUNDS.maxZ) / 2
    const railMaterial = new THREE.MeshStandardMaterial({
      color: 0x79d9bb,
      roughness: 0.34,
      metalness: 0.16,
      emissive: 0x1b725c,
      emissiveIntensity: 0.66
    })
    const panelMaterial = new THREE.MeshBasicMaterial({
      color: 0x7be3c5,
      transparent: true,
      opacity: 0.1,
      side: THREE.DoubleSide,
      depthWrite: false
    })

    const railDepth = 0.12
    const north = new THREE.Mesh(new THREE.BoxGeometry(width, 0.12, railDepth), railMaterial)
    const south = north.clone()
    north.position.set(centerX, 0.14, PLAY_BOUNDS.minZ)
    south.position.set(centerX, 0.14, PLAY_BOUNDS.maxZ)

    const west = new THREE.Mesh(new THREE.BoxGeometry(railDepth, 0.12, depth), railMaterial)
    const east = west.clone()
    west.position.set(PLAY_BOUNDS.minX, 0.14, centerZ)
    east.position.set(PLAY_BOUNDS.maxX, 0.14, centerZ)

    const backPanel = new THREE.Mesh(new THREE.PlaneGeometry(width, 2.6), panelMaterial)
    backPanel.position.set(centerX, 1.3, PLAY_BOUNDS.minZ - 0.02)

    const frontPanel = backPanel.clone()
    frontPanel.position.set(centerX, 1.3, PLAY_BOUNDS.maxZ + 0.02)

    const leftPanel = new THREE.Mesh(new THREE.PlaneGeometry(depth, 2.6), panelMaterial)
    leftPanel.rotation.y = Math.PI / 2
    leftPanel.position.set(PLAY_BOUNDS.minX - 0.02, 1.3, centerZ)

    const rightPanel = leftPanel.clone()
    rightPanel.position.set(PLAY_BOUNDS.maxX + 0.02, 1.3, centerZ)

    this.boundaryGroup.add(north, south, west, east, backPanel, frontPanel, leftPanel, rightPanel)

    const postMaterial = new THREE.MeshStandardMaterial({
      color: 0x2e4f45,
      roughness: 0.42,
      metalness: 0.2,
      emissive: 0x123b32,
      emissiveIntensity: 0.5
    })
    const postGeometry = new THREE.CylinderGeometry(0.13, 0.17, 1.4, 12)
    const postPositions = [
      [PLAY_BOUNDS.minX, PLAY_BOUNDS.minZ],
      [PLAY_BOUNDS.maxX, PLAY_BOUNDS.minZ],
      [PLAY_BOUNDS.minX, PLAY_BOUNDS.maxZ],
      [PLAY_BOUNDS.maxX, PLAY_BOUNDS.maxZ]
    ]
    postPositions.forEach((position) => {
      const post = new THREE.Mesh(postGeometry, postMaterial)
      post.position.set(position[0], 0.7, position[1])
      post.castShadow = true
      this.boundaryGroup.add(post)
    })

    this.archiveGroup.add(this.boundaryGroup)
  }

  buildAtmosphere() {
    const dustCount = 190
    const positions = new Float32Array(dustCount * 3)

    for (let index = 0; index < dustCount; index += 1) {
      positions[index * 3] = THREE.MathUtils.randFloat(PLAY_BOUNDS.minX, PLAY_BOUNDS.maxX)
      positions[index * 3 + 1] = THREE.MathUtils.randFloat(1.4, 8.6)
      positions[index * 3 + 2] = THREE.MathUtils.randFloat(PLAY_BOUNDS.minZ, PLAY_BOUNDS.maxZ)
    }

    const geometry = new THREE.BufferGeometry()
    geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3))
    const material = new THREE.PointsMaterial({
      color: 0xf7e0ad,
      size: 0.035,
      transparent: true,
      opacity: 0.46,
      depthWrite: false
    })

    this.dust = new THREE.Points(geometry, material)
    this.scene.add(this.dust)
  }

  buildPlayer() {
    const material = new THREE.MeshStandardMaterial({
      color: 0x8ee0c2,
      roughness: 0.28,
      metalness: 0.14,
      emissive: 0x1d7a5d,
      emissiveIntensity: 0.42
    })
    const body = new THREE.Mesh(new THREE.IcosahedronGeometry(0.72, 1), material)
    body.castShadow = true
    body.userData.baseEmissiveIntensity = material.emissiveIntensity

    const ring = new THREE.Mesh(
      new THREE.TorusGeometry(0.95, 0.025, 10, 48),
      new THREE.MeshBasicMaterial({ color: 0xbdf6df, transparent: true, opacity: 0.66 })
    )
    ring.rotation.x = Math.PI / 2
    ring.userData.baseOpacity = ring.material.opacity

    const beacon = new THREE.PointLight(0x9df3d7, 1.2, 7, 2)
    beacon.position.set(0, 0.8, 0)

    const shadow = new THREE.Mesh(
      new THREE.CircleGeometry(1.25, 40),
      new THREE.MeshBasicMaterial({ color: 0x0a0e0c, transparent: true, opacity: 0.34, depthWrite: false })
    )
    shadow.rotation.x = -Math.PI / 2
    shadow.position.y = -0.79

    this.player = new THREE.Group()
    this.player.add(body, ring, beacon, shadow)
    this.scene.add(this.player)
  }

  buildFragments() {
    this.fragments = []

    for (let index = 0; index < FRAGMENT_COUNT; index += 1) {
      const fragment = this.createFragment(index)
      fragment.position.set(0, 0.82, 0)
      fragment.userData.homeY = 0.82
      fragment.userData.collected = false
      this.fragments.push(fragment)
      this.fragmentGroup.add(fragment)
    }
  }

  createFragment(index) {
    const canvas = document.createElement("canvas")
    canvas.width = 256
    canvas.height = 256
    const context = canvas.getContext("2d")
    context.fillStyle = index % 2 === 0 ? "#eadfc6" : "#d7e7dc"
    context.fillRect(0, 0, 256, 256)
    context.strokeStyle = "#6d5b43"
    context.lineWidth = 8
    context.strokeRect(18, 18, 220, 220)
    context.fillStyle = "#31443d"
    for (let line = 0; line < 7; line += 1) {
      context.fillRect(44, 58 + line * 22, 112 + ((line + index) % 4) * 18, 6)
    }
    context.fillStyle = "#b8553f"
    context.fillRect(44, 208, 48, 8)

    const texture = new THREE.CanvasTexture(canvas)
    texture.colorSpace = THREE.SRGBColorSpace

    const material = new THREE.MeshStandardMaterial({
      map: texture,
      roughness: 0.62,
      metalness: 0.02,
      emissive: 0x4d3f1c,
      emissiveIntensity: 0.16,
      side: THREE.DoubleSide
    })
    const page = new THREE.Mesh(new THREE.BoxGeometry(1.08, 1.42, 0.045), material)
    page.castShadow = true

    const glow = new THREE.Mesh(
      new THREE.PlaneGeometry(1.58, 1.92),
      new THREE.MeshBasicMaterial({
        color: index % 2 === 0 ? 0xf8d38a : 0x82dfbd,
        transparent: true,
        opacity: 0.18,
        side: THREE.DoubleSide,
        depthWrite: false
      })
    )
    glow.position.z = -0.04

    const fragment = new THREE.Group()
    fragment.add(glow, page)
    fragment.userData.glow = glow
    return fragment
  }

  buildSentinels() {
    this.sentinels = []

    for (let index = 0; index < 3; index += 1) {
      const sentinel = this.createSentinel()
      sentinel.userData.path = this.randomSentinelPath()
      this.sentinels.push(sentinel)
      this.sentinelGroup.add(sentinel)
    }
  }

  createSentinel() {
    const core = new THREE.Mesh(
      new THREE.OctahedronGeometry(0.82, 0),
      new THREE.MeshStandardMaterial({
        color: 0xd95d49,
        roughness: 0.26,
        metalness: 0.18,
        emissive: 0x8d1d14,
        emissiveIntensity: 0.82
      })
    )
    core.castShadow = true

    const halo = new THREE.Mesh(
      new THREE.TorusGeometry(1.25, 0.035, 12, 56),
      new THREE.MeshBasicMaterial({ color: 0xffad8b, transparent: true, opacity: 0.62 })
    )
    halo.rotation.x = Math.PI / 2
    halo.userData.baseOpacity = halo.material.opacity

    const detection = new THREE.Mesh(
      new THREE.RingGeometry(1.15, 1.48, 48),
      new THREE.MeshBasicMaterial({ color: 0xff6f57, transparent: true, opacity: 0.2, side: THREE.DoubleSide })
    )
    detection.rotation.x = -Math.PI / 2
    detection.position.y = -0.7

    const glow = new THREE.PointLight(0xff6a4d, 1.45, 8.5, 2)
    glow.position.set(0, 0.5, 0)

    const sentinel = new THREE.Group()
    sentinel.add(core, halo, detection, glow)
    return sentinel
  }

  buildIndexGate() {
    const frameMaterial = new THREE.MeshStandardMaterial({
      color: 0x5c4a30,
      roughness: 0.42,
      metalness: 0.2,
      emissive: 0x33240d,
      emissiveIntensity: 0.22
    })
    const panelMaterial = new THREE.MeshStandardMaterial({
      color: 0x1f302b,
      roughness: 0.52,
      metalness: 0.08,
      transparent: true,
      opacity: 0.72,
      emissive: 0x123d32,
      emissiveIntensity: 0.35
    })

    this.indexGate = new THREE.Group()
    const left = new THREE.Mesh(new THREE.BoxGeometry(0.34, 5.3, 0.4), frameMaterial)
    const right = left.clone()
    left.position.set(-1.8, 2.65, 0)
    right.position.set(1.8, 2.65, 0)
    const top = new THREE.Mesh(new THREE.BoxGeometry(3.95, 0.34, 0.4), frameMaterial)
    top.position.set(0, 5.22, 0)
    const panel = new THREE.Mesh(new THREE.PlaneGeometry(3.1, 4.2), panelMaterial)
    panel.position.set(0, 2.7, 0.02)

    this.indexGate.add(left, right, top, panel)
    this.indexGate.position.set(0, 0, -18.7)
    this.indexGate.visible = true
    this.scene.add(this.indexGate)
  }

  resetSceneObjects() {
    this.player.position.set(PLAYER_START.x, PLAYER_START.y, PLAYER_START.z)
    this.player.rotation.set(0, 0, 0)
    this.camera.position.set(0, 9.5, 17)
    this.indexGate.scale.set(1, 1, 1)
    this.indexLight.intensity = 0.6

    this.fragments.forEach((fragment) => {
      fragment.visible = true
      fragment.userData.collected = false
      fragment.scale.set(1, 1, 1)
    })
  }

  randomizeFragments() {
    const reserved = [
      this.player.position.clone(),
      new THREE.Vector3(0, 0.82, PLAY_BOUNDS.minZ)
    ]

    this.fragments.forEach((fragment) => {
      const position = this.randomPlayfieldPoint(reserved, 3.2)
      fragment.position.set(position.x, 0.82, position.z)
      fragment.userData.homeY = 0.82
      reserved.push(fragment.position.clone())
    })
  }

  randomizeSentinels() {
    this.sentinels.forEach((sentinel) => {
      sentinel.userData.path = this.randomSentinelPath()
    })
  }

  randomSentinelPath() {
    const radius = this.randomFloat(2.8, 5.1)
    const minX = PLAY_BOUNDS.minX + radius + 1.2
    const maxX = PLAY_BOUNDS.maxX - radius - 1.2
    const minZ = PLAY_BOUNDS.minZ + radius + 1.2
    const maxZ = PLAY_BOUNDS.maxZ - radius - 1.2
    const playerPosition = new THREE.Vector3(PLAYER_START.x, PLAYER_START.y, PLAYER_START.z)

    let center = new THREE.Vector3()
    for (let attempt = 0; attempt < 24; attempt += 1) {
      center = new THREE.Vector3(this.randomFloat(minX, maxX), 0.75, this.randomFloat(minZ, maxZ))
      if (this.horizontalDistance(center, playerPosition) > radius + 3) break
    }

    return {
      center,
      radius,
      phase: Math.random() * Math.PI * 2,
      direction: Math.random() > 0.5 ? 1 : -1
    }
  }

  randomPlayfieldPoint(reservedPositions, minDistance) {
    const margin = 1.4
    let candidate = new THREE.Vector3(0, 0.82, 0)

    for (let attempt = 0; attempt < 60; attempt += 1) {
      candidate = new THREE.Vector3(
        this.randomFloat(PLAY_BOUNDS.minX + margin, PLAY_BOUNDS.maxX - margin),
        0.82,
        this.randomFloat(PLAY_BOUNDS.minZ + margin, PLAY_BOUNDS.maxZ - margin)
      )
      if (reservedPositions.every((position) => this.horizontalDistance(candidate, position) >= minDistance)) {
        return candidate
      }
    }

    return candidate
  }

  randomFloat(min, max) {
    return min + Math.random() * (max - min)
  }

  animate() {
    this.animationFrame = window.requestAnimationFrame(() => this.animate())
    const delta = Math.min(this.clock.getDelta(), 0.04)
    const elapsed = this.clock.elapsedTime

    if (this.running) {
      this.updatePlayer(delta)
      this.updateFragments(elapsed)
      this.updateSentinels(delta, elapsed)
      this.updateIndexGate(delta, elapsed)
      this.updateAtmosphere(delta, elapsed)
      this.updatePlayerEffects(delta, elapsed)
      this.updateCamera(delta)
      this.depth = Math.max(0, Math.round(18 - this.player.position.z))
      this.checkWin()
      this.updateHud()
    } else {
      this.updateFragments(elapsed)
      this.updateIndexGate(delta, elapsed)
      this.updateAtmosphere(delta, elapsed)
      this.updatePlayerEffects(delta, elapsed)
    }

    this.updateFeedbackEffects(delta)
    this.renderer.render(this.scene, this.camera)
  }

  updatePlayer(delta) {
    const movement = new THREE.Vector3()
    if (this.keys.has("w") || this.keys.has("arrowup")) movement.z -= 1
    if (this.keys.has("s") || this.keys.has("arrowdown")) movement.z += 1
    if (this.keys.has("a") || this.keys.has("arrowleft")) movement.x -= 1
    if (this.keys.has("d") || this.keys.has("arrowright")) movement.x += 1

    if (this.touchMoveVector.lengthSq() > 0) {
      movement.add(this.touchMoveVector)
    }

    if (this.pointerTarget) {
      const targetOffset = this.pointerTarget.clone().sub(this.player.position)
      targetOffset.y = 0
      if (targetOffset.length() > 0.4) {
        movement.add(targetOffset.normalize())
      } else {
        this.pointerTarget = null
      }
    }

    if (movement.lengthSq() > 0) {
      movement.normalize()
      this.player.position.addScaledVector(movement, PLAYER_SPEED * this.playerSpeedMultiplier() * delta)
      this.clampPlayerToBounds()
      this.player.rotation.y = Math.atan2(movement.x, movement.z)
    }

    this.clampPlayerToBounds()
    this.player.children[1].rotation.z += delta * 1.8
  }

  updateFragments(elapsed) {
    this.fragments.forEach((fragment, index) => {
      if (fragment.userData.collected) return

      fragment.rotation.y = elapsed * 0.72 + index
      fragment.rotation.z = Math.sin(elapsed * 1.1 + index) * 0.08
      fragment.position.y = fragment.userData.homeY + Math.sin(elapsed * 1.6 + index) * 0.22
      if (fragment.userData.glow) {
        fragment.userData.glow.material.opacity = 0.14 + Math.sin(elapsed * 2.4 + index) * 0.045
      }

      if (fragment.position.distanceTo(this.player.position) < FRAGMENT_RADIUS) {
        const feedbackPosition = fragment.position.clone()
        fragment.userData.collected = true
        fragment.visible = false
        this.fragmentsCollected += 1
        this.playSound("fragment")
        this.showEventCue("collect", "DOCUMENT SECURED")
        this.createWorldFeedback(feedbackPosition, "collect")
        const remaining = FRAGMENT_COUNT - this.fragmentsCollected
        this.updateHud(remaining === 0 ? "The Index is open." : `${remaining} fragments remain.`)
      }
    })
  }

  updateSentinels(delta, elapsed) {
    this.sentinels.forEach((sentinel, index) => {
      const path = sentinel.userData.path
      const angle = elapsed * SENTINEL_SPEED * this.levelSpeedMultiplier() * path.direction * (1 + index * 0.11) + path.phase
      sentinel.position.set(
        path.center.x + Math.cos(angle) * path.radius,
        path.center.y + Math.sin(elapsed * 2 + index) * 0.18,
        path.center.z + Math.sin(angle) * path.radius
      )
      sentinel.rotation.y += delta * 2.4
      sentinel.children[1].rotation.z += delta * 1.7
      sentinel.children[2].rotation.z -= delta * 0.9

      const distance = this.horizontalDistance(sentinel.position, this.player.position)
      const proximity = Math.max(0, 1 - distance / (HAZARD_RADIUS * 2.4))
      sentinel.children[1].material.opacity = 0.44 + proximity * 0.34
      sentinel.children[2].material.opacity = 0.13 + proximity * 0.28
      sentinel.children[3].intensity = 1.2 + proximity * 2.4

      if (distance < HAZARD_RADIUS && !this.gameOver && !this.won) {
        this.triggerSentinelHit(sentinel, elapsed)
      }
    })
  }

  updateIndexGate(delta, elapsed) {
    const open = this.fragmentsCollected >= FRAGMENT_COUNT
    const targetScale = open ? 1.12 : 0.96
    this.indexGate.scale.lerp(new THREE.Vector3(targetScale, targetScale, targetScale), delta * 3)
    this.indexLight.intensity = THREE.MathUtils.lerp(this.indexLight.intensity, open ? 3.8 : 0.6, delta * 3)
    this.indexGate.rotation.y = Math.sin(elapsed * 0.8) * (open ? 0.04 : 0.015)
  }

  updateAtmosphere(delta, elapsed) {
    if (this.dust) {
      this.dust.rotation.y += delta * 0.018
      this.dust.position.y = Math.sin(elapsed * 0.45) * 0.08
    }

    this.boundaryGroup?.children?.forEach((child, index) => {
      if (!child.material?.emissive) return

      child.material.emissiveIntensity = 0.5 + Math.sin(elapsed * 1.6 + index) * 0.12
    })

    this.boundaryLights?.forEach((light, index) => {
      light.intensity = 0.42 + Math.sin(elapsed * 1.9 + index) * 0.11
    })
  }

  updatePlayerEffects(delta, elapsed) {
    this.hitFlash = Math.max(0, this.hitFlash - delta * 2.5)
    const body = this.player.children[0]
    const ring = this.player.children[1]
    const beacon = this.player.children[2]
    const pulse = 0.5 + Math.sin(elapsed * 4.8) * 0.5

    body.material.emissiveIntensity = body.userData.baseEmissiveIntensity + pulse * 0.18 + this.hitFlash * 1.25
    ring.material.opacity = ring.userData.baseOpacity + pulse * 0.14 + this.hitFlash * 0.12
    beacon.intensity = 1.05 + pulse * 0.45 + this.hitFlash * 1.8
  }

  createWorldFeedback(position, kind) {
    if (!this.feedbackGroup) return

    const collect = kind === "collect"
    const ringColor = collect ? 0xf8d38a : 0xff6f57
    const glowColor = collect ? 0x82dfbd : 0xffa05f
    const coreColor = collect ? 0xf8f0d8 : 0xffded2
    const group = new THREE.Group()
    group.position.copy(position)
    group.position.y = 0.08

    const ring = new THREE.Mesh(
      new THREE.RingGeometry(0.82, 1.16, 72),
      new THREE.MeshBasicMaterial({
        color: ringColor,
        transparent: true,
        opacity: collect ? 0.84 : 0.92,
        side: THREE.DoubleSide,
        depthWrite: false
      })
    )
    ring.rotation.x = -Math.PI / 2

    const pulse = new THREE.Mesh(
      new THREE.CircleGeometry(0.58, 48),
      new THREE.MeshBasicMaterial({
        color: coreColor,
        transparent: true,
        opacity: collect ? 0.26 : 0.32,
        side: THREE.DoubleSide,
        depthWrite: false
      })
    )
    pulse.rotation.x = -Math.PI / 2
    pulse.position.y = 0.02

    const beam = new THREE.Mesh(
      new THREE.CylinderGeometry(collect ? 0.22 : 0.36, collect ? 0.72 : 0.95, collect ? 4.8 : 3.7, 32, 1, true),
      new THREE.MeshBasicMaterial({
        color: glowColor,
        transparent: true,
        opacity: collect ? 0.2 : 0.16,
        side: THREE.DoubleSide,
        depthWrite: false
      })
    )
    beam.position.y = collect ? 2.35 : 1.8

    ;[ring, pulse, beam].forEach((mesh) => {
      mesh.userData.baseOpacity = mesh.material.opacity
    })

    group.add(ring, pulse, beam)
    this.feedbackGroup.add(group)
    this.feedbackEffects.push({
      group,
      age: 0,
      duration: collect ? 0.9 : 0.78,
      kind
    })
  }

  updateFeedbackEffects(delta) {
    if (!this.feedbackEffects?.length) return

    this.feedbackEffects = this.feedbackEffects.filter((effect) => {
      effect.age += delta
      const progress = Math.min(effect.age / effect.duration, 1)
      const easeOut = 1 - Math.pow(1 - progress, 3)
      const collect = effect.kind === "collect"
      const scale = collect ? 0.82 + easeOut * 2.35 : 0.95 + easeOut * 3.05
      const fade = Math.max(0, 1 - progress)
      const flicker = collect ? 0.82 + Math.sin(effect.age * 28) * 0.18 : 1

      effect.group.scale.set(scale, 1, scale)
      effect.group.rotation.y += delta * (collect ? 0.8 : -1.6)
      effect.group.children.forEach((child, index) => {
        if (!child.material || child.userData.baseOpacity == null) return

        const beamBias = index === 2 ? Math.max(0, 1 - progress * 1.25) : fade
        child.material.opacity = child.userData.baseOpacity * beamBias * flicker
      })

      if (progress < 1) return true

      this.feedbackGroup?.remove(effect.group)
      this.disposeObject(effect.group)
      return false
    })
  }

  showEventCue(kind, text) {
    this.clearEventCueTimer()

    if (this.hasEventCueTarget) {
      this.eventCueTarget.textContent = text
      this.eventCueTarget.dataset.kind = kind
      this.eventCueTarget.hidden = false
      this.eventCueTarget.setAttribute("aria-hidden", "false")
      this.eventCueTarget.classList.remove("is-visible")
      void this.eventCueTarget.offsetWidth
      this.eventCueTarget.classList.add("is-visible")
    }

    if (this.hasScreenFlashTarget) {
      this.screenFlashTarget.dataset.kind = kind
      this.screenFlashTarget.hidden = false
      this.screenFlashTarget.classList.remove("is-visible")
      void this.screenFlashTarget.offsetWidth
      this.screenFlashTarget.classList.add("is-visible")
    }

    this.eventCueTimer = window.setTimeout(() => this.clearEventCue(), 920)
  }

  clearEventCueTimer() {
    if (!this.eventCueTimer) return

    window.clearTimeout(this.eventCueTimer)
    this.eventCueTimer = null
  }

  clearEventCue() {
    this.clearEventCueTimer()

    if (this.hasEventCueTarget) {
      this.eventCueTarget.classList.remove("is-visible")
      this.eventCueTarget.setAttribute("aria-hidden", "true")
      this.eventCueTarget.hidden = true
    }

    if (this.hasScreenFlashTarget) {
      this.screenFlashTarget.classList.remove("is-visible")
      this.screenFlashTarget.hidden = true
    }
  }

  updateCamera(delta) {
    const target = new THREE.Vector3(
      this.player.position.x * 0.82,
      9.5,
      this.player.position.z + 8.2
    )
    this.camera.position.lerp(target, delta * 5.2)
    this.camera.lookAt(this.player.position.x * 0.72, 0.8, this.player.position.z - 2.2)
  }

  levelSpeedMultiplier() {
    return 1 + (this.level - 1) * LEVEL_SPEED_STEP
  }

  playerSpeedMultiplier() {
    return 1 + (this.level - 1) * PLAYER_LEVEL_SPEED_STEP
  }

  async toggleSound() {
    this.soundEnabled = !this.soundEnabled

    if (this.soundEnabled) {
      const ready = await this.ensureAudio()
      if (!ready) {
        this.soundEnabled = false
        this.updateSoundButton()
        return
      }

      this.playSound("toggle")
      this.startMusic()
    } else {
      this.stopMusic()
    }

    this.updateSoundButton()
  }

  async ensureAudio() {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext
    if (!AudioContextClass) return false

    if (!this.audioContext) {
      this.audioContext = new AudioContextClass()
      this.masterGain = this.audioContext.createGain()
      this.masterGain.gain.value = 0.18
      this.masterGain.connect(this.audioContext.destination)
    }

    if (this.audioContext.state === "suspended") {
      await this.audioContext.resume()
    }

    return true
  }

  startMusic() {
    this.stopMusic()
    if (!this.soundEnabled) return

    this.musicStep = 0
    this.musicTimer = window.setInterval(() => this.playMusicStep(), 165)
  }

  stopMusic() {
    if (!this.musicTimer) return

    window.clearInterval(this.musicTimer)
    this.musicTimer = null
  }

  playMusicStep() {
    if (!this.soundEnabled || !this.audioContext || !this.masterGain) return

    const bass = [110, 110, 146.83, 110, 164.81, 146.83, 98, 123.47]
    const lead = [440, 0, 493.88, 0, 392, 0, 329.63, 0, 369.99, 0, 493.88, 0, 440, 0, 293.66, 0]
    const bassNote = bass[this.musicStep % bass.length] * this.levelSpeedMultiplier()
    const leadNote = lead[this.musicStep % lead.length]

    this.playTone(bassNote, 0.105, "square", 0.12)
    if (leadNote) {
      this.playTone(leadNote, 0.055, "square", 0.055, 0.02)
    }

    this.musicStep += 1
  }

  playSound(kind) {
    if (!this.soundEnabled || !this.audioContext || !this.masterGain) return

    if (kind === "fragment") {
      this.playTone(659.25, 0.055, "square", 0.16)
      this.playTone(987.77, 0.075, "square", 0.12, 0.055)
      return
    }

    if (kind === "hit") {
      this.playTone(146.83, 0.08, "sawtooth", 0.2)
      this.playTone(92.5, 0.13, "square", 0.17, 0.04)
      return
    }

    if (kind === "level") {
      ;[523.25, 659.25, 783.99, 1046.5].forEach((frequency, index) => {
        this.playTone(frequency, 0.075, "square", 0.13, index * 0.075)
      })
      return
    }

    if (kind === "gameOver") {
      ;[246.94, 196, 146.83, 98].forEach((frequency, index) => {
        this.playTone(frequency, 0.12, "square", 0.14, index * 0.09)
      })
      return
    }

    if (kind === "toggle") {
      this.playTone(523.25, 0.06, "square", 0.09)
      this.playTone(783.99, 0.08, "square", 0.08, 0.06)
    }
  }

  playTone(frequency, duration, type, volume, delay = 0) {
    if (!this.audioContext || !this.masterGain) return

    const startAt = this.audioContext.currentTime + delay
    const oscillator = this.audioContext.createOscillator()
    const gain = this.audioContext.createGain()

    oscillator.type = type
    oscillator.frequency.setValueAtTime(frequency, startAt)
    gain.gain.setValueAtTime(0.0001, startAt)
    gain.gain.exponentialRampToValueAtTime(Math.max(volume, 0.0001), startAt + 0.012)
    gain.gain.exponentialRampToValueAtTime(0.0001, startAt + duration)
    oscillator.connect(gain)
    gain.connect(this.masterGain)
    oscillator.start(startAt)
    oscillator.stop(startAt + duration + 0.025)
  }

  updateSoundButton() {
    if (!this.hasSoundButtonTarget) return

    this.soundButtonTarget.textContent = this.soundEnabled ? "Sound on" : "Sound off"
    this.soundButtonTarget.setAttribute("aria-pressed", this.soundEnabled ? "true" : "false")
  }

  triggerSentinelHit(sentinel, elapsed) {
    if (elapsed - this.lastSentinelHitAt < SENTINEL_HIT_COOLDOWN) return

    this.lastSentinelHitAt = elapsed
    this.hitFlash = 1
    this.integrity = Math.max(0, this.integrity - SENTINEL_HIT_DAMAGE)
    this.playSound("hit")
    this.showEventCue("hit", "INTEGRITY HIT")
    this.createWorldFeedback(this.player.position.clone(), "hit")

    const knockback = this.player.position.clone().sub(sentinel.position)
    knockback.y = 0
    if (knockback.lengthSq() < 0.001) {
      knockback.set(0, 0, 1)
    }
    knockback.normalize()
    this.player.position.addScaledVector(knockback, SENTINEL_KNOCKBACK)
    this.clampPlayerToBounds()
    this.pointerTarget = null

    if (this.integrity <= 0) {
      this.running = false
      this.gameOver = true
      this.playSound("gameOver")
      this.updateHud("The Archive sealed. Restart to try again.")
    } else {
      this.updateHud(`Sentinel breach. Integrity -${SENTINEL_HIT_DAMAGE}.`)
    }
  }

  horizontalDistance(first, second) {
    const dx = first.x - second.x
    const dz = first.z - second.z
    return Math.sqrt(dx * dx + dz * dz)
  }

  clampPlayerToBounds() {
    const beforeX = this.player.position.x
    const beforeZ = this.player.position.z
    this.clampVectorToPlayBounds(this.player.position)

    if (this.pointerTarget && (beforeX !== this.player.position.x || beforeZ !== this.player.position.z)) {
      this.pointerTarget = null
    }
  }

  clampVectorToPlayBounds(vector) {
    vector.x = THREE.MathUtils.clamp(vector.x, PLAY_BOUNDS.minX, PLAY_BOUNDS.maxX)
    vector.z = THREE.MathUtils.clamp(vector.z, PLAY_BOUNDS.minZ, PLAY_BOUNDS.maxZ)
    return vector
  }

  checkWin() {
    if (this.fragmentsCollected < FRAGMENT_COUNT || this.won) return

    const gateCenter = new THREE.Vector3(0, 0.82, -17.9)
    if (this.player.position.distanceTo(gateCenter) <= INDEX_RADIUS) {
      this.advanceLevel()
    }
  }

  advanceLevel() {
    this.won = true
    this.level += 1
    this.integrity = Math.min(100, this.integrity + LEVEL_INTEGRITY_BONUS)
    this.playSound("level")
    this.startLevel(`Level ${this.level}. The archive shifts faster.`)
  }

  updateHud(statusText = null) {
    if (statusText) {
      this.statusTarget.textContent = statusText
    }
    this.fragmentsTarget.textContent = `${this.fragmentsCollected}/${FRAGMENT_COUNT}`
    this.levelTarget.textContent = `${this.level}`
    this.integrityTarget.textContent = `${this.integrity}`
    this.depthTarget.textContent = `${this.depth}`
  }

  handleKeydown(event) {
    if (this.interactiveElement(event.target)) return

    const key = event.key.toLowerCase()
    if (["w", "a", "s", "d", "arrowup", "arrowdown", "arrowleft", "arrowright"].includes(key)) {
      event.preventDefault()
      this.pointerTarget = null
      this.keys.add(key)
      return
    }

    if (key === "r") {
      event.preventDefault()
      this.restart()
      return
    }

    if (key === "escape" && this.hasExitUrlValue) {
      event.preventDefault()
      window.location.assign(this.exitUrlValue)
    }
  }

  handleKeyup(event) {
    this.keys.delete(event.key.toLowerCase())
  }

  handlePointerdown(event) {
    if (event.pointerType === "touch" || event.pointerType === "pen") {
      this.touchPointerId = event.pointerId
      this.touchStart = { x: event.clientX, y: event.clientY }
      this.touchDragging = false
      this.touchMoveVector.set(0, 0, 0)
      this.captureTouchPointer(event.pointerId)
      event.preventDefault()
    }

    if (event.pointerType === "touch" || event.pointerType === "pen") {
      this.element.focus({ preventScroll: true })
      return
    }

    this.setPointerTargetFromEvent(event)
    this.element.focus({ preventScroll: true })
  }

  setPointerTargetFromEvent(event) {
    const rect = this.canvasTarget.getBoundingClientRect()
    this.pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1
    this.pointer.y = -(((event.clientY - rect.top) / rect.height) * 2 - 1)
    this.raycaster.setFromCamera(this.pointer, this.camera)

    const target = new THREE.Vector3()
    if (this.raycaster.ray.intersectPlane(this.floorPlane, target)) {
      this.clampVectorToPlayBounds(target)
      target.y = 0.82
      this.pointerTarget = target
    }
  }

  handlePointermove(event) {
    if (event.pointerId !== this.touchPointerId || !this.touchStart) return

    const deltaX = event.clientX - this.touchStart.x
    const deltaY = event.clientY - this.touchStart.y
    const distance = Math.hypot(deltaX, deltaY)
    if (distance < TOUCH_DRAG_THRESHOLD) return

    this.touchDragging = true
    this.pointerTarget = null
    this.touchMoveVector.set(deltaX, 0, deltaY).normalize()
    event.preventDefault()
  }

  handlePointerup(event) {
    if (event.pointerId !== this.touchPointerId) return

    if (!this.touchDragging && event.type !== "pointercancel") {
      this.setPointerTargetFromEvent(event)
    }

    this.releaseTouchPointer(event.pointerId)
    this.touchMoveVector.set(0, 0, 0)
    this.touchPointerId = null
    this.touchStart = null
    this.touchDragging = false

    if (event.pointerType === "touch" || event.pointerType === "pen") {
      event.preventDefault()
    }
  }

  captureTouchPointer(pointerId) {
    try {
      this.canvasTarget.setPointerCapture?.(pointerId)
    } catch (_error) {
      // Synthetic and cancelled pointer streams can lack an active pointer capture.
    }
  }

  releaseTouchPointer(pointerId) {
    try {
      this.canvasTarget.releasePointerCapture?.(pointerId)
    } catch (_error) {
      // Movement state still resets even if the browser has already released capture.
    }
  }

  resize() {
    if (!this.renderer || !this.camera) return

    const rect = this.element.getBoundingClientRect()
    const width = Math.max(Math.floor(rect.width), 320)
    const height = Math.max(Math.floor(rect.height), 420)
    this.renderer.setSize(width, height, false)
    this.camera.aspect = width / height
    this.camera.updateProjectionMatrix()
  }

  clearFeedbackEffects() {
    if (!this.feedbackEffects?.length) return

    this.feedbackEffects.forEach((effect) => {
      this.feedbackGroup?.remove(effect.group)
      this.disposeObject(effect.group)
    })
    this.feedbackEffects = []
  }

  disposeObject(object) {
    object.traverse((child) => {
      if (child.geometry) child.geometry.dispose()
      if (!child.material) return

      const materials = Array.isArray(child.material) ? child.material : [child.material]
      materials.forEach((material) => {
        Object.values(material).forEach((value) => {
          if (value?.isTexture) value.dispose()
        })
        material.dispose()
      })
    })
  }

  disposeScene() {
    if (!this.scene) return

    this.scene.traverse((object) => {
      if (object.geometry) object.geometry.dispose()
      if (!object.material) return

      const materials = Array.isArray(object.material) ? object.material : [object.material]
      materials.forEach((material) => {
        Object.values(material).forEach((value) => {
          if (value?.isTexture) value.dispose()
        })
        material.dispose()
      })
    })

    this.renderer?.dispose()
  }

  interactiveElement(target) {
    return Boolean(target?.closest?.("input, textarea, select, button, a, [contenteditable='true']"))
  }
}
