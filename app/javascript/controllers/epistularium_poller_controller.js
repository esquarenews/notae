import { Controller } from "@hotwired/stimulus"

const DEFAULT_POLL_INTERVAL_MS = 15000
const POLL_INITIAL_DELAY_MS = 5000

export default class extends Controller {
  static targets = ["sections"]
  static values = {
    endpoint: String,
    cursor: String,
    interval: { type: Number, default: DEFAULT_POLL_INTERVAL_MS }
  }

  connect() {
    this.inFlight = false
    this.currentCursor = this.cursorValue || ""
    this.pendingPaneScrollPositions = null
    this.pendingSelectedMessageId = ""
    this.pollStartTimer = window.setTimeout(() => {
      this.pollStartTimer = null
      this.poll()
      this.intervalId = window.setInterval(() => this.poll(), this.intervalValue)
    }, POLL_INITIAL_DELAY_MS)
  }

  disconnect() {
    if (this.pollStartTimer) window.clearTimeout(this.pollStartTimer)
    if (this.intervalId) window.clearInterval(this.intervalId)
  }

  poll() {
    if (document.hidden) return
    if (!this.hasSectionsTarget || this.inFlight) return

    this.fetchAndReplace()
  }

  async fetchAndReplace() {
    const endpoint = this.endpointValue || window.location.href
    const requestUrl = new URL(endpoint, window.location.origin)
    if (this.currentCursor) requestUrl.searchParams.set("poll_cursor", this.currentCursor)
    this.inFlight = true

    try {
      const response = await window.fetch(requestUrl.toString(), {
        method: "GET",
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          "X-Requested-With": "XMLHttpRequest"
        }
      })
      if (!response.ok) return

      const payload = await response.json()
      const nextCursor = String(payload.cursor || "")
      if (nextCursor && nextCursor === this.currentCursor) return
      if (typeof payload.html !== "string") return

      const scrollPositions = this.capturePaneScrollPositions()
      const previousSelectedMessageId = this.selectedMessageId()

      this.sectionsTarget.innerHTML = payload.html
      this.currentCursor = nextCursor

      this.syncEndpoint()
      this.restorePaneScrollPositions(scrollPositions, previousSelectedMessageId)
    } catch (_error) {
      // Ignore transient polling failures; next poll will retry.
    } finally {
      this.inFlight = false
    }
  }

  captureBeforeFrameRequest(event) {
    if (!this.frameEventForSectionsTarget(event)) return

    this.pendingPaneScrollPositions = this.capturePaneScrollPositions()
    this.pendingSelectedMessageId = this.selectedMessageId()
  }

  restoreAfterFrameLoad(event) {
    if (!this.frameEventForSectionsTarget(event)) return

    if (this.pendingPaneScrollPositions) {
      this.restorePaneScrollPositions(this.pendingPaneScrollPositions, this.pendingSelectedMessageId)
    }

    this.pendingPaneScrollPositions = null
    this.pendingSelectedMessageId = ""
    this.syncEndpoint()
  }

  capturePaneScrollPositions() {
    const positions = {}

    this.paneElements().forEach((pane) => {
      const key = pane.dataset.epistulariumPaneKey
      if (!key) return

      positions[key] = pane.scrollTop
    })

    return positions
  }

  restorePaneScrollPositions(positions, previousSelectedMessageId) {
    const currentSelectedMessageId = this.selectedMessageId()

    this.paneElements().forEach((pane) => {
      const key = pane.dataset.epistulariumPaneKey
      if (!key) return
      if (!Object.prototype.hasOwnProperty.call(positions, key)) return
      if (key === "detail" && previousSelectedMessageId !== currentSelectedMessageId) return

      pane.scrollTop = positions[key]
    })
  }

  paneElements() {
    if (!this.hasSectionsTarget) return []

    return Array.from(this.sectionsTarget.querySelectorAll("[data-epistularium-pane-key]"))
  }

  selectedMessageId() {
    if (!this.hasSectionsTarget) return ""

    return this.sectionsTarget.querySelector(".notae-epistularium-grid")?.dataset.epistulariumSelectedMessageId || ""
  }

  syncEndpoint() {
    const nextEndpoint = this.currentPath()
    if (!nextEndpoint) return

    this.endpointValue = nextEndpoint
  }

  currentPath() {
    if (!this.hasSectionsTarget) return ""

    return this.sectionsTarget.querySelector(".notae-epistularium-grid")?.dataset.epistulariumCurrentPath || ""
  }

  frameEventForSectionsTarget(event) {
    return this.hasSectionsTarget && event?.target === this.sectionsTarget
  }
}
