import { Controller } from "@hotwired/stimulus"

const DEFAULT_BOARD = { width: 1600, height: 1000 }
const DEFAULT_COLOR = "#111827"
const DEFAULT_DIAMETER = 3
const MIN_DIAMETER = 1
const MAX_DIAMETER = 10
const SAVE_DELAY_MS = 500
const MIN_POINT_DISTANCE = 0.5

export default class extends Controller {
  static targets = [ "canvas", "status", "toolButton", "colorButton", "colorInput", "diameterInput", "diameterValue", "openButton", "collapseButton" ]

  static values = {
    url: String,
    initialJson: Object,
    title: String,
    readonly: Boolean
  }

  connect() {
    this.context = this.canvasTarget.getContext("2d")
    this.state = this.normalizedState(this.initialJsonValue || {})
    this.board = this.state.board
    this.strokes = this.state.strokes
    this.tool = "pencil"
    this.color = DEFAULT_COLOR
    this.diameter = DEFAULT_DIAMETER
    this.activeStroke = null
    this.activePointerId = null
    this.saveTimer = null
    this.resizeHandler = () => this.resizeCanvas()

    this.pointerDownHandler = (event) => this.handlePointerDown(event)
    this.pointerMoveHandler = (event) => this.handlePointerMove(event)
    this.pointerUpHandler = (event) => this.handlePointerUp(event)

    if (!this.readonlyValue) {
      this.canvasTarget.addEventListener("pointerdown", this.pointerDownHandler)
      this.canvasTarget.addEventListener("pointermove", this.pointerMoveHandler)
      this.canvasTarget.addEventListener("pointerup", this.pointerUpHandler)
      this.canvasTarget.addEventListener("pointercancel", this.pointerUpHandler)
    }

    if ("ResizeObserver" in window) {
      this.resizeObserver = new ResizeObserver(this.resizeHandler)
      this.resizeObserver.observe(this.element)
    } else {
      window.addEventListener("resize", this.resizeHandler)
    }

    this.resizeCanvas()
    this.updateToolButtons()
    this.updateColorInput()
    this.updateColorButtons()
    this.updateDiameterControls()
    this.setStatus(this.readonlyValue ? "Read only" : "Saved")

    if (this.state.whiteboard_autofocus) {
      window.requestAnimationFrame(() => this.enterFullscreen())
    }
  }

  disconnect() {
    this.canvasTarget.removeEventListener("pointerdown", this.pointerDownHandler)
    this.canvasTarget.removeEventListener("pointermove", this.pointerMoveHandler)
    this.canvasTarget.removeEventListener("pointerup", this.pointerUpHandler)
    this.canvasTarget.removeEventListener("pointercancel", this.pointerUpHandler)
    this.resizeObserver?.disconnect()
    window.removeEventListener("resize", this.resizeHandler)
    window.clearTimeout(this.saveTimer)
    this.releasePointer()
    document.documentElement.classList.remove("notae-whiteboard-open")
    document.body.classList.remove("notae-whiteboard-open")
  }

  enterFullscreen(event) {
    event?.preventDefault()
    this.element.classList.add("is-fullscreen")
    document.documentElement.classList.add("notae-whiteboard-open")
    document.body.classList.add("notae-whiteboard-open")
    this.openButtonTarget.hidden = true
    this.collapseButtonTarget.hidden = false
    window.requestAnimationFrame(() => this.resizeCanvas())
  }

  exitFullscreen(event) {
    event?.preventDefault()
    this.element.classList.remove("is-fullscreen")
    document.documentElement.classList.remove("notae-whiteboard-open")
    document.body.classList.remove("notae-whiteboard-open")
    this.openButtonTarget.hidden = false
    this.collapseButtonTarget.hidden = true
    delete this.state.whiteboard_autofocus
    this.queueSave({ immediate: true })
    window.requestAnimationFrame(() => this.resizeCanvas())
  }

  selectTool(event) {
    event.preventDefault()
    this.tool = event.params.tool || "pencil"
    this.updateToolButtons()
  }

  selectColor(event) {
    event.preventDefault()
    this.color = event.params.color || DEFAULT_COLOR
    this.updateColorInput()
    this.updateColorButtons()
  }

  selectCustomColor(event) {
    this.color = event.currentTarget.value || DEFAULT_COLOR
    this.updateColorButtons()
  }

  selectDiameter(event) {
    this.diameter = this.clampedDiameter(event.currentTarget.value)
    this.updateDiameterControls()
  }

  clearAll(event) {
    event.preventDefault()
    if (!window.confirm("Clear everything on this whiteboard?")) return

    this.strokes = []
    this.state.strokes = this.strokes
    this.draw()
    this.queueSave({ immediate: true })
  }

  handlePointerDown(event) {
    if (this.readonlyValue) return

    event.preventDefault()
    if (!this.fullscreenActive()) {
      this.enterFullscreen()
      return
    }

    this.capturePointer(event.pointerId)
    const point = this.pointFromEvent(event)
    this.activePointerId = event.pointerId

    if (this.tool === "eraser") {
      this.eraseAt(point)
      this.draw()
      return
    }

    this.activeStroke = {
      id: window.crypto?.randomUUID?.() || `${Date.now()}-${Math.random()}`,
      tool: this.tool,
      color: this.color,
      width: this.diameter,
      points: [ point ]
    }
    this.strokes.push(this.activeStroke)
    this.drawStrokeSegment(this.activeStroke, point, point)
  }

  handlePointerMove(event) {
    if (event.pointerId !== this.activePointerId) return

    event.preventDefault()
    const coalescedEvents = event.getCoalescedEvents?.()
    const pointerEvents = coalescedEvents?.length ? coalescedEvents : [ event ]

    if (this.tool === "eraser") {
      let erased = false
      for (const pointerEvent of pointerEvents) {
        erased = this.eraseAt(this.pointFromEvent(pointerEvent)) || erased
      }
      if (erased) this.draw()
      return
    }

    if (!this.activeStroke) return

    for (const pointerEvent of pointerEvents) {
      this.extendActiveStroke(this.pointFromEvent(pointerEvent))
    }
  }

  extendActiveStroke(point) {
    const previous = this.activeStroke.points[this.activeStroke.points.length - 1]
    if (this.distance(previous, point) < MIN_POINT_DISTANCE) return

    this.activeStroke.points.push(point)
    this.drawStrokeSegment(this.activeStroke, previous, point)
  }

  handlePointerUp(event) {
    if (event.pointerId !== this.activePointerId) return

    event.preventDefault()
    if (this.activeStroke) this.draw()
    this.activeStroke = null
    this.activePointerId = null
    this.releasePointer(event.pointerId)
    this.queueSave()
  }

  resizeCanvas() {
    const rect = this.canvasTarget.getBoundingClientRect()
    const width = Math.max(Math.floor(rect.width), 1)
    const height = Math.max(Math.floor(rect.height), 1)
    const pixelRatio = window.devicePixelRatio || 1

    if (this.canvasTarget.width !== Math.floor(width * pixelRatio)) {
      this.canvasTarget.width = Math.floor(width * pixelRatio)
    }
    if (this.canvasTarget.height !== Math.floor(height * pixelRatio)) {
      this.canvasTarget.height = Math.floor(height * pixelRatio)
    }

    this.canvasTarget.style.width = `${width}px`
    this.canvasTarget.style.height = `${height}px`
    this.context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0)
    this.draw({ width, height })
  }

  draw(size = this.currentCanvasSize()) {
    const { width, height } = size
    const context = this.context
    context.clearRect(0, 0, width, height)
    this.drawBackground(context, width, height)

    for (const stroke of this.strokes) {
      const points = Array.isArray(stroke.points) ? stroke.points : []
      if (!points.length) continue

      context.save()
      this.applyStrokeStyle(context, stroke)

      const first = this.scalePoint(points[0], width, height)
      if (points.length === 1) {
        context.beginPath()
        context.arc(first.x, first.y, context.lineWidth / 2, 0, Math.PI * 2)
        context.fill()
      } else {
        context.beginPath()
        context.moveTo(first.x, first.y)
        for (const point of points.slice(1)) {
          const scaled = this.scalePoint(point, width, height)
          context.lineTo(scaled.x, scaled.y)
        }
        context.stroke()
      }
      context.restore()
    }
  }

  drawStrokeSegment(stroke, startPoint, endPoint, size = this.currentCanvasSize()) {
    const { width, height } = size
    const context = this.context
    const start = this.scalePoint(startPoint, width, height)
    const end = this.scalePoint(endPoint, width, height)

    context.save()
    this.applyStrokeStyle(context, stroke)
    if (startPoint === endPoint || (start.x === end.x && start.y === end.y)) {
      context.beginPath()
      context.arc(end.x, end.y, context.lineWidth / 2, 0, Math.PI * 2)
      context.fill()
    } else {
      context.beginPath()
      context.moveTo(start.x, start.y)
      context.lineTo(end.x, end.y)
      context.stroke()
    }
    context.restore()
  }

  applyStrokeStyle(context, stroke) {
    const color = this.normalizedColor(stroke.color)
    const lineWidth = this.clampedDiameter(stroke.width)
    context.lineCap = "round"
    context.lineJoin = "round"
    context.strokeStyle = color
    context.fillStyle = color
    context.lineWidth = lineWidth
    if (stroke.tool === "marker") {
      context.globalAlpha = 0.38
      context.shadowColor = color
      context.shadowBlur = Math.max(1.5, lineWidth * 0.7)
    } else {
      context.globalAlpha = 1
      context.shadowBlur = 0
    }
  }

  drawBackground(context, width, height) {
    context.save()
    context.fillStyle = "#ffffff"
    context.fillRect(0, 0, width, height)
    context.strokeStyle = "#e5eef5"
    context.lineWidth = 1

    const grid = 32
    for (let x = 0; x <= width; x += grid) {
      context.beginPath()
      context.moveTo(x, 0)
      context.lineTo(x, height)
      context.stroke()
    }
    for (let y = 0; y <= height; y += grid) {
      context.beginPath()
      context.moveTo(0, y)
      context.lineTo(width, y)
      context.stroke()
    }
    context.restore()
  }

  eraseAt(point) {
    const radius = this.boardUnitsForPixels(this.diameter / 2)
    const originalLength = this.strokes.length
    this.strokes = this.strokes.filter((stroke) => !this.strokeTouchesPoint(stroke, point, radius))
    this.state.strokes = this.strokes
    if (this.strokes.length !== originalLength) {
      this.setStatus("Unsaved")
      return true
    }
    return false
  }

  strokeTouchesPoint(stroke, point, radius) {
    const points = Array.isArray(stroke.points) ? stroke.points : []
    if (!points.length) return false

    const strokeRadius = this.boardUnitsForPixels(this.clampedDiameter(stroke.width) / 2)
    const hitRadius = radius + strokeRadius

    if (points.length === 1) return this.distance(points[0], point) <= hitRadius

    return points.slice(1).some((candidate, index) => (
      this.distanceToSegment(point, points[index], candidate) <= hitRadius
    ))
  }

  queueSave({ immediate = false } = {}) {
    if (this.readonlyValue || !this.hasUrlValue) return

    window.clearTimeout(this.saveTimer)
    if (immediate) {
      this.save()
    } else {
      this.setStatus("Unsaved")
      this.saveTimer = window.setTimeout(() => this.save(), SAVE_DELAY_MS)
    }
  }

  async save() {
    this.setStatus("Saving")
    const content = this.serializedContent()

    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken()
        },
        body: JSON.stringify({ block: { content_json: content } })
      })

      if (!response.ok) throw new Error(`Save failed with status ${response.status}`)

      const payload = await response.json()
      this.state = this.normalizedState(payload.block?.content_json || content)
      this.strokes = this.state.strokes
      this.board = this.state.board
      this.setStatus("Saved")
    } catch (error) {
      this.setStatus("Could not save")
      console.error("[notae-whiteboard]", error)
    }
  }

  serializedContent() {
    const content = {
      ...this.state,
      type: "whiteboard",
      version: 1,
      board: this.board,
      strokes: this.strokes
    }
    delete content.whiteboard_autofocus
    return content
  }

  normalizedState(rawState) {
    const board = rawState.board && typeof rawState.board === "object" ? rawState.board : DEFAULT_BOARD
    return {
      ...rawState,
      type: "whiteboard",
      version: 1,
      board: {
        width: this.positiveNumber(board.width, DEFAULT_BOARD.width),
        height: this.positiveNumber(board.height, DEFAULT_BOARD.height)
      },
      strokes: this.normalizedStrokes(rawState.strokes)
    }
  }

  normalizedStrokes(strokes) {
    if (!Array.isArray(strokes)) return []

    return strokes.map((stroke) => ({
      id: stroke.id?.toString() || `${Date.now()}-${Math.random()}`,
      tool: [ "pencil", "marker" ].includes(stroke.tool) ? stroke.tool : "pencil",
      color: stroke.color?.toString() || DEFAULT_COLOR,
      width: this.clampedDiameter(stroke.width),
      points: Array.isArray(stroke.points) ? stroke.points.map((point) => ({
        x: this.positiveNumber(point.x, 0),
        y: this.positiveNumber(point.y, 0)
      })) : []
    })).filter((stroke) => stroke.points.length)
  }

  pointFromEvent(event) {
    const rect = this.canvasTarget.getBoundingClientRect()
    const x = ((event.clientX - rect.left) / Math.max(rect.width, 1)) * this.board.width
    const y = ((event.clientY - rect.top) / Math.max(rect.height, 1)) * this.board.height
    return {
      x: Math.min(Math.max(x, 0), this.board.width),
      y: Math.min(Math.max(y, 0), this.board.height)
    }
  }

  scalePoint(point, width, height) {
    return {
      x: (point.x / this.board.width) * width,
      y: (point.y / this.board.height) * height
    }
  }

  currentCanvasSize() {
    const rect = this.canvasTarget.getBoundingClientRect()
    return {
      width: Math.max(Math.floor(rect.width), 1),
      height: Math.max(Math.floor(rect.height), 1)
    }
  }

  updateToolButtons() {
    for (const button of this.toolButtonTargets) {
      button.classList.toggle("is-active", button.dataset.whiteboardToolParam === this.tool)
    }
  }

  updateColorButtons() {
    for (const button of this.colorButtonTargets) {
      button.classList.toggle("is-active", this.normalizedColor(button.dataset.whiteboardColorParam) === this.normalizedColor(this.color))
    }
  }

  updateColorInput() {
    if (this.hasColorInputTarget) this.colorInputTarget.value = this.normalizedColor(this.color)
  }

  updateDiameterControls() {
    if (this.hasDiameterInputTarget) this.diameterInputTarget.value = this.diameter
    if (this.hasDiameterValueTarget) this.diameterValueTarget.textContent = `${this.diameter}px`
  }

  normalizedColor(color) {
    const candidate = color?.toString().trim()
    return /^#[0-9a-f]{6}$/i.test(candidate) ? candidate.toLowerCase() : DEFAULT_COLOR
  }

  clampedDiameter(value) {
    const number = Number(value)
    if (!Number.isFinite(number)) return DEFAULT_DIAMETER
    return Math.min(Math.max(Math.round(number), MIN_DIAMETER), MAX_DIAMETER)
  }

  boardUnitsForPixels(pixels) {
    const { width, height } = this.currentCanvasSize()
    const scale = Math.max(this.board.width / width, this.board.height / height)
    return Math.max(pixels * scale, 0)
  }

  fullscreenActive() {
    return this.element.classList.contains("is-fullscreen")
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }

  capturePointer(pointerId) {
    try {
      this.canvasTarget.setPointerCapture?.(pointerId)
    } catch (_error) {
      // Synthetic pointer streams may not be capturable.
    }
  }

  releasePointer(pointerId = this.activePointerId) {
    if (pointerId === null || pointerId === undefined) return

    try {
      this.canvasTarget.releasePointerCapture?.(pointerId)
    } catch (_error) {
      // The pointer may already be released after cancellation.
    }
  }

  distance(first, second) {
    return Math.hypot(first.x - second.x, first.y - second.y)
  }

  distanceToSegment(point, start, end) {
    const dx = end.x - start.x
    const dy = end.y - start.y
    if (dx === 0 && dy === 0) return this.distance(point, start)

    const t = Math.max(0, Math.min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy)))
    return this.distance(point, {
      x: start.x + t * dx,
      y: start.y + t * dy
    })
  }

  positiveNumber(value, fallback) {
    const number = Number(value)
    return Number.isFinite(number) && number >= 0 ? number : fallback
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }
}
