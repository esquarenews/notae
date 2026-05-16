import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["startDate", "endDate"]

  connect() {
    this.submitTimer = null
  }

  disconnect() {
    this.clearSubmitTimer()
  }

  submit() {
    this.requestSubmit()
  }

  submitFromPeriodInput() {
    this.clearDateRange()
    this.clearSubmitTimer()
    this.submitTimer = window.setTimeout(() => this.requestSubmit(), 150)
  }

  submitFromPeriodChange() {
    this.clearDateRange()
    this.clearSubmitTimer()
    this.requestSubmit()
  }

  clearDateRange() {
    if (this.hasStartDateTarget) this.startDateTarget.value = ""
    if (this.hasEndDateTarget) this.endDateTarget.value = ""
  }

  clearSubmitTimer() {
    if (!this.submitTimer) return

    window.clearTimeout(this.submitTimer)
    this.submitTimer = null
  }

  requestSubmit() {
    this.element.requestSubmit()
  }
}
