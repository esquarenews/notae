import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submit", "progress", "status"]
  static values = {
    busyText: { type: String, default: "Creating account..." },
    statusText: { type: String, default: "Creating your account. This can take a moment." }
  }

  submit() {
    this.element.classList.add("is-submitting")
    this.element.setAttribute("aria-busy", "true")

    if (this.hasSubmitTarget) {
      this.submitTarget.dataset.originalValue = this.submitTarget.value
      this.submitTarget.value = this.busyTextValue
      this.submitTarget.disabled = true
    }

    if (this.hasProgressTarget) {
      this.progressTarget.hidden = false
    }

    if (this.hasStatusTarget) {
      this.statusTarget.textContent = this.statusTextValue
    }
  }
}
