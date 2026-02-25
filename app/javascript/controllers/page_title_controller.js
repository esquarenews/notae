import { Controller } from "@hotwired/stimulus"

const DEBOUNCE_MS = 350

export default class extends Controller {
  static targets = ["input", "status"]
  static values = { url: String }

  connect() {
    this.inFlight = false
    this.pendingTitle = null
    this.saveTimeout = null
    this.lastSavedTitle = this.inputTarget.value
    this.pageHideHandler = () => this.flushSave({ keepalive: true, force: true })
    window.addEventListener("pagehide", this.pageHideHandler)
  }

  disconnect() {
    clearTimeout(this.saveTimeout)
    window.removeEventListener("pagehide", this.pageHideHandler)
  }

  queueSave() {
    this.setStatus("Saving...")
    clearTimeout(this.saveTimeout)
    this.saveTimeout = setTimeout(() => this.flushSave(), DEBOUNCE_MS)
  }

  flushSave(options = {}) {
    clearTimeout(this.saveTimeout)
    const title = this.inputTarget.value

    if (!options.force && title === this.lastSavedTitle) {
      this.setStatus("Saved")
      return
    }

    if (this.inFlight) {
      this.pendingTitle = title
      return
    }

    this.save(title, options)
  }

  preventSubmit(event) {
    event.preventDefault()
    this.flushSave({ force: true })
  }

  async save(title, { keepalive = false, force = false } = {}) {
    if (this.inFlight) {
      this.pendingTitle = title
      return
    }

    if (!force && title === this.lastSavedTitle) {
      this.setStatus("Saved")
      return
    }

    this.inFlight = true
    this.setStatus("Saving...")

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        credentials: "same-origin",
        keepalive,
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {})
        },
        body: JSON.stringify({ page: { title } })
      })

      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      this.lastSavedTitle = title
      this.setStatus("Saved")
    } catch (_error) {
      this.setStatus("Save failed")
    } finally {
      this.inFlight = false
      if (this.pendingTitle && this.pendingTitle !== this.lastSavedTitle) {
        const queuedTitle = this.pendingTitle
        this.pendingTitle = null
        this.save(queuedTitle)
      }
    }
  }

  setStatus(message) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = message
    }
  }
}
