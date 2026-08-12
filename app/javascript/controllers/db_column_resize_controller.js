import { Controller } from "@hotwired/stimulus"

const MAX_COLUMN_WIDTH = 960
const MIN_NAME_COLUMN_WIDTH = 180
const MIN_PROPERTY_COLUMN_WIDTH = 120

export default class extends Controller {
  static targets = ["column", "header"]
  static values = {
    enabled: Boolean,
    updateUrl: String,
    widths: Object
  }

  connect() {
    this.activeColumnKey = null
    this.startX = 0
    this.startWidth = 0
    this.pendingWidths = {}
    this.pointerMoveHandler = this.onPointerMove.bind(this)
    this.pointerUpHandler = this.onPointerUp.bind(this)
    this.applyPersistedWidths()
  }

  disconnect() {
    this.removePointerListeners()
    document.body.classList.remove("notae-is-col-resizing")
  }

  startResize(event) {
    if (!this.enabledValue) return

    const header = event.currentTarget.closest("th[data-column-key]")
    if (!header) return

    const columnKey = header.dataset.columnKey
    if (!columnKey) return

    // A <col> does not have reliable element geometry across browsers. In
    // Chromium it can report the width of the whole table before its first
    // inline width is applied, which immediately clamps the dragged column to
    // MAX_COLUMN_WIDTH. The rendered header cell is the actual drag surface
    // and gives us a stable starting width.
    const measuredWidth = header.getBoundingClientRect().width
    this.activeColumnKey = columnKey
    this.startX = event.clientX
    this.startWidth = measuredWidth
    this.pendingWidths = { ...this.pendingWidths, [columnKey]: Math.round(measuredWidth) }

    document.body.classList.add("notae-is-col-resizing")
    this.element.classList.add("is-column-resizing")
    this.addPointerListeners()
    event.preventDefault()
  }

  onPointerMove(event) {
    if (!this.activeColumnKey) return

    const delta = event.clientX - this.startX
    const minimumWidth = this.minimumWidthForColumn(this.activeColumnKey)
    const nextWidth = this.clampWidth(this.startWidth + delta, minimumWidth)
    this.applyWidth(this.activeColumnKey, nextWidth)
  }

  onPointerUp() {
    if (!this.activeColumnKey) {
      this.removePointerListeners()
      document.body.classList.remove("notae-is-col-resizing")
      this.element.classList.remove("is-column-resizing")
      return
    }

    this.activeColumnKey = null
    this.removePointerListeners()
    document.body.classList.remove("notae-is-col-resizing")
    this.element.classList.remove("is-column-resizing")
    this.persistWidths()
  }

  addPointerListeners() {
    window.addEventListener("pointermove", this.pointerMoveHandler)
    window.addEventListener("pointerup", this.pointerUpHandler)
  }

  removePointerListeners() {
    window.removeEventListener("pointermove", this.pointerMoveHandler)
    window.removeEventListener("pointerup", this.pointerUpHandler)
  }

  applyPersistedWidths() {
    const widths = this.widthsValue || {}
    Object.entries(widths).forEach(([columnKey, rawWidth]) => {
      const minimumWidth = this.minimumWidthForColumn(columnKey)
      if (!minimumWidth) return

      const parsedWidth = Number.parseInt(rawWidth, 10)
      if (!Number.isFinite(parsedWidth)) return

      this.applyWidth(columnKey, this.clampWidth(parsedWidth, minimumWidth))
    })
  }

  applyWidth(columnKey, width) {
    const roundedWidth = Math.round(width)
    const pixelWidth = `${roundedWidth}px`
    const column = this.findColumnByKey(columnKey)
    const header = this.findHeaderByKey(columnKey)

    if (column) {
      column.style.width = pixelWidth
      column.style.minWidth = pixelWidth
    }

    if (header) {
      header.style.width = pixelWidth
      header.style.minWidth = pixelWidth
    }

    this.pendingWidths[columnKey] = roundedWidth
  }

  findColumnByKey(columnKey) {
    return this.columnTargets.find((node) => node.dataset.columnKey === columnKey)
  }

  findHeaderByKey(columnKey) {
    return this.headerTargets.find((node) => node.dataset.columnKey === columnKey)
  }

  minimumWidthForColumn(columnKey) {
    if (columnKey === "name") return MIN_NAME_COLUMN_WIDTH
    if (columnKey.startsWith("property_")) return MIN_PROPERTY_COLUMN_WIDTH
    return null
  }

  clampWidth(width, minWidth) {
    return Math.min(MAX_COLUMN_WIDTH, Math.max(minWidth, width))
  }

  async persistWidths() {
    if (!this.enabledValue || !this.updateUrlValue) return

    const payload = {
      database_view: {
        column_widths: this.pendingWidths
      }
    }

    const response = await fetch(this.updateUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": this.csrfToken
      },
      body: JSON.stringify(payload)
    })
    if (!response.ok) return

    this.widthsValue = { ...this.pendingWidths }
  }

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }
}
