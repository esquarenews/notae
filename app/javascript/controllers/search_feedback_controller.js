import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "submit"]
  static values = {
    activeText: { type: String, default: "Searching..." }
  }

  start(event) {
    if (event?.target?.checkValidity && !event.target.checkValidity()) return

    this.setLoading(true)
  }

  setLoading(loading) {
    this.element.classList.toggle("is-searching", loading)
    this.element.setAttribute("aria-busy", loading ? "true" : "false")

    if (this.hasStatusTarget) {
      this.statusTarget.hidden = !loading
    }

    this.submitTargets.forEach((submit) => {
      if (loading) {
        this.cacheOriginalLabel(submit)
        this.setSubmitLabel(submit, this.activeTextValue)
      } else {
        this.restoreSubmitLabel(submit)
      }

      submit.toggleAttribute("disabled", loading)
      submit.setAttribute("aria-busy", loading ? "true" : "false")
    })
  }

  cacheOriginalLabel(submit) {
    if (submit.dataset.searchFeedbackOriginalLabel) return

    submit.dataset.searchFeedbackOriginalLabel =
      submit instanceof HTMLInputElement ? submit.value : submit.textContent
  }

  setSubmitLabel(submit, label) {
    if (submit instanceof HTMLInputElement) {
      return
    } else {
      submit.textContent = label
    }
  }

  restoreSubmitLabel(submit) {
    const label = submit.dataset.searchFeedbackOriginalLabel
    if (!label) return

    this.setSubmitLabel(submit, label)
  }
}
