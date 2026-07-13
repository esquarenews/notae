import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "period", "startDate", "endDate" ]

  submit() {
    this.element.requestSubmit()
  }

  prepareCustomRange(event) {
    if (this.hasPeriodTarget) this.periodTarget.value = "custom"

    if (event.target === this.startDateTarget && this.hasEndDateTarget) {
      this.endDateTarget.min = this.startDateTarget.value
    } else if (event.target === this.endDateTarget && this.hasStartDateTarget) {
      this.startDateTarget.max = this.endDateTarget.value
    }
  }
}
