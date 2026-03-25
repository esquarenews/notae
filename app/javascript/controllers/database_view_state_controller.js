import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static maxAgeMs = 30_000

  static values = {
    storageKey: String
  }

  connect() {
    this.restoreScrollPosition()
  }

  capture(event) {
    const form = event.target
    if (!(form instanceof HTMLFormElement)) return
    if (form.dataset.preserveDatabaseScroll !== "true") return

    this.storeScrollPosition()
  }

  captureLink(event) {
    const link = event.target.closest("a[data-preserve-database-scroll='true']")
    if (!(link instanceof HTMLAnchorElement)) return
    if (!this.element.contains(link)) return

    this.storeScrollPosition()
  }

  restoreScrollPosition() {
    const scrollContainer = this.scrollContainer()
    if (!scrollContainer) return

    const storedPosition = this.readStoredPosition()
    if (!storedPosition) return
    if (storedPosition.path !== window.location.pathname) return
    if (Date.now() - Number(storedPosition.timestamp || 0) > this.constructor.maxAgeMs) {
      this.clearStoredPosition()
      return
    }

    this.clearStoredPosition()
    const top = Number(storedPosition.scrollTop || 0)
    const left = Number(storedPosition.scrollLeft || 0)

    this.applyScrollPosition(scrollContainer, { top, left })
    window.requestAnimationFrame(() => this.applyScrollPosition(scrollContainer, { top, left }))
  }

  scrollContainer() {
    return this.element.closest(".notae-content-scroll") || document.querySelector(".notae-content-scroll") || document.scrollingElement
  }

  storeScrollPosition() {
    const scrollContainer = this.scrollContainer()
    if (!scrollContainer) return

    const payload = {
      path: window.location.pathname,
      timestamp: Date.now(),
      scrollTop: scrollContainer.scrollTop,
      scrollLeft: scrollContainer.scrollLeft
    }

    try {
      window.sessionStorage.setItem(this.storageKey(), JSON.stringify(payload))
    } catch (_error) {
      // Ignore storage failures and allow normal navigation.
    }
  }

  readStoredPosition() {
    try {
      const rawPayload = window.sessionStorage.getItem(this.storageKey())
      return rawPayload ? JSON.parse(rawPayload) : null
    } catch (_error) {
      return null
    }
  }

  clearStoredPosition() {
    try {
      window.sessionStorage.removeItem(this.storageKey())
    } catch (_error) {
      // Ignore storage failures and allow normal navigation.
    }
  }

  storageKey() {
    return this.hasStorageKeyValue ? this.storageKeyValue : "database-view-scroll"
  }

  applyScrollPosition(scrollContainer, position) {
    scrollContainer.scrollTop = position.top
    scrollContainer.scrollLeft = position.left
  }
}
