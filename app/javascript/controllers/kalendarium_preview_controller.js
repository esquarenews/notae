import { Controller } from "@hotwired/stimulus"

const TIMELINE_SLOT_MINUTES = 30
const TIMELINE_MIN_DURATION_MINUTES = 30
const TIMELINE_DAY_MINUTES = 24 * 60

export default class extends Controller {
  connect() {
    this.onPointerMove = (event) => this.drag(event)
    this.onPointerUp = (event) => this.finishDrag(event)
    this.onPointerCancel = (event) => this.cancelDrag(event)
    this.previewElement = null
    this.currentDetail = null
    this.dragState = null
  }

  disconnect() {
    this.teardownDrag()
    this.clear()
  }

  render(event) {
    const detail = event.detail || {}
    if (detail.allDay) {
      this.clear()
      return
    }

    const previewRange = this.previewRangeFor(detail)
    if (!previewRange) {
      this.clear()
      return
    }

    const track = this.trackElementsFor(previewRange.date)[0]
    if (!(track instanceof HTMLElement)) {
      this.clear()
      return
    }

    this.currentDetail = {
      title: detail.title || "",
      date: previewRange.date,
      startLocal: detail.startLocal,
      endLocal: detail.endLocal,
      allDay: Boolean(detail.allDay)
    }

    this.renderPreview(track, this.currentDetail, previewRange)
  }

  clear() {
    this.teardownDrag()
    this.element.querySelectorAll(".notae-kalendarium-draft-preview").forEach((preview) => preview.remove())
    this.previewElement = null
    this.currentDetail = null
  }

  trackElementsFor(dateString) {
    const selector = `.notae-kalendarium-day-track[data-day-date="${dateString}"], .notae-kalendarium-week-day-track[data-day-date="${dateString}"]`
    return Array.from(this.element.querySelectorAll(selector))
  }

  renderPreview(track, detail, previewRange) {
    const layer = track.querySelector(".notae-kalendarium-events-layer")
    if (!(layer instanceof HTMLElement)) return

    const preview = this.previewElement || document.createElement("div")
    preview.className = "notae-kalendarium-draft-preview"
    preview.dataset.action = "pointerdown->kalendarium-preview#beginDrag"
    preview.dataset.date = previewRange.date
    preview.dataset.startMinutes = String(previewRange.startMinutes)
    preview.dataset.endMinutes = String(previewRange.endMinutes)
    preview.dataset.durationMinutes = String(previewRange.endMinutes - previewRange.startMinutes)
    preview.setAttribute("aria-hidden", "true")
    preview.style.top = `${this.timelinePixelsForMinutes(track, previewRange.startMinutes)}px`
    preview.style.height = `${this.timelinePixelsForMinutes(track, previewRange.endMinutes - previewRange.startMinutes)}px`

    const label = document.createElement("div")
    label.className = "notae-kalendarium-draft-preview-label"
    label.textContent = detail.title?.trim() || "Draft event"
    const children = [ label ]

    if (this.hasConflict(track, previewRange.startMinutes, previewRange.endMinutes)) {
      preview.classList.add("has-conflict")
      const conflict = document.createElement("div")
      conflict.className = "notae-kalendarium-draft-preview-conflict"
      conflict.textContent = "Possible conflict"
      children.push(conflict)
    } else {
      preview.classList.remove("has-conflict")
    }

    preview.replaceChildren(...children)

    if (preview.parentElement !== layer) {
      layer.prepend(preview)
    }

    this.previewElement = preview
  }

  hasConflict(track, startMinutes, endMinutes) {
    return Array.from(track.querySelectorAll(".notae-kalendarium-event-card.is-timeline[data-start-minutes][data-end-minutes]")).some((card) => {
      const existingStart = Number.parseInt(card.dataset.startMinutes, 10)
      const existingEnd = Number.parseInt(card.dataset.endMinutes, 10)
      if (Number.isNaN(existingStart) || Number.isNaN(existingEnd)) return false

      return startMinutes < existingEnd && endMinutes > existingStart
    })
  }

  previewRangeFor(detail) {
    const startParts = this.parseLocalDateTime(detail.startLocal)
    const endParts = this.parseLocalDateTime(detail.endLocal)
    if (!startParts || !endParts) return null

    const dateString = detail.date || startParts.date
    if (!dateString || startParts.date !== dateString) return null
    if (endParts.date < dateString) return null

    const startMinutes = this.clampMinutes(this.minutesFor(startParts.hour, startParts.minute), 0, TIMELINE_DAY_MINUTES - TIMELINE_MIN_DURATION_MINUTES)
    let endMinutes = endParts.date > dateString ? TIMELINE_DAY_MINUTES : this.minutesFor(endParts.hour, endParts.minute)
    endMinutes = this.clampMinutes(endMinutes, startMinutes + TIMELINE_MIN_DURATION_MINUTES, TIMELINE_DAY_MINUTES)

    return {
      date: dateString,
      startMinutes,
      endMinutes
    }
  }

  parseLocalDateTime(value) {
    if (!value) return null

    const [date, time] = value.split("T")
    const [hourString, minuteString] = (time || "").split(":")
    const hour = Number.parseInt(hourString, 10)
    const minute = Number.parseInt(minuteString, 10)
    if (!date || Number.isNaN(hour) || Number.isNaN(minute)) return null

    return { date, hour, minute }
  }

  minutesFor(hour, minute) {
    return (hour * 60) + minute
  }

  timelinePixelsForMinutes(track, minutes) {
    const style = window.getComputedStyle(track)
    const slotHeight = Number.parseFloat(style.getPropertyValue("--kal-slot-height")) || 28
    return (minutes / TIMELINE_SLOT_MINUTES) * slotHeight
  }

  clampMinutes(value, minimum, maximum) {
    return Math.min(Math.max(value, minimum), maximum)
  }

  beginDrag(event) {
    if (event.button !== 0) return

    const preview = event.currentTarget
    if (!(preview instanceof HTMLElement)) return
    if (!this.currentDetail) return

    event.preventDefault()

    const previewRect = preview.getBoundingClientRect()
    const durationMinutes = Number.parseInt(preview.dataset.durationMinutes, 10)

    this.dragState = {
      pointerId: event.pointerId,
      offsetY: event.clientY - previewRect.top,
      durationMinutes: Number.isNaN(durationMinutes) ? TIMELINE_MIN_DURATION_MINUTES : durationMinutes,
      detail: { ...this.currentDetail },
      preview
    }

    preview.classList.add("is-dragging")
    preview.setPointerCapture?.(event.pointerId)

    window.addEventListener("pointermove", this.onPointerMove)
    window.addEventListener("pointerup", this.onPointerUp)
    window.addEventListener("pointercancel", this.onPointerCancel)
  }

  drag(event) {
    if (!this.dragState || event.pointerId !== this.dragState.pointerId) return

    const track = this.trackAtPoint(event.clientX, event.clientY)
    if (!(track instanceof HTMLElement)) return

    const detail = this.detailForDrag(track, event.clientY)
    const previewRange = this.previewRangeFor(detail)
    if (!previewRange) return

    this.dragState.detail = detail
    this.currentDetail = detail
    this.renderPreview(track, detail, previewRange)
    this.previewElement?.classList.add("is-dragging")
  }

  finishDrag(event) {
    if (!this.dragState || event.pointerId !== this.dragState.pointerId) return

    const finalDetail = this.dragState.detail
    this.teardownDrag()
    if (!finalDetail) return

    this.element.dispatchEvent(new CustomEvent("kalendarium:quick-create", {
      bubbles: true,
      detail: finalDetail
    }))
  }

  cancelDrag(event) {
    if (!this.dragState || event.pointerId !== this.dragState.pointerId) return

    this.teardownDrag()
    if (this.currentDetail) {
      this.render({ detail: this.currentDetail })
    }
  }

  teardownDrag() {
    if (this.dragState?.preview instanceof HTMLElement && this.dragState.pointerId !== undefined) {
      this.dragState.preview.classList.remove("is-dragging")
      if (this.dragState.preview.hasPointerCapture?.(this.dragState.pointerId)) {
        this.dragState.preview.releasePointerCapture(this.dragState.pointerId)
      }
    }

    window.removeEventListener("pointermove", this.onPointerMove)
    window.removeEventListener("pointerup", this.onPointerUp)
    window.removeEventListener("pointercancel", this.onPointerCancel)
    this.dragState = null
  }

  trackAtPoint(clientX, clientY) {
    const pointTarget = document.elementFromPoint(clientX, clientY)
    if (!(pointTarget instanceof Element)) return null

    return pointTarget.closest(".notae-kalendarium-day-track, .notae-kalendarium-week-day-track")
  }

  detailForDrag(track, clientY) {
    if (!this.dragState) return null

    const dateString = track.dataset.dayDate
    if (!dateString) return null

    const style = window.getComputedStyle(track)
    const slotHeight = Number.parseFloat(style.getPropertyValue("--kal-slot-height")) || 28
    const allDayOffset = Number.parseFloat(style.getPropertyValue("--kal-all-day-offset")) || 0
    const rect = track.getBoundingClientRect()
    const topWithinTrack = clientY - rect.top - this.dragState.offsetY
    const usableY = Math.max(topWithinTrack - allDayOffset, 0)
    const snappedMinutes = Math.round(usableY / slotHeight) * TIMELINE_SLOT_MINUTES
    const maxStart = Math.max(TIMELINE_DAY_MINUTES - this.dragState.durationMinutes, 0)
    const startMinutes = this.clampMinutes(snappedMinutes, 0, maxStart)
    const endMinutes = startMinutes + this.dragState.durationMinutes

    return {
      title: this.dragState.detail.title,
      date: dateString,
      startLocal: this.localTimestampFor(dateString, startMinutes),
      endLocal: this.localTimestampFor(dateString, endMinutes),
      allDay: false
    }
  }

  localTimestampFor(dateString, minutesIntoDay) {
    const [year, month, day] = dateString.split("-").map((part) => Number.parseInt(part, 10))
    if (!year || !month || !day) return ""

    const baseDate = new Date(year, month - 1, day, 0, 0, 0, 0)
    baseDate.setMinutes(minutesIntoDay)

    const formattedYear = String(baseDate.getFullYear())
    const formattedMonth = String(baseDate.getMonth() + 1).padStart(2, "0")
    const formattedDay = String(baseDate.getDate()).padStart(2, "0")
    const formattedHour = String(baseDate.getHours()).padStart(2, "0")
    const formattedMinute = String(baseDate.getMinutes()).padStart(2, "0")
    return `${formattedYear}-${formattedMonth}-${formattedDay}T${formattedHour}:${formattedMinute}`
  }
}
