import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "toggle"]
  static values = { delay: Number }

  connect() {
    this.startTimer()
  }

  disconnect() {
    this.clearTimer()
  }

  collapse() {
    if (this.hasPanelTarget) this.panelTarget.classList.add("is-hidden")
    if (this.hasToggleTarget) this.toggleTarget.classList.remove("is-hidden")
    this.clearTimer()
  }

  expand() {
    if (this.hasPanelTarget) this.panelTarget.classList.remove("is-hidden")
    if (this.hasToggleTarget) this.toggleTarget.classList.add("is-hidden")
    this.startTimer()
  }

  pause() {
    this.clearTimer()
  }

  resume() {
    if (this.hasPanelTarget && this.panelTarget.classList.contains("is-hidden")) return
    this.startTimer()
  }

  startTimer() {
    this.clearTimer()
    const delay = this.hasDelayValue ? this.delayValue : 18000
    this.timeout = window.setTimeout(() => this.collapse(), delay)
  }

  clearTimer() {
    if (!this.timeout) return
    window.clearTimeout(this.timeout)
    this.timeout = null
  }
}
