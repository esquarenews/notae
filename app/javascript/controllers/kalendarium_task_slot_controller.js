import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "heading", "startInput", "endInput", "durationInput"]
  static values = {
    taskTitle: String,
    defaultDurationMinutes: Number
  }

  connect() {
    this.syncEndConstraints()
  }

  openCandidate(event) {
    event.preventDefault()

    const trigger = event.currentTarget
    if (!(trigger instanceof HTMLElement)) return

    this.openWith({
      startLocal: trigger.dataset.startLocal,
      endLocal: trigger.dataset.endLocal,
      label: trigger.dataset.slotLabel
    })
  }

  openDraft(event) {
    const detail = event.detail || {}
    this.openWith({
      startLocal: detail.startLocal,
      endLocal: detail.endLocal,
      label: detail.label || "Custom slot"
    })
  }

  close(event) {
    event?.preventDefault()
    if (!this.hasDialogTarget) return

    this.dialogTarget.close()
  }

  backdropClose(event) {
    if (!this.hasDialogTarget) return
    if (event.target !== this.dialogTarget) return

    this.dialogTarget.close()
  }

  startChanged() {
    this.syncEndConstraints()

    if (this.selectedDurationMinutes() !== null) {
      this.applyDurationMinutes(this.selectedDurationMinutes())
      return
    }

    this.syncDurationSelection()
  }

  endChanged() {
    this.syncEndConstraints()
    this.syncDurationSelection()
  }

  durationChanged() {
    const durationMinutes = this.selectedDurationMinutes()
    if (durationMinutes === null) return

    this.applyDurationMinutes(durationMinutes)
  }

  openWith({ startLocal, endLocal, label }) {
    if (!this.hasDialogTarget || !this.hasStartInputTarget || !this.hasEndInputTarget) return
    if (!startLocal || !endLocal) return

    this.startInputTarget.value = startLocal
    this.endInputTarget.value = endLocal
    this.syncEndConstraints()
    this.syncDurationSelection()

    if (this.hasHeadingTarget) {
      const title = this.hasTaskTitleValue ? this.taskTitleValue : "task"
      const labelSuffix = label ? ` · ${label}` : ""
      this.headingTarget.textContent = `Schedule ${title}${labelSuffix}`
    }

    if (!this.dialogTarget.open) {
      this.dialogTarget.showModal()
    }

    window.requestAnimationFrame(() => {
      this.startInputTarget.focus()
    })
  }

  syncEndConstraints() {
    if (!this.hasStartInputTarget || !this.hasEndInputTarget) return
    if (!this.startInputTarget.value) return

    this.endInputTarget.min = this.startInputTarget.value
    if (this.endInputTarget.value && this.endInputTarget.value < this.startInputTarget.value) {
      this.endInputTarget.value = this.startInputTarget.value
    }
  }

  syncDurationSelection() {
    if (!this.hasDurationInputTarget) return

    const currentDuration = this.currentDurationMinutes()
    if (currentDuration === null) {
      this.durationInputTarget.value = String(this.defaultDuration())
      return
    }

    const normalizedDuration = String(currentDuration)
    const availableOption = Array.from(this.durationInputTarget.options).find((option) => option.value === normalizedDuration)
    this.durationInputTarget.value = availableOption ? normalizedDuration : "custom"
  }

  selectedDurationMinutes() {
    if (!this.hasDurationInputTarget) return this.defaultDuration()
    if (this.durationInputTarget.value === "custom") return null

    const parsed = Number.parseInt(this.durationInputTarget.value, 10)
    return Number.isNaN(parsed) ? this.defaultDuration() : parsed
  }

  currentDurationMinutes() {
    const start = this.parseLocalDateTime(this.startInputTarget?.value)
    const ending = this.parseLocalDateTime(this.endInputTarget?.value)
    if (!start || !ending || ending <= start) return null

    return Math.round((ending - start) / 60000)
  }

  applyDurationMinutes(durationMinutes) {
    if (!this.hasStartInputTarget || !this.hasEndInputTarget) return

    const start = this.parseLocalDateTime(this.startInputTarget.value)
    if (!start) return

    const ending = new Date(start.getTime() + (durationMinutes * 60000))
    this.endInputTarget.value = this.formatLocalDateTime(ending)
    this.syncEndConstraints()
  }

  parseLocalDateTime(value) {
    if (!value) return null

    const parsed = new Date(value)
    return Number.isNaN(parsed.getTime()) ? null : parsed
  }

  formatLocalDateTime(date) {
    const year = String(date.getFullYear())
    const month = String(date.getMonth() + 1).padStart(2, "0")
    const day = String(date.getDate()).padStart(2, "0")
    const hours = String(date.getHours()).padStart(2, "0")
    const minutes = String(date.getMinutes()).padStart(2, "0")
    return `${year}-${month}-${day}T${hours}:${minutes}`
  }

  defaultDuration() {
    return this.hasDefaultDurationMinutesValue ? this.defaultDurationMinutesValue : 20
  }
}
