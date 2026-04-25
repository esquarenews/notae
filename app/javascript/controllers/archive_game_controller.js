import { Controller } from "@hotwired/stimulus"
import * as THREE from "three"

const FRAGMENT_COUNT = 7
const PLAYER_SPEED = 8.5
const SENTINEL_SPEED = 0.72
const WORLD_LIMIT = 18
const HAZARD_RADIUS = 1.15
const FRAGMENT_RADIUS = 1.05
const INDEX_RADIUS = 1.75

export default class extends Controller {
  static targets = ["canvas", "status", "fragments", "integrity", "depth"]
  static values = {
    exitUrl: String
  }

  connect() {
    this.keys = new Set()
    this.clock = new THREE.Clock()
    this.pointer = new THREE.Vector2()
    this.pointerTarget = null
    this.running = false
    this.gameOver = false
    this.won = false

    this.boundKeydown = (event) => this.handleKeydown(event)
    this.boundKeyup = (event) => this.handleKeyup(event)
    this.boundResize = () => this.resize()
    this.boundPointerdown = (event) => this.handlePointerdown(event)

    window.addEventListener("keydown", this.boundKeydown)
    window.addEventListener("keyup", this.boundKeyup)
    window.addEventListener("resize", this.boundResize)
    this.canvasTarget.addEventListener("pointerdown", this.boundPointerdown)

    this.buildScene()
    this.restart()
  }

  disconnect() {
    window.removeEventListener("keydown", this.boundKeydown)
    window.removeEventListener("keyup", this.boundKeyup)
    window.removeEventListener("resize", this.boundResize)
    this.canvasTarget.removeEventListener("pointerdown", this.boundPointerdown)

    if (this.animationFrame) {
      window.cancelAnimationFrame(this.animationFrame)
      this.animationFrame = null
    }

    this.disposeScene()
  }

  restart() {
    this.keys.clear()
    this.pointerTarget = null
    this.fragmentsCollected = 0
    this.integrity = 100
    this.depth = 0
    this.gameOver = false
    this.won = false
    this.running = true

    this.resetSceneObjects()
    this.updateHud("Recover the lost fragments.")
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
    this.scene.add(this.archiveGroup, this.fragmentGroup, this.sentinelGroup)

    this.buildLights()
    this.buildRoom()
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
  }

  buildRoom() {
    const floorMaterial = new THREE.MeshStandardMaterial({
      color: 0x1d221f,
      roughness: 0.72,
      metalness: 0.04
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

    const ring = new THREE.Mesh(
      new THREE.TorusGeometry(0.95, 0.025, 10, 48),
      new THREE.MeshBasicMaterial({ color: 0xbdf6df, transparent: true, opacity: 0.66 })
    )
    ring.rotation.x = Math.PI / 2

    this.player = new THREE.Group()
    this.player.add(body, ring)
    this.scene.add(this.player)
  }

  buildFragments() {
    this.fragments = []
    const positions = [
      [-12, 0.82, 9],
      [11, 0.82, 8],
      [-8, 0.82, 0],
      [7, 0.82, -2],
      [-13, 0.82, -10],
      [13, 0.82, -12],
      [0, 0.82, -15]
    ]

    positions.forEach((position, index) => {
      const fragment = this.createFragment(index)
      fragment.position.set(position[0], position[1], position[2])
      fragment.userData.homeY = position[1]
      fragment.userData.collected = false
      this.fragments.push(fragment)
      this.fragmentGroup.add(fragment)
    })
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
      emissiveIntensity: 0.09,
      side: THREE.DoubleSide
    })
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(1.08, 1.42, 0.045), material)
    mesh.castShadow = true
    return mesh
  }

  buildSentinels() {
    this.sentinels = []
    const paths = [
      { center: new THREE.Vector3(-8, 0.75, 4), radius: 3.6, phase: 0 },
      { center: new THREE.Vector3(8, 0.75, 3), radius: 4.2, phase: 2.2 },
      { center: new THREE.Vector3(0, 0.75, -8), radius: 5.3, phase: 4.2 }
    ]

    paths.forEach((path) => {
      const sentinel = this.createSentinel()
      sentinel.userData.path = path
      this.sentinels.push(sentinel)
      this.sentinelGroup.add(sentinel)
    })
  }

  createSentinel() {
    const core = new THREE.Mesh(
      new THREE.OctahedronGeometry(0.7, 0),
      new THREE.MeshStandardMaterial({
        color: 0xd95d49,
        roughness: 0.26,
        metalness: 0.18,
        emissive: 0x8d1d14,
        emissiveIntensity: 0.68
      })
    )
    core.castShadow = true

    const halo = new THREE.Mesh(
      new THREE.TorusGeometry(1.02, 0.035, 12, 44),
      new THREE.MeshBasicMaterial({ color: 0xffad8b, transparent: true, opacity: 0.56 })
    )
    halo.rotation.x = Math.PI / 2

    const sentinel = new THREE.Group()
    sentinel.add(core, halo)
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
    this.player.position.set(0, 0.82, 13)
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

  animate() {
    this.animationFrame = window.requestAnimationFrame(() => this.animate())
    const delta = Math.min(this.clock.getDelta(), 0.04)
    const elapsed = this.clock.elapsedTime

    if (this.running) {
      this.updatePlayer(delta)
      this.updateFragments(elapsed)
      this.updateSentinels(delta, elapsed)
      this.updateIndexGate(delta, elapsed)
      this.updateCamera(delta)
      this.depth = Math.max(0, Math.round(18 - this.player.position.z))
      this.checkWin()
      this.updateHud()
    } else {
      this.updateFragments(elapsed)
      this.updateIndexGate(delta, elapsed)
    }

    this.renderer.render(this.scene, this.camera)
  }

  updatePlayer(delta) {
    const movement = new THREE.Vector3()
    if (this.keys.has("w") || this.keys.has("arrowup")) movement.z -= 1
    if (this.keys.has("s") || this.keys.has("arrowdown")) movement.z += 1
    if (this.keys.has("a") || this.keys.has("arrowleft")) movement.x -= 1
    if (this.keys.has("d") || this.keys.has("arrowright")) movement.x += 1

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
      this.player.position.addScaledVector(movement, PLAYER_SPEED * delta)
      this.player.rotation.y = Math.atan2(movement.x, movement.z)
    }

    this.player.position.x = THREE.MathUtils.clamp(this.player.position.x, -WORLD_LIMIT, WORLD_LIMIT)
    this.player.position.z = THREE.MathUtils.clamp(this.player.position.z, -WORLD_LIMIT, WORLD_LIMIT - 2)
    this.player.children[1].rotation.z += delta * 1.8
  }

  updateFragments(elapsed) {
    this.fragments.forEach((fragment, index) => {
      if (fragment.userData.collected) return

      fragment.rotation.y = elapsed * 0.72 + index
      fragment.rotation.z = Math.sin(elapsed * 1.1 + index) * 0.08
      fragment.position.y = fragment.userData.homeY + Math.sin(elapsed * 1.6 + index) * 0.22

      if (fragment.position.distanceTo(this.player.position) < FRAGMENT_RADIUS) {
        fragment.userData.collected = true
        fragment.visible = false
        this.fragmentsCollected += 1
        const remaining = FRAGMENT_COUNT - this.fragmentsCollected
        this.updateHud(remaining === 0 ? "The Index is open." : `${remaining} fragments remain.`)
      }
    })
  }

  updateSentinels(delta, elapsed) {
    this.sentinels.forEach((sentinel, index) => {
      const path = sentinel.userData.path
      const angle = elapsed * SENTINEL_SPEED * (1 + index * 0.11) + path.phase
      sentinel.position.set(
        path.center.x + Math.cos(angle) * path.radius,
        path.center.y + Math.sin(elapsed * 2 + index) * 0.18,
        path.center.z + Math.sin(angle) * path.radius
      )
      sentinel.rotation.y += delta * 2.4
      sentinel.children[1].rotation.z += delta * 1.7

      if (sentinel.position.distanceTo(this.player.position) < HAZARD_RADIUS && !this.gameOver && !this.won) {
        this.integrity = Math.max(0, this.integrity - Math.round(42 * delta))
        this.updateHud("Sentinel contact.")
        if (this.integrity <= 0) {
          this.running = false
          this.gameOver = true
          this.updateHud("The Archive sealed. Restart to try again.")
        }
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

  updateCamera(delta) {
    const target = new THREE.Vector3(
      this.player.position.x * 0.42,
      9.5,
      this.player.position.z + 8.2
    )
    this.camera.position.lerp(target, delta * 3.8)
    this.camera.lookAt(this.player.position.x * 0.2, 0.8, this.player.position.z - 5)
  }

  checkWin() {
    if (this.fragmentsCollected < FRAGMENT_COUNT || this.won) return

    const gateCenter = new THREE.Vector3(0, 0.82, -17.9)
    if (this.player.position.distanceTo(gateCenter) <= INDEX_RADIUS) {
      this.won = true
      this.running = false
      this.updateHud("Index restored.")
    }
  }

  updateHud(statusText = null) {
    if (statusText) {
      this.statusTarget.textContent = statusText
    }
    this.fragmentsTarget.textContent = `${this.fragmentsCollected}/${FRAGMENT_COUNT}`
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
    const rect = this.canvasTarget.getBoundingClientRect()
    this.pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1
    this.pointer.y = -(((event.clientY - rect.top) / rect.height) * 2 - 1)
    this.raycaster.setFromCamera(this.pointer, this.camera)

    const target = new THREE.Vector3()
    if (this.raycaster.ray.intersectPlane(this.floorPlane, target)) {
      target.x = THREE.MathUtils.clamp(target.x, -WORLD_LIMIT, WORLD_LIMIT)
      target.z = THREE.MathUtils.clamp(target.z, -WORLD_LIMIT, WORLD_LIMIT - 2)
      target.y = 0.82
      this.pointerTarget = target
    }

    this.element.focus({ preventScroll: true })
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
