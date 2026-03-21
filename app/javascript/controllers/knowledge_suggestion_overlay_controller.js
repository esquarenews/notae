import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "toggle"]
  static values = {
    delay: Number,
    suggestionId: String
  }

  connect() {
    this.restoreState()
  }

  disconnect() {
    this.clearTimer()
  }

  collapse() {
    if (this.hasPanelTarget) this.panelTarget.classList.add("is-hidden")
    if (this.hasToggleTarget) this.toggleTarget.classList.remove("is-hidden")
    this.persistCollapsedState(true)
    this.clearTimer()
  }

  expand() {
    if (this.hasPanelTarget) this.panelTarget.classList.remove("is-hidden")
    if (this.hasToggleTarget) this.toggleTarget.classList.add("is-hidden")
    this.persistCollapsedState(false)
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
    if (this.hasPanelTarget && this.panelTarget.classList.contains("is-hidden")) return
    const delay = this.hasDelayValue ? this.delayValue : 18000
    this.timeout = window.setTimeout(() => this.collapse(), delay)
  }

  clearTimer() {
    if (!this.timeout) return
    window.clearTimeout(this.timeout)
    this.timeout = null
  }

  restoreState() {
    if (this.collapsedForCurrentSuggestion()) {
      this.collapse()
      return
    }

    if (this.hasPanelTarget) this.panelTarget.classList.remove("is-hidden")
    if (this.hasToggleTarget) this.toggleTarget.classList.add("is-hidden")
    this.startTimer()
  }

  collapsedForCurrentSuggestion() {
    return this.currentSuggestionId() && this.collapsedSuggestionId() === this.currentSuggestionId()
  }

  persistCollapsedState(collapsed) {
    const suggestionId = this.currentSuggestionId()
    if (!suggestionId) return

    try {
      if (collapsed) {
        window.localStorage.setItem(this.collapsedSuggestionStorageKey(), suggestionId)
      } else if (this.collapsedSuggestionId() === suggestionId) {
        window.localStorage.removeItem(this.collapsedSuggestionStorageKey())
      }
    } catch (_error) {
      // localStorage is unavailable
    }
  }

  collapsedSuggestionId() {
    try {
      return window.localStorage.getItem(this.collapsedSuggestionStorageKey()) || ""
    } catch (_error) {
      return ""
    }
  }

  collapsedSuggestionStorageKey() {
    return "notae-knowledge-overlay-collapsed-suggestion-id"
  }

  currentSuggestionId() {
    return this.hasSuggestionIdValue ? String(this.suggestionIdValue || "") : ""
  }
}
