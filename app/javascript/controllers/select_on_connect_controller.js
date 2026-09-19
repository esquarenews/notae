import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  connect() {
    this.focusTimeout = window.setTimeout(() => this.focusAndSelect(), 0)
  }

  disconnect() {
    window.clearTimeout(this.focusTimeout)
  }

  focusAndSelect() {
    if (!this.hasInputTarget || !this.inputTarget.isConnected) return

    this.inputTarget.focus({ preventScroll: true })
    if (typeof this.inputTarget.select === "function") this.inputTarget.select()
  }
}
