import { Controller } from "@hotwired/stimulus"

const MAZE_LAYOUTS = Object.freeze([
  [
    "#####################",
    "#o....#.......#....o#",
    "#.##.#.#.###.#.#.##.#",
    "#...................#",
    "###.#.#####.#####.#.#",
    "#...#.......#.....#.#",
    "#.#.###.###.#.###.#.#",
    "#.#.....#.....#.....#",
    "#.#####.#.###.#.###.#",
    "#.......#.....#.....#",
    "#.###.#.#####.#.###.#",
    "#o..#...........#..o#",
    "#####################"
  ],
  [
    "#####################",
    "#o..#.....#.....#..o#",
    "#.#.#.###.#.###.#.#.#",
    "#.#...#...#...#...#.#",
    "#.#####.#####.#####.#",
    "#.......#...#.......#",
    "###.###.#.#.#.###.###",
    "#...#...#.#.#...#...#",
    "#.###.###.#.###.###.#",
    "#.....#.......#.....#",
    "#.###.#.#####.#.###.#",
    "#o..#...........#..o#",
    "#####################"
  ]
])

const DIRECTIONS = Object.freeze({
  none: Object.freeze({ name: "none", x: 0, y: 0 }),
  up: Object.freeze({ name: "up", x: 0, y: -1 }),
  down: Object.freeze({ name: "down", x: 0, y: 1 }),
  left: Object.freeze({ name: "left", x: -1, y: 0 }),
  right: Object.freeze({ name: "right", x: 1, y: 0 })
})
const DIRECTION_LIST = [DIRECTIONS.up, DIRECTIONS.left, DIRECTIONS.down, DIRECTIONS.right]
const BUG_TYPES = Object.freeze([
  { name: "stale task", color: "#c76556", accent: "#ffb09d" },
  { name: "sync error", color: "#b05e9f", accent: "#e9aadf" },
  { name: "blocker", color: "#c98246", accent: "#ffd08b" }
])
const PLAYER_SPEED = 6.6
const BUG_SPEED = 2.85
const LEVEL_SPEED_STEP = 0.16
const POWER_DURATION_MS = 7600
const BUG_RESPAWN_MS = 1900
const TOUCH_DEADZONE = 22
const SAFE_START_MS = 2600
const TURN_ASSIST_DISTANCE = 0.22

export default class extends Controller {
  static targets = ["canvas", "status", "level", "fragments", "sparks", "integrity", "soundButton"]
  static values = {
    exitUrl: String
  }

  connect() {
    this.canvasContext = this.canvasTarget.getContext("2d")
    this.keys = new Set()
    this.level = 1
    this.integrity = 3
    this.score = 0
    this.soundEnabled = false
    this.audioContext = null
    this.masterGain = null
    this.musicTimer = null
    this.musicStep = 0
    this.particles = []
    this.touchStart = null
    this.lastFrameAt = null
    this.levelClearing = false
    this.gameOver = false

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

    this.resize()
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
  }

  restart() {
    this.level = 1
    this.integrity = 3
    this.score = 0
    this.startLevel("Collect every fragment.")
  }

  startLevel(statusText) {
    this.layout = MAZE_LAYOUTS[(this.level - 1) % MAZE_LAYOUTS.length]
    this.rows = this.layout.length
    this.columns = this.layout[0].length
    this.fragments = new Set()
    this.sparks = new Set()
    this.particles = []
    this.poweredUntil = 0
    this.safeUntil = performance.now() + SAFE_START_MS
    this.levelClearing = false
    this.gameOver = false
    this.keys.clear()

    this.layout.forEach((row, rowIndex) => {
      Array.from(row).forEach((cell, columnIndex) => {
        const key = this.tileKey(columnIndex, rowIndex)
        if (cell === ".") this.fragments.add(key)
        if (cell === "o") this.sparks.add(key)
      })
    })

    this.placeActors()
    this.resize()
    this.updateHud(statusText)
    this.element.focus({ preventScroll: true })

    if (!this.animationFrame) {
      this.lastFrameAt = null
      this.animationFrame = window.requestAnimationFrame((timestamp) => this.animate(timestamp))
    }
  }

  placeActors() {
    this.player = this.createActor(this.openTileNear(10, 9))
    this.player.direction = DIRECTIONS.left
    this.player.queuedDirection = DIRECTIONS.left

    const bugSpawns = [
      this.openTileNear(3, 1),
      this.openTileNear(17, 1),
      this.openTileNear(18, 11)
    ]

    this.bugs = BUG_TYPES.map((bugType, index) => {
      const spawn = bugSpawns[index]
      return {
        ...this.createActor(spawn),
        ...bugType,
        spawn,
        resolvedUntil: 0,
        scatterBias: DIRECTION_LIST[index % DIRECTION_LIST.length]
      }
    })
  }

  createActor(tile) {
    return {
      col: tile.col,
      row: tile.row,
      x: tile.col,
      y: tile.row,
      target: null,
      direction: DIRECTIONS.none,
      queuedDirection: DIRECTIONS.none
    }
  }

  animate(timestamp) {
    this.animationFrame = window.requestAnimationFrame((nextTimestamp) => this.animate(nextTimestamp))
    const delta = this.lastFrameAt ? Math.min((timestamp - this.lastFrameAt) / 1000, 0.045) : 0
    this.lastFrameAt = timestamp

    if (!this.levelClearing && !this.gameOver) {
      this.updatePlayer(delta, timestamp)
      this.updateBugs(delta, timestamp)
      this.checkBugCollisions(timestamp)
      this.checkLevelClear(timestamp)
    }

    this.updateParticles(delta)
    this.draw(timestamp)
  }

  updatePlayer(delta, timestamp) {
    this.applyResponsiveTurn(timestamp)

    if (!this.player.target) {
      if (!this.tryStartMove(this.player, this.player.queuedDirection)) {
        this.tryStartMove(this.player, this.player.direction)
      }
    }

    if (this.moveActor(this.player, PLAYER_SPEED * this.levelSpeedMultiplier() * delta)) {
      this.collectCurrentTile(timestamp)
    }
  }

  updateBugs(delta, timestamp) {
    this.bugs.forEach((bug, index) => {
      if (timestamp < bug.resolvedUntil) return

      if (!bug.target) {
        const direction = this.chooseBugDirection(bug, index, timestamp)
        this.tryStartMove(bug, direction)
      }

      this.moveActor(bug, BUG_SPEED * this.levelSpeedMultiplier() * delta)
    })
  }

  applyResponsiveTurn(timestamp) {
    const actor = this.player
    const direction = actor.queuedDirection
    if (!actor.target || !direction || direction.name === "none" || direction.name === actor.direction.name) return

    if (direction.name === this.reverseDirection(actor.direction).name) {
      actor.target = { col: actor.col, row: actor.row }
      actor.direction = direction
      return
    }

    const remaining = Math.hypot(actor.target.col - actor.x, actor.target.row - actor.y)
    if (remaining > TURN_ASSIST_DISTANCE) return
    if (this.wallAt(actor.target.col + direction.x, actor.target.row + direction.y)) return

    actor.x = actor.target.col
    actor.y = actor.target.row
    actor.col = actor.target.col
    actor.row = actor.target.row
    actor.target = null
    this.collectCurrentTile(timestamp)
    this.tryStartMove(actor, direction)
  }

  tryStartMove(actor, direction) {
    if (!direction || direction.name === "none") return false
    const nextCol = actor.col + direction.x
    const nextRow = actor.row + direction.y
    if (this.wallAt(nextCol, nextRow)) return false

    actor.direction = direction
    actor.target = { col: nextCol, row: nextRow }
    return true
  }

  moveActor(actor, distance) {
    if (!actor.target || distance <= 0) return false

    const dx = actor.target.col - actor.x
    const dy = actor.target.row - actor.y
    const remaining = Math.hypot(dx, dy)
    if (remaining <= distance) {
      actor.x = actor.target.col
      actor.y = actor.target.row
      actor.col = actor.target.col
      actor.row = actor.target.row
      actor.target = null
      return true
    }

    actor.x += (dx / remaining) * distance
    actor.y += (dy / remaining) * distance
    return false
  }

  collectCurrentTile(timestamp) {
    const key = this.tileKey(this.player.col, this.player.row)
    if (this.fragments.delete(key)) {
      this.score += 10
      this.playSound("collect")
      this.updateHud(`${this.fragments.size} fragments remain.`)
    }

    if (this.sparks.delete(key)) {
      this.score += 50
      this.poweredUntil = timestamp + POWER_DURATION_MS
      this.spawnBurst(this.player.x, this.player.y, "#f8d38a", 18)
      this.playSound("power")
      this.updateHud("AI spark active. Resolve bugs.")
    }
  }

  checkBugCollisions(timestamp) {
    if (timestamp < this.safeUntil) return

    for (const bug of this.bugs) {
      if (timestamp < bug.resolvedUntil) continue

      const distance = Math.hypot(this.player.x - bug.x, this.player.y - bug.y)
      if (distance > 0.58) continue

      if (this.powered(timestamp)) {
        bug.resolvedUntil = timestamp + BUG_RESPAWN_MS
        bug.x = bug.spawn.col
        bug.y = bug.spawn.row
        bug.col = bug.spawn.col
        bug.row = bug.spawn.row
        bug.target = null
        this.score += 120
        this.spawnBurst(bug.x, bug.y, "#d9fff2", 20)
        this.playSound("resolve")
        this.updateHud(`${bug.name} resolved.`)
      } else {
        this.handleBugHit()
        break
      }
    }
  }

  handleBugHit() {
    this.integrity -= 1
    this.spawnBurst(this.player.x, this.player.y, "#d96a56", 24)
    this.playSound("fail")
    if (this.integrity <= 0) {
      this.gameOver = true
      this.updateHud("System stalled. Restart to try again.")
    } else {
      this.resetActorsAfterHit()
      this.updateHud("Bug collision. Integrity reduced.")
    }
  }

  resetActorsAfterHit() {
    const playerStart = this.openTileNear(10, 9)
    this.player = this.createActor(playerStart)
    this.player.direction = DIRECTIONS.left
    this.player.queuedDirection = DIRECTIONS.left
    this.poweredUntil = 0
    this.safeUntil = performance.now() + SAFE_START_MS
    this.bugs.forEach((bug) => {
      bug.x = bug.spawn.col
      bug.y = bug.spawn.row
      bug.col = bug.spawn.col
      bug.row = bug.spawn.row
      bug.target = null
      bug.direction = DIRECTIONS.none
      bug.resolvedUntil = 0
    })
  }

  checkLevelClear(timestamp) {
    if (this.fragments.size > 0 || this.levelClearing) return

    this.levelClearing = true
    this.spawnBurst(this.player.x, this.player.y, "#82dfbd", 34)
    this.spawnBurst(this.player.x, this.player.y, "#f8d38a", 28)
    this.playSound("clear")
    this.updateHud("LEVEL CLEARED")

    window.setTimeout(() => {
      if (!this.element.isConnected) return
      this.level += 1
      this.integrity = Math.min(3, this.integrity + 1)
      this.startLevel(`Level ${this.level}. Bugs are faster.`)
    }, 1650)
  }

  chooseBugDirection(bug, index, timestamp) {
    const options = this.availableDirections(bug)
    if (options.length === 0) return DIRECTIONS.none

    if (this.powered(timestamp)) {
      return options
        .slice()
        .sort((first, second) => this.distanceAfterMove(bug, second, this.player) - this.distanceAfterMove(bug, first, this.player))[0]
    }

    if (index === 2 && Math.random() < 0.34) {
      return options[Math.floor(Math.random() * options.length)]
    }

    const target = index === 1 ? this.ambushTile() : this.player
    return this.firstStepToward(bug, target, options) || options[Math.floor(Math.random() * options.length)]
  }

  ambushTile() {
    return {
      col: this.player.col + this.player.direction.x * 3,
      row: this.player.row + this.player.direction.y * 3
    }
  }

  firstStepToward(actor, target, options) {
    const queue = [{ col: actor.col, row: actor.row, firstDirection: null }]
    const visited = new Set([this.tileKey(actor.col, actor.row)])

    while (queue.length > 0) {
      const current = queue.shift()
      if (current.col === target.col && current.row === target.row) {
        return current.firstDirection
      }

      DIRECTION_LIST.forEach((direction) => {
        const nextCol = current.col + direction.x
        const nextRow = current.row + direction.y
        const key = this.tileKey(nextCol, nextRow)
        if (visited.has(key) || this.wallAt(nextCol, nextRow)) return

        const firstDirection = current.firstDirection || options.find((option) => option.name === direction.name)
        if (!firstDirection) return

        visited.add(key)
        queue.push({ col: nextCol, row: nextRow, firstDirection })
      })
    }

    return null
  }

  availableDirections(actor) {
    const reverse = this.reverseDirection(actor.direction)
    const forwardOptions = DIRECTION_LIST.filter((direction) => {
      if (direction.name === reverse.name) return false
      return !this.wallAt(actor.col + direction.x, actor.row + direction.y)
    })

    if (forwardOptions.length > 0) return forwardOptions

    return DIRECTION_LIST.filter((direction) => !this.wallAt(actor.col + direction.x, actor.row + direction.y))
  }

  reverseDirection(direction) {
    if (direction.name === "up") return DIRECTIONS.down
    if (direction.name === "down") return DIRECTIONS.up
    if (direction.name === "left") return DIRECTIONS.right
    if (direction.name === "right") return DIRECTIONS.left
    return DIRECTIONS.none
  }

  distanceAfterMove(actor, direction, target) {
    return Math.hypot(actor.col + direction.x - target.col, actor.row + direction.y - target.row)
  }

  powered(timestamp) {
    return timestamp < this.poweredUntil
  }

  levelSpeedMultiplier() {
    return 1 + (this.level - 1) * LEVEL_SPEED_STEP
  }

  wallAt(col, row) {
    return row < 0 || row >= this.rows || col < 0 || col >= this.columns || this.layout[row][col] === "#"
  }

  openTileNear(col, row) {
    if (!this.wallAt(col, row)) return { col, row }

    for (let radius = 1; radius < Math.max(this.columns, this.rows); radius += 1) {
      for (let y = row - radius; y <= row + radius; y += 1) {
        for (let x = col - radius; x <= col + radius; x += 1) {
          if (!this.wallAt(x, y)) return { col: x, row: y }
        }
      }
    }

    return { col: 1, row: 1 }
  }

  tileKey(col, row) {
    return `${col},${row}`
  }

  handleKeydown(event) {
    if (this.interactiveElement(event.target)) return

    const key = event.key.toLowerCase()
    if (["w", "a", "s", "d", "arrowup", "arrowdown", "arrowleft", "arrowright"].includes(key)) {
      event.preventDefault()
      this.keys.delete(key)
      this.keys.add(key)
      this.player.queuedDirection = this.directionForKey(key)
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
    const key = event.key.toLowerCase()
    const releasedDirection = this.directionForKey(key)
    this.keys.delete(key)

    if (releasedDirection.name === this.player.queuedDirection.name && this.keys.size > 0) {
      this.player.queuedDirection = this.directionForKey(Array.from(this.keys).at(-1))
    }
  }

  directionForKey(key) {
    if (key === "w" || key === "arrowup") return DIRECTIONS.up
    if (key === "s" || key === "arrowdown") return DIRECTIONS.down
    if (key === "a" || key === "arrowleft") return DIRECTIONS.left
    if (key === "d" || key === "arrowright") return DIRECTIONS.right
    return DIRECTIONS.none
  }

  handlePointerdown(event) {
    this.touchStart = { x: event.clientX, y: event.clientY }
    this.capturePointer(event.pointerId)
    this.element.focus({ preventScroll: true })
    event.preventDefault()
  }

  handlePointermove(event) {
    if (!this.touchStart) return

    const deltaX = event.clientX - this.touchStart.x
    const deltaY = event.clientY - this.touchStart.y
    if (Math.hypot(deltaX, deltaY) < TOUCH_DEADZONE) return

    this.queueDirectionFromVector(deltaX, deltaY)
    event.preventDefault()
  }

  handlePointerup(event) {
    if (!this.touchStart) return

    const deltaX = event.clientX - this.touchStart.x
    const deltaY = event.clientY - this.touchStart.y
    if (Math.hypot(deltaX, deltaY) >= TOUCH_DEADZONE) {
      this.queueDirectionFromVector(deltaX, deltaY)
    } else {
      const playerPoint = this.tileToPoint(this.player.x, this.player.y)
      this.queueDirectionFromVector(event.clientX - playerPoint.x, event.clientY - playerPoint.y)
    }

    this.touchStart = null
    this.releasePointer(event.pointerId)
    event.preventDefault()
  }

  capturePointer(pointerId) {
    try {
      this.canvasTarget.setPointerCapture?.(pointerId)
    } catch (_error) {
      // Synthetic or cancelled pointer streams may not be capturable.
    }
  }

  releasePointer(pointerId) {
    try {
      this.canvasTarget.releasePointerCapture?.(pointerId)
    } catch (_error) {
      // The browser may already have released capture; input state still resets.
    }
  }

  queueDirectionFromVector(deltaX, deltaY) {
    if (Math.abs(deltaX) > Math.abs(deltaY)) {
      this.player.queuedDirection = deltaX > 0 ? DIRECTIONS.right : DIRECTIONS.left
    } else {
      this.player.queuedDirection = deltaY > 0 ? DIRECTIONS.down : DIRECTIONS.up
    }
  }

  interactiveElement(target) {
    return Boolean(target?.closest?.("input, textarea, select, button, a, [contenteditable='true']"))
  }

  resize() {
    const rect = this.element.getBoundingClientRect()
    const width = Math.max(Math.floor(rect.width), 320)
    const height = Math.max(Math.floor(rect.height), 420)
    const pixelRatio = Math.min(window.devicePixelRatio || 1, 2)

    this.canvasTarget.width = Math.floor(width * pixelRatio)
    this.canvasTarget.height = Math.floor(height * pixelRatio)
    this.canvasTarget.style.width = `${width}px`
    this.canvasTarget.style.height = `${height}px`
    this.canvasContext.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0)
    this.width = width
    this.height = height

    if (this.columns && this.rows) {
      const compact = width < 760
      const topInset = compact ? 166 : 108
      const bottomInset = compact ? 162 : 112
      const availableHeight = Math.max(260, height - topInset - bottomInset)
      this.tileSize = Math.floor(Math.max(14, Math.min(34, width * 0.94 / this.columns, availableHeight / this.rows)))
      this.boardWidth = this.columns * this.tileSize
      this.boardHeight = this.rows * this.tileSize
      this.boardX = Math.round((width - this.boardWidth) / 2)
      this.boardY = compact ? Math.round(topInset + 12) : Math.round(topInset + (availableHeight - this.boardHeight) / 2)
    }
  }

  draw(timestamp) {
    const ctx = this.canvasContext
    ctx.clearRect(0, 0, this.width, this.height)
    this.drawBackground(ctx, timestamp)
    this.drawMaze(ctx)
    this.drawCollectibles(ctx, timestamp)
    this.drawActors(ctx, timestamp)
    this.drawParticles(ctx)
    this.drawOverlayText(ctx)
  }

  drawBackground(ctx, timestamp) {
    const pulse = 0.5 + Math.sin(timestamp / 1100) * 0.5
    ctx.fillStyle = "#101615"
    ctx.fillRect(0, 0, this.width, this.height)
    ctx.strokeStyle = `rgba(130, 223, 189, ${0.06 + pulse * 0.035})`
    ctx.lineWidth = 1
    for (let x = 0; x < this.width; x += 28) {
      ctx.beginPath()
      ctx.moveTo(x, 0)
      ctx.lineTo(x, this.height)
      ctx.stroke()
    }
    for (let y = 0; y < this.height; y += 28) {
      ctx.beginPath()
      ctx.moveTo(0, y)
      ctx.lineTo(this.width, y)
      ctx.stroke()
    }
  }

  drawMaze(ctx) {
    if (!this.tileSize) return

    ctx.save()
    ctx.translate(this.boardX, this.boardY)
    this.layout.forEach((row, rowIndex) => {
      Array.from(row).forEach((cell, colIndex) => {
        const x = colIndex * this.tileSize
        const y = rowIndex * this.tileSize
        if (cell === "#") {
          ctx.fillStyle = "#17312e"
          this.roundRect(ctx, x + 2, y + 2, this.tileSize - 4, this.tileSize - 4, 6)
          ctx.fill()
          ctx.strokeStyle = "rgba(130, 223, 189, 0.42)"
          ctx.lineWidth = 1
          ctx.stroke()
        } else {
          ctx.strokeStyle = "rgba(130, 223, 189, 0.1)"
          ctx.strokeRect(x + 0.5, y + 0.5, this.tileSize - 1, this.tileSize - 1)
        }
      })
    })
    ctx.restore()
  }

  drawCollectibles(ctx, timestamp) {
    this.fragments.forEach((key) => {
      const { col, row } = this.tileFromKey(key)
      const point = this.tileToPoint(col, row)
      const size = Math.max(4, this.tileSize * 0.22)
      ctx.save()
      ctx.shadowColor = "rgba(130, 223, 189, 0.65)"
      ctx.shadowBlur = 8
      ctx.fillStyle = "#efe5cd"
      this.roundRect(ctx, point.x - size / 2, point.y - size / 2, size, size * 0.72, 2)
      ctx.fill()
      ctx.restore()
    })

    this.sparks.forEach((key) => {
      const { col, row } = this.tileFromKey(key)
      const point = this.tileToPoint(col, row)
      const radius = this.tileSize * (0.2 + Math.sin(timestamp / 210) * 0.025)
      ctx.save()
      ctx.shadowColor = "rgba(248, 211, 138, 0.85)"
      ctx.shadowBlur = 16
      ctx.fillStyle = "#f8d38a"
      ctx.beginPath()
      ctx.arc(point.x, point.y, radius, 0, Math.PI * 2)
      ctx.fill()
      ctx.strokeStyle = "rgba(255, 247, 225, 0.78)"
      ctx.lineWidth = 2
      ctx.stroke()
      ctx.restore()
    })
  }

  drawActors(ctx, timestamp) {
    this.drawPlayer(ctx, timestamp)
    this.bugs.forEach((bug) => this.drawBug(ctx, bug, timestamp))
  }

  drawPlayer(ctx, timestamp) {
    const point = this.tileToPoint(this.player.x, this.player.y)
    const angle = this.directionAngle(this.player.direction)
    const radius = this.tileSize * 0.38
    const pulse = 0.5 + Math.sin(timestamp / 160) * 0.5

    ctx.save()
    ctx.translate(point.x, point.y)
    ctx.rotate(angle)
    ctx.shadowColor = "rgba(130, 223, 189, 0.95)"
    ctx.shadowBlur = 18
    ctx.fillStyle = "#82dfbd"
    ctx.beginPath()
    ctx.moveTo(radius * 1.2, 0)
    ctx.lineTo(-radius * 0.58, -radius * 0.72)
    ctx.quadraticCurveTo(-radius * 0.28, 0, -radius * 0.58, radius * 0.72)
    ctx.closePath()
    ctx.fill()
    ctx.fillStyle = `rgba(255, 255, 255, ${0.72 + pulse * 0.2})`
    ctx.beginPath()
    ctx.arc(radius * 0.2, -radius * 0.18, radius * 0.14, 0, Math.PI * 2)
    ctx.fill()
    ctx.restore()
  }

  drawBug(ctx, bug, timestamp) {
    const point = this.tileToPoint(bug.x, bug.y)
    const resolved = timestamp < bug.resolvedUntil
    const powered = this.powered(timestamp)
    const radius = this.tileSize * 0.36

    ctx.save()
    ctx.translate(point.x, point.y)
    ctx.shadowColor = resolved || powered ? "rgba(217, 255, 242, 0.72)" : bug.color
    ctx.shadowBlur = resolved || powered ? 10 : 13
    ctx.lineWidth = 2
    ctx.fillStyle = resolved || powered ? "rgba(217, 255, 242, 0.18)" : bug.color
    ctx.strokeStyle = resolved || powered ? "#d9fff2" : bug.accent

    ctx.beginPath()
    ctx.ellipse(0, 0, radius * 0.92, radius * 0.72, 0, 0, Math.PI * 2)
    ctx.fill()
    ctx.stroke()

    for (let side = -1; side <= 1; side += 2) {
      for (let leg = -1; leg <= 1; leg += 1) {
        ctx.beginPath()
        ctx.moveTo(side * radius * 0.58, leg * radius * 0.32)
        ctx.lineTo(side * radius * 1.02, leg * radius * 0.54)
        ctx.stroke()
      }
    }

    ctx.fillStyle = resolved || powered ? "#d9fff2" : "#2a1715"
    ctx.beginPath()
    ctx.arc(-radius * 0.27, -radius * 0.12, radius * 0.09, 0, Math.PI * 2)
    ctx.arc(radius * 0.27, -radius * 0.12, radius * 0.09, 0, Math.PI * 2)
    ctx.fill()
    ctx.restore()
  }

  drawParticles(ctx) {
    this.particles.forEach((particle) => {
      const point = this.tileToPoint(particle.x, particle.y)
      ctx.save()
      ctx.globalAlpha = particle.life
      ctx.fillStyle = particle.color
      ctx.fillRect(point.x - 2, point.y - 2, 4, 4)
      ctx.restore()
    })
  }

  drawOverlayText(ctx) {
    if (!this.levelClearing && !this.gameOver) return

    ctx.save()
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    ctx.fillStyle = this.levelClearing ? "#f8d38a" : "#ffb09d"
    ctx.shadowColor = this.levelClearing ? "rgba(248, 211, 138, 0.72)" : "rgba(217, 106, 86, 0.72)"
    ctx.shadowBlur = 18
    ctx.font = "800 32px system-ui, -apple-system, BlinkMacSystemFont, sans-serif"
    ctx.fillText(this.levelClearing ? "LEVEL CLEARED" : "SYSTEM STALLED", this.width / 2, this.boardY + this.boardHeight / 2)
    ctx.restore()
  }

  updateParticles(delta) {
    this.particles = this.particles
      .map((particle) => ({
        ...particle,
        x: particle.x + particle.vx * delta,
        y: particle.y + particle.vy * delta,
        life: particle.life - delta * 1.7
      }))
      .filter((particle) => particle.life > 0)
  }

  spawnBurst(x, y, color, count) {
    for (let index = 0; index < count; index += 1) {
      const angle = Math.random() * Math.PI * 2
      const speed = 1.6 + Math.random() * 4.2
      this.particles.push({
        x,
        y,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        color,
        life: 0.85 + Math.random() * 0.35
      })
    }
  }

  tileToPoint(col, row) {
    return {
      x: this.boardX + col * this.tileSize + this.tileSize / 2,
      y: this.boardY + row * this.tileSize + this.tileSize / 2
    }
  }

  tileFromKey(key) {
    const [col, row] = key.split(",").map((value) => Number.parseInt(value, 10))
    return { col, row }
  }

  directionAngle(direction) {
    if (direction.name === "up") return -Math.PI / 2
    if (direction.name === "down") return Math.PI / 2
    if (direction.name === "left") return Math.PI
    return 0
  }

  roundRect(ctx, x, y, width, height, radius) {
    ctx.beginPath()
    ctx.moveTo(x + radius, y)
    ctx.lineTo(x + width - radius, y)
    ctx.quadraticCurveTo(x + width, y, x + width, y + radius)
    ctx.lineTo(x + width, y + height - radius)
    ctx.quadraticCurveTo(x + width, y + height, x + width - radius, y + height)
    ctx.lineTo(x + radius, y + height)
    ctx.quadraticCurveTo(x, y + height, x, y + height - radius)
    ctx.lineTo(x, y + radius)
    ctx.quadraticCurveTo(x, y, x + radius, y)
    ctx.closePath()
  }

  updateHud(statusText = null) {
    if (statusText) this.statusTarget.textContent = statusText
    this.levelTarget.textContent = `${this.level}`
    this.fragmentsTarget.textContent = `${this.fragments?.size || 0}`
    this.sparksTarget.textContent = `${this.sparks?.size || 0}`
    this.integrityTarget.textContent = `${this.integrity}`
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
      this.playSound("power")
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
      this.masterGain.gain.value = 0.15
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
    this.musicTimer = window.setInterval(() => this.playMusicStep(), 220)
  }

  stopMusic() {
    if (!this.musicTimer) return
    window.clearInterval(this.musicTimer)
    this.musicTimer = null
  }

  playMusicStep() {
    if (!this.soundEnabled || !this.audioContext || !this.masterGain) return

    const pattern = [98, 0, 123.47, 0, 146.83, 0, 123.47, 0]
    const note = pattern[this.musicStep % pattern.length]
    if (note) this.playTone(note * this.levelSpeedMultiplier(), 0.08, "square", 0.045)
    this.musicStep += 1
  }

  playSound(kind) {
    if (!this.soundEnabled || !this.audioContext || !this.masterGain) return

    if (kind === "collect") {
      this.playTone(659.25, 0.035, "square", 0.08)
      return
    }

    if (kind === "power") {
      ;[523.25, 659.25, 987.77].forEach((frequency, index) => this.playTone(frequency, 0.055, "square", 0.085, index * 0.045))
      return
    }

    if (kind === "resolve") {
      this.playTone(783.99, 0.05, "square", 0.09)
      this.playTone(1174.66, 0.055, "square", 0.075, 0.045)
      return
    }

    if (kind === "clear") {
      ;[523.25, 659.25, 783.99, 1046.5].forEach((frequency, index) => this.playTone(frequency, 0.08, "square", 0.11, index * 0.07))
      return
    }

    if (kind === "fail") {
      this.playTone(155.56, 0.16, "sawtooth", 0.12)
      this.playTone(92.5, 0.2, "square", 0.1, 0.06)
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

    this.soundButtonTarget.textContent = this.soundEnabled ? "Sound On" : "Sound Off"
    this.soundButtonTarget.setAttribute("aria-pressed", this.soundEnabled ? "true" : "false")
  }
}
