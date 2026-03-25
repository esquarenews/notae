import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["titleInput", "startInput", "endInput", "allDayInput"]
  static values = {
    enforceFutureEnd: { type: Boolean, default: false },
    previewEnabled: { type: Boolean, default: false }
  }

  connect() {
    this.onAccordionToggle = () => this.accordionToggled()
    this.accordionElement = this.element.closest("details")
    if (this.previewEnabledValue && this.accordionElement) {
      this.accordionElement.addEventListener("toggle", this.onAccordionToggle)
    }

    if (this.allDaySelected) {
      this.applyAllDayTimes()
    }

    this.syncEndConstraints()
    this.publishPreview()
  }

  disconnect() {
    if (this.previewEnabledValue && this.accordionElement) {
      this.accordionElement.removeEventListener("toggle", this.onAccordionToggle)
    }

    this.clearPreview()
  }

  cancel(event) {
    event?.preventDefault()

    if (typeof this.element.reset === "function") {
      this.element.reset()
    }

    const selectedDate = this.selectedDateValue()
    if (selectedDate) {
      if (this.hasStartInputTarget) {
        this.startInputTarget.value = `${selectedDate}T09:00`
      }

      if (this.hasEndInputTarget) {
        this.endInputTarget.value = `${selectedDate}T10:00`
      }
    }

    this.syncEndConstraints()
    this.clearPreview()

    if (this.accordionElement) {
      this.accordionElement.open = false
    }
  }

  titleChanged() {
    this.publishPreview()
  }

  startChanged() {
    if (this.allDaySelected) {
      this.normalizeStartTimeToDayBoundary()
      this.normalizeEndTimeToDayBoundary()
    }

    this.syncEndConstraints()
    this.publishPreview()
  }

  endChanged() {
    if (this.allDaySelected) {
      this.normalizeEndTimeToDayBoundary()
    }

    this.syncEndConstraints()
    this.publishPreview()
  }

  toggleAllDay() {
    if (this.allDaySelected) {
      this.applyAllDayTimes()
    }

    this.syncEndConstraints()
    this.publishPreview()
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

  accordionToggled() {
    if (this.accordionElement?.open) {
      this.publishPreview()
    } else {
      this.clearPreview()
    }
  }

  publishPreview() {
    if (!this.previewEnabledValue) return
    if (this.accordionElement && !this.accordionElement.open) {
      this.clearPreview()
      return
    }

    const detail = this.previewDetail()
    if (!detail) {
      this.clearPreview()
      return
    }

    this.dispatchPreview("kalendarium:preview-event", detail)
  }

  clearPreview() {
    if (!this.previewEnabledValue) return

    this.dispatchPreview("kalendarium:preview-clear", {})
  }

  previewDetail() {
    if (!this.hasStartInputTarget || !this.hasEndInputTarget) return null
    if (!this.startInputTarget.value || !this.endInputTarget.value) return null

    const dateString = this.datePortion(this.startInputTarget.value)
    if (!dateString) return null

    return {
      title: this.hasTitleInputTarget ? this.titleInputTarget.value : "",
      date: dateString,
      startLocal: this.startInputTarget.value,
      endLocal: this.endInputTarget.value,
      allDay: this.allDaySelected
    }
  }

  dispatchPreview(name, detail) {
    const shell = this.element.closest(".notae-kalendarium")
    if (!shell) return

    shell.dispatchEvent(new CustomEvent(name, {
      bubbles: true,
      detail
    }))
  }

  selectedDateValue() {
    const dateInput = this.element.querySelector("input[name='date']")
    const selectedDate = this.datePortion(dateInput?.value)
    if (selectedDate) return selectedDate

    return this.hasStartInputTarget ? this.datePortion(this.startInputTarget.value) : null
  }
}
