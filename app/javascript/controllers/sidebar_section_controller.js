import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "toggle"]
  static values = {
    defaultOpen: { type: Boolean, default: true },
    key: String
  }

  connect() {
    this.open = this.storedOpenState()
    this.applyState()
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    this.open = !this.open
    this.persistOpenState()
    this.applyState()
  }

  applyState() {
    this.element.classList.toggle("is-collapsed", !this.open)
    if (this.hasContentTarget) this.contentTarget.hidden = !this.open
    if (this.hasToggleTarget) {
      this.toggleTarget.setAttribute("aria-expanded", this.open ? "true" : "false")
    }
  }

  storedOpenState() {
    try {
      const value = window.localStorage.getItem(this.storageKey())
      if (value === "true") return true
      if (value === "false") return false
    } catch (_error) {
      // localStorage is unavailable
    }

    return this.defaultOpenValue
  }

  persistOpenState() {
    try {
      window.localStorage.setItem(this.storageKey(), this.open ? "true" : "false")
    } catch (_error) {
      // localStorage is unavailable
    }
  }

  storageKey() {
    const sectionKey = this.hasKeyValue ? this.keyValue : "default"
    return `notae-sidebar-section:${sectionKey}`
  }
}
