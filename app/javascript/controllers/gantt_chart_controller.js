import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.pointerMoveHandler = this.onPointerMove.bind(this)
    this.pointerUpHandler = this.onPointerUp.bind(this)
    this.activeInteraction = null
  }

  disconnect() {
    this.stopTracking()
  }

  startMove(event) {
    if (event.target.closest(".notae-db-gantt-bar-handle")) return

    this.beginInteraction(event, { mode: "move" })
  }

  startResize(event) {
    const direction = event.currentTarget.dataset.resizeDirection === "start" ? "resize-start" : "resize-end"
    this.beginInteraction(event, { mode: direction })
  }

  beginInteraction(event, { mode }) {
    const wrap = event.currentTarget.closest(".notae-db-gantt-bar-wrap")
    const track = wrap?.closest(".notae-db-gantt-track")
    if (!wrap || !track) return

    this.activeInteraction = {
      mode: mode,
      wrap: wrap,
      track: track,
      rowId: wrap.dataset.ganttRowId,
      chartStartDate: wrap.dataset.chartStartDate,
      originalStartDate: wrap.dataset.startDate,
      originalEndDate: wrap.dataset.endDate,
      previewStartDate: wrap.dataset.startDate,
      previewEndDate: wrap.dataset.endDate,
      originalWidth: wrap.style.width,
      originalLeft: wrap.style.left,
      totalDays: Number.parseInt(wrap.dataset.totalDays, 10) || 1,
      startPropertyId: wrap.dataset.startPropertyId,
      endPropertyId: wrap.dataset.endPropertyId,
      updateUrl: wrap.dataset.updateUrl,
      startX: event.clientX
    }

    wrap.classList.add("is-resizing")
    window.addEventListener("pointermove", this.pointerMoveHandler)
    window.addEventListener("pointerup", this.pointerUpHandler)
    event.preventDefault()
    event.stopPropagation()
  }

  onPointerMove(event) {
    if (!this.activeInteraction) return

    const interaction = this.activeInteraction
    const trackWidth = interaction.track.getBoundingClientRect().width
    if (trackWidth <= 0) return

    const dayWidth = trackWidth / Math.max(interaction.totalDays, 1)
    const deltaDays = Math.round((event.clientX - interaction.startX) / Math.max(dayWidth, 1))

    let nextStartDate = interaction.originalStartDate
    let nextEndDate = interaction.originalEndDate

    if (interaction.mode === "move") {
      nextStartDate = this.addDays(interaction.originalStartDate, deltaDays)
      nextEndDate = this.addDays(interaction.originalEndDate, deltaDays)
    } else if (interaction.mode === "resize-start") {
      nextStartDate = this.addDays(interaction.originalStartDate, deltaDays)
      if (nextStartDate > interaction.originalEndDate) {
        nextStartDate = interaction.originalEndDate
      }
    } else {
      nextEndDate = this.addDays(interaction.originalEndDate, deltaDays)
      if (nextEndDate < interaction.originalStartDate) {
        nextEndDate = interaction.originalStartDate
      }
    }

    this.applyPreview(interaction, nextStartDate, nextEndDate)
  }

  async onPointerUp() {
    if (!this.activeInteraction) {
      this.stopTracking()
      return
    }

    const interaction = this.activeInteraction
    const nextStartDate = interaction.previewStartDate
    const nextEndDate = interaction.previewEndDate
    this.stopTracking()

    if (nextStartDate === interaction.originalStartDate && nextEndDate === interaction.originalEndDate) {
      this.restoreOriginalPosition(interaction)
      return
    }

    const response = await fetch(interaction.updateUrl, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": this.csrfToken
      },
      body: JSON.stringify({
        start_property_id: interaction.startPropertyId,
        end_property_id: interaction.endPropertyId,
        start_date: nextStartDate,
        end_date: nextEndDate
      })
    })

    if (!response.ok) {
      this.restoreOriginalPosition(interaction)
      return
    }

    this.syncGridDateField(interaction.rowId, interaction.startPropertyId, nextStartDate)
    this.syncGridDateField(interaction.rowId, interaction.endPropertyId, nextEndDate)
    this.refreshCurrentPage()
  }

  async updateRowColor(event) {
    const input = event.currentTarget
    const rowId = input.dataset.ganttRowId || ""
    const updateUrl = input.dataset.updateUrl
    if (!updateUrl || !rowId) return

    const response = await fetch(updateUrl, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": this.csrfToken
      },
      body: JSON.stringify({
        db_row: {
          style_action: "set_gantt_color",
          gantt_color_hex: input.value
        }
      })
    })

    if (!response.ok) return

    this.syncRowColor(rowId, input.value)
  }

  stopTracking() {
    if (this.activeInteraction?.wrap) {
      this.activeInteraction.wrap.classList.remove("is-resizing")
    }

    window.removeEventListener("pointermove", this.pointerMoveHandler)
    window.removeEventListener("pointerup", this.pointerUpHandler)
    this.activeInteraction = null
  }

  applyPreview(interaction, startDate, endDate) {
    interaction.previewStartDate = startDate
    interaction.previewEndDate = endDate

    const offsetDays = this.daysBetween(interaction.chartStartDate, startDate)
    const lengthDays = this.daysBetween(startDate, endDate) + 1
    interaction.wrap.style.left = `${((offsetDays / Math.max(interaction.totalDays, 1)) * 100).toFixed(4)}%`
    interaction.wrap.style.width = `${((lengthDays / Math.max(interaction.totalDays, 1)) * 100).toFixed(4)}%`
  }

  restoreOriginalPosition(interaction) {
    interaction.wrap.style.left = interaction.originalLeft
    interaction.wrap.style.width = interaction.originalWidth
  }

  syncRowColor(rowId, colorValue) {
    const rowSelector = `[data-gantt-row-id="${this.escapeSelector(rowId)}"]`
    this.element.querySelectorAll(`${rowSelector} input[type="color"][data-gantt-row-id]`).forEach((node) => {
      node.value = colorValue
    })

    this.element.querySelectorAll(`${rowSelector} .notae-db-gantt-bar`).forEach((node) => {
      node.style.setProperty("--notae-gantt-bar-color", colorValue)
    })
  }

  syncGridDateField(rowId, propertyId, value) {
    this.element.ownerDocument.querySelectorAll("[data-gantt-grid-row-id][data-gantt-grid-property-id]").forEach((field) => {
      if (field.dataset.ganttGridRowId !== rowId) return
      if (field.dataset.ganttGridPropertyId !== propertyId) return

      field.value = value
    })
  }

  refreshCurrentPage() {
    if (window.Turbo?.visit) {
      window.Turbo.visit(window.location.href, { action: "replace" })
    } else {
      window.location.reload()
    }
  }

  daysBetween(startIso, endIso) {
    const startDate = this.parseIsoDate(startIso)
    const endDate = this.parseIsoDate(endIso)
    if (!startDate || !endDate) return 0

    return Math.round((endDate - startDate) / 86400000)
  }

  addDays(isoDate, deltaDays) {
    const date = this.parseIsoDate(isoDate)
    if (!date) return isoDate

    date.setDate(date.getDate() + deltaDays)
    return this.formatIsoDate(date)
  }

  parseIsoDate(value) {
    if (!value) return null

    const [year, month, day] = value.split("-").map((part) => Number.parseInt(part, 10))
    if (!year || !month || !day) return null

    return new Date(year, month - 1, day, 12, 0, 0, 0)
  }

  formatIsoDate(date) {
    const year = String(date.getFullYear())
    const month = String(date.getMonth() + 1).padStart(2, "0")
    const day = String(date.getDate()).padStart(2, "0")
    return `${year}-${month}-${day}`
  }

  escapeSelector(value) {
    if (window.CSS?.escape) return window.CSS.escape(value)

    return String(value).replace(/["\\]/g, "\\$&")
  }

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }
}
