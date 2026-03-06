import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    active: Boolean,
    interval: { type: Number, default: 10000 },
    endpoint: String
  }
  static targets = ["sections"]

  connect() {
    this.intervalId = null
    this.inFlight = false
    if (this.activeValue) this.startPolling()
  }

  disconnect() {
    this.stopPolling()
  }

  startPolling() {
    this.stopPolling()
    this.intervalId = window.setInterval(() => this.poll(), this.intervalValue)
  }

  stopPolling() {
    if (!this.intervalId) return
    window.clearInterval(this.intervalId)
    this.intervalId = null
  }

  poll() {
    if (document.hidden) return
    if (!this.hasSectionsTarget) return

    const activeElement = document.activeElement
    if (activeElement && [ "INPUT", "TEXTAREA", "SELECT" ].includes(activeElement.tagName)) return

    this.fetchAndReplace()
  }

  async fetchAndReplace() {
    if (this.inFlight) return

    const endpoint = this.endpointValue || window.location.href
    this.inFlight = true
    try {
      const response = await window.fetch(endpoint, {
        method: "GET",
        credentials: "same-origin",
        headers: {
          Accept: "application/json"
        }
      })
      if (!response.ok) return

      const payload = await response.json()
      if (typeof payload.html === "string") {
        this.sectionsTarget.innerHTML = payload.html
      }
      this.activeValue = Boolean(payload.active)
      if (!this.activeValue) this.stopPolling()
    } catch (_error) {
      // Ignore transient polling failures; next poll will retry.
    } finally {
      this.inFlight = false
    }
  }
}
