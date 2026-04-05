import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    loaded: { type: Boolean, default: false },
    src: String
  }

  connect() {
    this.prefillHandler = (event) => this.prefill(event.detail || {})
    window.addEventListener("notae:ai-prefill", this.prefillHandler)
  }

  disconnect() {
    window.removeEventListener("notae:ai-prefill", this.prefillHandler)
  }

  openRail(event) {
    event.preventDefault()
    this.load("rail")
  }

  openOverlay(event) {
    event.preventDefault()
    this.load("overlay")
  }

  prefill(detail) {
    window.notaeAiRailPendingPrefill = detail
    this.load("rail")
  }

  load(mode = "rail") {
    if (!this.hasSrcValue || this.srcValue.length === 0) return

    window.notaeAiRailPendingOpen = mode
    if (this.loadedValue) return

    this.loadedValue = true
    this.element.setAttribute("src", this.srcValue)
  }
}
