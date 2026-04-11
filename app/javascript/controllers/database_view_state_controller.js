import { Controller } from "@hotwired/stimulus"

const RESTORE_SCROLL_DELAYS_MS = [ 60, 180, 360, 720, 1200, 1800 ]

export default class extends Controller {
  static maxAgeMs = 30_000

  static values = {
    storageKey: String
  }

  connect() {
    this.pendingSubmitState = null
    this.restoreScrollPosition()
  }

  capture(event) {
    const form = event.target
    if (!(form instanceof HTMLFormElement)) return
    if (form.dataset.preserveScroll === "false") return

    this.pendingSubmitState = this.currentStateFor(this.submitterFor(event, form))
    this.storeScrollPosition(this.pendingSubmitState)
  }

  restoreAfterSubmit(event) {
    const form = event.target
    if (!(form instanceof HTMLFormElement)) return
    if (form.dataset.preserveScroll === "false") return

    const state = this.pendingSubmitState
    this.pendingSubmitState = null

    if (!state) return
    if (!event.detail?.success) return

    const contentType = this.responseContentType(event)
    if (contentType.present && !contentType.value.includes("turbo-stream")) return

    this.clearStoredPosition()
    this.restoreSubmitScrollPosition(state)
  }

  captureLink(event) {
    const link = event.target.closest("a")
    if (!(link instanceof HTMLAnchorElement)) return
    if (!this.element.contains(link)) return
    if (!this.shouldCaptureLink(link)) return

    this.storeScrollPosition(this.currentStateFor(link))
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
    this.restoreStoredPosition(scrollContainer, storedPosition)
  }

  scrollContainer() {
    return this.element.closest(".notae-content-scroll") || document.querySelector(".notae-content-scroll") || document.scrollingElement
  }

  currentScrollPosition() {
    const scrollContainer = this.scrollContainer()
    if (!scrollContainer) return null

    return {
      top: scrollContainer.scrollTop,
      left: scrollContainer.scrollLeft
    }
  }

  currentStateFor(sourceElement = null) {
    const position = this.currentScrollPosition()
    if (!position) return null

    const trackedElement = this.trackedElementFor(sourceElement)

    return {
      path: window.location.pathname,
      timestamp: Date.now(),
      scrollTop: position.top,
      scrollLeft: position.left,
      trackedSelector: this.selectorForTrackedElement(trackedElement),
      trackedViewportTop: trackedElement ? trackedElement.getBoundingClientRect().top : null
    }
  }

  storeScrollPosition(state = this.currentStateFor()) {
    if (!state) return

    try {
      window.sessionStorage.setItem(this.storageKey(), JSON.stringify(state))
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

  restoreStoredPosition(scrollContainer, state) {
    const apply = () => {
      this.applyScrollPosition(scrollContainer, {
        top: Number(state.scrollTop || 0),
        left: Number(state.scrollLeft || 0)
      })
      this.restoreTrackedElementPosition(scrollContainer, state)
    }

    apply()
    window.requestAnimationFrame(() => apply())
    RESTORE_SCROLL_DELAYS_MS.forEach((delay) => {
      window.setTimeout(() => apply(), delay)
    })
  }

  restoreSubmitScrollPosition(state) {
    const scrollContainer = this.scrollContainer()
    if (!scrollContainer) return

    this.restoreStoredPosition(scrollContainer, state)
  }

  responseContentType(event) {
    const response = event.detail?.fetchResponse?.response
    if (!(response instanceof Response)) {
      return { present: false, value: "" }
    }

    return {
      present: true,
      value: response.headers.get("content-type") || ""
    }
  }

  shouldCaptureLink(link) {
    if (link.dataset.preserveScroll === "false") return false
    if (link.dataset.preserveDatabaseScroll === "true") return true

    return false
  }

  submitterFor(event, fallbackForm) {
    const turboSubmitter = event.detail?.formSubmission?.submitter
    if (turboSubmitter instanceof Element) return turboSubmitter
    if (document.activeElement instanceof Element && fallbackForm.contains(document.activeElement)) {
      return document.activeElement
    }

    return fallbackForm
  }

  trackedElementFor(sourceElement) {
    if (!(sourceElement instanceof Element)) return null

    return sourceElement.closest("[data-scroll-preserve-key], [id]")
  }

  selectorForTrackedElement(element) {
    if (!(element instanceof Element)) return null

    const customKey = element.getAttribute("data-scroll-preserve-key")
    if (customKey) {
      return `[data-scroll-preserve-key="${this.escapeSelectorValue(customKey)}"]`
    }

    if (element.id) {
      return `#${this.escapeSelectorValue(element.id)}`
    }

    return null
  }

  restoreTrackedElementPosition(scrollContainer, state) {
    if (!state?.trackedSelector) return
    if (typeof state.trackedViewportTop !== "number") return

    const trackedElement = this.element.querySelector(state.trackedSelector) || document.querySelector(state.trackedSelector)
    if (!(trackedElement instanceof Element)) return

    const currentViewportTop = trackedElement.getBoundingClientRect().top
    const delta = currentViewportTop - state.trackedViewportTop
    if (Math.abs(delta) < 1) return

    scrollContainer.scrollTop += delta
  }

  escapeSelectorValue(value) {
    if (typeof CSS !== "undefined" && typeof CSS.escape === "function") {
      return CSS.escape(value)
    }

    return String(value).replace(/["\\]/g, "\\$&")
  }
}
