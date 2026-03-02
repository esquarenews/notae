import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["startInput", "endInput", "allDayInput"]
  static values = {
    enforceFutureEnd: { type: Boolean, default: false }
  }

  connect() {
    if (this.allDaySelected) {
      this.applyAllDayTimes()
    }

    this.syncEndConstraints()
  }

  startChanged() {
    if (this.allDaySelected) {
      this.normalizeStartTimeToDayBoundary()
      this.normalizeEndTimeToDayBoundary()
    }

    this.syncEndConstraints()
  }

  endChanged() {
    if (this.allDaySelected) {
      this.normalizeEndTimeToDayBoundary()
    }

    this.syncEndConstraints()
  }

  toggleAllDay() {
    if (this.allDaySelected) {
      this.applyAllDayTimes()
    }

    this.syncEndConstraints()
  }

  applyAllDayTimes() {
    this.normalizeStartTimeToDayBoundary()
    this.normalizeEndTimeToDayBoundary()
  }

  normalizeStartTimeToDayBoundary() {
    if (!this.hasStartInputTarget) return

    const startDate = this.datePortion(this.startInputTarget.value)
    if (!startDate) return

    this.startInputTarget.value = `${startDate}T00:00`
  }

  normalizeEndTimeToDayBoundary() {
    if (!this.hasEndInputTarget) return

    const startDate = this.hasStartInputTarget ? this.datePortion(this.startInputTarget.value) : null
    const endDate = this.datePortion(this.endInputTarget.value)
    const chosenDate = this.maxDateString(startDate, endDate)
    if (!chosenDate) return

    this.endInputTarget.value = `${chosenDate}T23:59`
  }

  syncEndConstraints() {
    if (!this.hasEndInputTarget) return

    if (this.enforceFutureEndValue) {
      let minimum = this.nowLocalTimestamp()
      if (this.hasStartInputTarget && this.startInputTarget.value) {
        minimum = this.maxDateTimeString(minimum, this.startInputTarget.value)
      }

      this.endInputTarget.min = minimum
      if (this.endInputTarget.value && this.endInputTarget.value < minimum) {
        this.endInputTarget.value = minimum
      }
      return
    }

    if (this.hasStartInputTarget && this.startInputTarget.value) {
      this.endInputTarget.min = this.startInputTarget.value
      if (this.endInputTarget.value && this.endInputTarget.value < this.startInputTarget.value) {
        this.endInputTarget.value = this.startInputTarget.value
      }
      return
    }

    this.endInputTarget.removeAttribute("min")
  }

  get allDaySelected() {
    return this.hasAllDayInputTarget && this.allDayInputTarget.checked
  }

  nowLocalTimestamp() {
    const now = new Date()
    const year = now.getFullYear()
    const month = String(now.getMonth() + 1).padStart(2, "0")
    const day = String(now.getDate()).padStart(2, "0")
    const hours = String(now.getHours()).padStart(2, "0")
    const minutes = String(now.getMinutes()).padStart(2, "0")
    return `${year}-${month}-${day}T${hours}:${minutes}`
  }

  datePortion(value) {
    if (!value) return null

    const parts = value.split("T")
    return parts[0] || null
  }

  maxDateString(firstDate, secondDate) {
    if (firstDate && secondDate) return firstDate >= secondDate ? firstDate : secondDate
    return firstDate || secondDate || null
  }

  maxDateTimeString(firstValue, secondValue) {
    if (firstValue && secondValue) return firstValue >= secondValue ? firstValue : secondValue
    return firstValue || secondValue || ""
  }
}
