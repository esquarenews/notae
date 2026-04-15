import { Controller } from "@hotwired/stimulus"

const DEBOUNCE_MS = 350

export default class extends Controller {
  static targets = ["input", "status"]
  static values = {
    url: String,
    resource: { type: String, default: "page" },
    field: { type: String, default: "title" }
  }

  connect() {
    this.inFlight = false
    this.pendingTitle = null
    this.saveTimeout = null
    this.lastSavedTitle = this.inputTarget.value
    this.resizeInput()
    this.pageHideHandler = () => this.flushSave({ keepalive: true })
    window.addEventListener("pagehide", this.pageHideHandler)
  }

  disconnect() {
    clearTimeout(this.saveTimeout)
    window.removeEventListener("pagehide", this.pageHideHandler)
  }

  queueSave() {
    this.resizeInput()
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
    this.flushSave()
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
        body: JSON.stringify({
          [this.resourceValue]: {
            [this.fieldValue]: title
          }
        })
      })

      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      let responseData = null
      const contentType = response.headers.get("content-type") || ""
      if (contentType.includes("application/json")) {
        responseData = await response.json()
      }

      this.lastSavedTitle = title
      this.setStatus("Saved")
      this.updateTopbarEditedAt(responseData?.updated_at)
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

  updateTopbarEditedAt(isoTimestamp) {
    if (!isoTimestamp) return

    const updatedAtMs = Date.parse(isoTimestamp)
    if (!Number.isFinite(updatedAtMs)) return

    const wrapper = document.getElementById(`${this.resourceValue}_topbar_edited_at`)
    if (!wrapper) return

    const target = wrapper.classList.contains("notae-topbar-meta") ? wrapper : wrapper.querySelector(".notae-topbar-meta")
    if (!target) return

    target.textContent = `Edited ${this.relativeTimeLabel(updatedAtMs)} ago`
  }

  relativeTimeLabel(updatedAtMs) {
    const deltaSeconds = Math.max(1, Math.round((Date.now() - updatedAtMs) / 1000))

    if (deltaSeconds < 45) return "less than a minute"
    if (deltaSeconds < 90) return "1 minute"
    if (deltaSeconds < 45 * 60) return `${Math.round(deltaSeconds / 60)} minutes`
    if (deltaSeconds < 90 * 60) return "about 1 hour"
    if (deltaSeconds < 24 * 60 * 60) return `about ${Math.round(deltaSeconds / (60 * 60))} hours`
    if (deltaSeconds < 42 * 60 * 60) return "1 day"
    if (deltaSeconds < 30 * 24 * 60 * 60) return `${Math.round(deltaSeconds / (24 * 60 * 60))} days`
    if (deltaSeconds < 45 * 24 * 60 * 60) return "about 1 month"
    if (deltaSeconds < 365 * 24 * 60 * 60) return `${Math.round(deltaSeconds / (30 * 24 * 60 * 60))} months`
    if (deltaSeconds < 545 * 24 * 60 * 60) return "about 1 year"

    return `${Math.round(deltaSeconds / (365 * 24 * 60 * 60))} years`
  }

  resizeInput() {
    if (!(this.inputTarget instanceof HTMLTextAreaElement)) return

    this.inputTarget.style.height = "0px"
    this.inputTarget.style.height = `${this.inputTarget.scrollHeight}px`
  }
}
