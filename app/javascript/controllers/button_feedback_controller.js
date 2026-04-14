import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    activeText: { type: String, default: "Working..." },
    duration: { type: Number, default: 1800 }
  }

  flash(event) {
    const button = event?.currentTarget || this.element
    const label = button.querySelector("[data-button-feedback-label]") || button

    if (!label.dataset.originalText) {
      label.dataset.originalText = label.textContent
    }

    window.clearTimeout(this.timeoutId)
    label.textContent = this.activeTextValue
    button.setAttribute("aria-busy", "true")
    button.classList.add("is-working")

    this.timeoutId = window.setTimeout(() => {
      label.textContent = label.dataset.originalText
      button.removeAttribute("aria-busy")
      button.classList.remove("is-working")
    }, this.durationValue)
  }
}
