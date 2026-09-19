import { Controller } from "@hotwired/stimulus"

const RESTORE_SCROLL_DELAYS_MS = [ 60, 180, 360, 720, 1200, 1800 ]

export default class extends Controller {
  static maxAgeMs = 30_000

  static values = {
    storageKey: String
  }

  connect() {
    this.pendingSubmitState = null
    this.scrollRestoreGeneration = 0
    this.scrollRestoreAnimationFrame = null
    this.scrollRestoreTimeouts = []
    this.userInteractionHandler = (event) => this.cancelScrollRestoration(event)
    this.element.addEventListener("pointerdown", this.userInteractionHandler, true)
    this.element.addEventListener("mousedown", this.userInteractionHandler, true)
    this.element.addEventListener("keydown", this.userInteractionHandler, true)
    this.element.addEventListener("touchstart", this.userInteractionHandler, { capture: true, passive: true })
    this.element.addEventListener("wheel", this.userInteractionHandler, { capture: true, passive: true })
    this.restoreScrollPosition()
  }

  disconnect() {
    this.element.removeEventListener("pointerdown", this.userInteractionHandler, true)
    this.element.removeEventListener("mousedown", this.userInteractionHandler, true)
    this.element.removeEventListener("keydown", this.userInteractionHandler, true)
    this.element.removeEventListener("touchstart", this.userInteractionHandler, true)
    this.element.removeEventListener("wheel", this.userInteractionHandler, true)
    this.cancelScrollRestoration()
  }

  capture(event) {
    const form = event.target
    if (!this.shouldCaptureForm(form)) return

    this.pendingSubmitState = this.currentStateFor(this.submitterFor(event, form))
    this.storeScrollPosition(this.pendingSubmitState)
  }

  restoreAfterSubmit(event) {
    const form = event.target
    if (!this.shouldCaptureForm(form)) return

    const state = this.pendingSubmitState
    this.pendingSubmitState = null

    if (!state) return
    if (!event.detail?.success) return
    if (this.shouldDeferRestore(event)) return

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
    this.cancelScrollRestoration()
    const generation = this.scrollRestoreGeneration
    const apply = () => {
      if (generation !== this.scrollRestoreGeneration) return

      this.applyScrollPosition(scrollContainer, {
        top: Number(state.scrollTop || 0),
        left: Number(state.scrollLeft || 0)
      })
      this.restoreTrackedElementPosition(scrollContainer, state)
    }

    apply()
    this.scrollRestoreAnimationFrame = window.requestAnimationFrame(() => apply())
    this.scrollRestoreTimeouts = RESTORE_SCROLL_DELAYS_MS.map((delay) => window.setTimeout(() => apply(), delay))
  }

  cancelScrollRestoration(event = null) {
    this.scrollRestoreGeneration += 1
    if (this.scrollRestoreAnimationFrame !== null) {
      window.cancelAnimationFrame(this.scrollRestoreAnimationFrame)
      this.scrollRestoreAnimationFrame = null
    }
    this.scrollRestoreTimeouts.forEach((timeout) => window.clearTimeout(timeout))
    this.scrollRestoreTimeouts = []
  }

  restoreSubmitScrollPosition(state) {
    const scrollContainer = this.scrollContainer()
    if (!scrollContainer) return

    this.restoreStoredPosition(scrollContainer, state)
  }

  shouldCaptureForm(form) {
    if (!(form instanceof HTMLFormElement)) return false

    return this.preserveRequested(form)
  }

  shouldCaptureLink(link) {
    if (!this.preserveRequested(link)) return false

    return true
  }

  preserveRequested(element) {
    if (!(element instanceof HTMLElement)) return false
    if (element.dataset.preserveScroll === "false") return false

    return element.dataset.preserveScroll === "true" || element.dataset.preserveDatabaseScroll === "true"
  }

  responseFor(event) {
    const response = event.detail?.fetchResponse?.response
    return response instanceof Response ? response : null
  }

  responseContentType(event) {
    return this.responseFor(event)?.headers.get("content-type") || ""
  }

  shouldDeferRestore(event) {
    const response = this.responseFor(event)
    if (!response) return false
    if (response.redirected) return true

    const contentType = this.responseContentType(event)
    return contentType.length > 0 && !contentType.includes("turbo-stream")
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

    const keyedAncestor = sourceElement.closest("[data-scroll-preserve-key]")
    if (keyedAncestor instanceof Element) return keyedAncestor

    let current = sourceElement
    while (current instanceof Element) {
      if (this.uniqueIdSelectorFor(current)) return current
      current = current.parentElement
    }

    return null
  }

  selectorForTrackedElement(element) {
    if (!(element instanceof Element)) return null

    const customKey = element.getAttribute("data-scroll-preserve-key")
    if (customKey) {
      return `[data-scroll-preserve-key="${this.escapeSelectorValue(customKey)}"]`
    }

    return this.uniqueIdSelectorFor(element)
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

  uniqueIdSelectorFor(element) {
    if (!(element instanceof Element) || !element.id) return null

    const selector = `#${this.escapeSelectorValue(element.id)}`
    if (document.querySelectorAll(selector).length !== 1) return null

    return selector
  }
}
