import { Controller } from "@hotwired/stimulus"

const AI_RAIL_COLLAPSED_PREFERENCE_KEY = "notae-ai-rail-collapsed-v2"
const AI_RAIL_COMPACT_MAX_WIDTH = 1180

export default class extends Controller {
  static values = {
    loaded: { type: Boolean, default: false },
    src: String
  }

  connect() {
    this.prefillHandler = (event) => this.prefill(event.detail || {})
    window.addEventListener("notae:ai-prefill", this.prefillHandler)

    if (this.shouldAutoload()) this.load(this.defaultLoadMode())
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

  shouldAutoload() {
    if (window.notaeAiRailPendingPrefill) return true
    if (window.notaeAiRailPendingOpen) return true
    if (this.compactViewport()) return false

    return !this.railCollapsedPreference()
  }

  defaultLoadMode() {
    if (window.notaeAiRailPendingOpen === "overlay") return "overlay"

    return "rail"
  }

  railCollapsedPreference() {
    try {
      return window.localStorage.getItem(AI_RAIL_COLLAPSED_PREFERENCE_KEY) === "true"
    } catch (_error) {
      return false
    }
  }

  compactViewport() {
    if (typeof window.innerWidth === "number" && window.innerWidth > 0) {
      return window.innerWidth <= AI_RAIL_COMPACT_MAX_WIDTH
    }

    return window.matchMedia?.(`(max-width: ${AI_RAIL_COMPACT_MAX_WIDTH}px)`)?.matches || false
  }
}
