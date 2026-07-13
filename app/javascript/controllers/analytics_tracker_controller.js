import { Controller } from "@hotwired/stimulus"

const DEFAULT_INTERVAL_MS = 30_000
const DEFAULT_IDLE_AFTER_MS = 120_000
const MIN_FLUSH_SECONDS = 5

export default class extends Controller {
  static values = {
    endpoint: String,
    surface: String,
    workspaceSlug: String,
    interval: { type: Number, default: DEFAULT_INTERVAL_MS },
    idleAfter: { type: Number, default: DEFAULT_IDLE_AFTER_MS }
  }

  connect() {
    if (window.top !== window || !this.hasEndpointValue) return

    this.tracking = true
    this.activeSurface = this.normalizedSurface(this.surfaceValue)
    this.lastInteractionAt = Date.now()
    this.lastSampleAt = Date.now()
    this.handleInteraction = this.recordInteraction.bind(this)
    this.handlePassiveInteraction = this.recordPassiveInteraction.bind(this)
    this.handleVisibilityChange = this.visibilityChanged.bind(this)
    this.handlePageHide = this.pageHidden.bind(this)
    this.handleWindowFocus = this.windowFocused.bind(this)
    this.handleWindowBlur = this.windowBlurred.bind(this)
    this.handleTurboLoad = this.turboLoaded.bind(this)
    this.handleTurboBeforeVisit = this.turboBeforeVisit.bind(this)

    document.addEventListener("pointerdown", this.handleInteraction, true)
    document.addEventListener("keydown", this.handleInteraction, true)
    document.addEventListener("focusin", this.handlePassiveInteraction, true)
    document.addEventListener("scroll", this.handleInteraction, true)
    document.addEventListener("visibilitychange", this.handleVisibilityChange)
    window.addEventListener("pagehide", this.handlePageHide)
    window.addEventListener("focus", this.handleWindowFocus)
    window.addEventListener("blur", this.handleWindowBlur)
    document.addEventListener("turbo:load", this.handleTurboLoad)
    document.addEventListener("turbo:before-visit", this.handleTurboBeforeVisit)

    this.timer = window.setInterval(() => this.captureInterval(), this.intervalValue)
  }

  disconnect() {
    if (!this.tracking) return

    this.flushPartial()
    window.clearInterval(this.timer)
    document.removeEventListener("pointerdown", this.handleInteraction, true)
    document.removeEventListener("keydown", this.handleInteraction, true)
    document.removeEventListener("focusin", this.handlePassiveInteraction, true)
    document.removeEventListener("scroll", this.handleInteraction, true)
    document.removeEventListener("visibilitychange", this.handleVisibilityChange)
    window.removeEventListener("pagehide", this.handlePageHide)
    window.removeEventListener("focus", this.handleWindowFocus)
    window.removeEventListener("blur", this.handleWindowBlur)
    document.removeEventListener("turbo:load", this.handleTurboLoad)
    document.removeEventListener("turbo:before-visit", this.handleTurboBeforeVisit)
    this.tracking = false
  }

  surfaceValueChanged(value) {
    if (!this.tracking) return

    this.activeSurface = this.normalizedSurface(value)
    this.lastSampleAt = Date.now()
  }

  recordInteraction(event) {
    const now = Date.now()
    const returningFromIdle = this.idleAt(now)
    const target = event.target instanceof Element ? event.target : null
    let nextSurface = this.activeSurface
    if (target?.closest(".notae-ai-rail, .notae-ai-floating-toggle")) {
      nextSurface = "ai"
    } else if (target?.closest(".notae-main, .notae-sidebar, .notae-mobile-tabbar")) {
      nextSurface = this.normalizedSurface(this.surfaceValue)
    }

    if (nextSurface !== this.activeSurface) {
      this.flushPartial()
      this.activeSurface = nextSurface
    }

    this.lastInteractionAt = now
    if (returningFromIdle) this.lastSampleAt = now
  }

  recordPassiveInteraction() {
    const now = Date.now()
    const returningFromIdle = this.idleAt(now)
    this.lastInteractionAt = now
    if (returningFromIdle) this.lastSampleAt = now
  }

  turboLoaded() {
    this.activeSurface = this.normalizedSurface(this.surfaceValue)
    this.lastInteractionAt = Date.now()
    this.lastSampleAt = Date.now()
  }

  turboBeforeVisit() {
    this.flushPartial()
  }

  visibilityChanged() {
    if (document.visibilityState === "hidden") {
      this.flushPartial({ allowHidden: true })
      return
    }

    this.lastInteractionAt = Date.now()
    this.lastSampleAt = Date.now()
  }

  pageHidden() {
    this.flushPartial({ allowHidden: true })
  }

  windowBlurred() {
    this.flushPartial()
    this.lastSampleAt = Date.now()
  }

  windowFocused() {
    const now = Date.now()
    this.lastInteractionAt = now
    this.lastSampleAt = now
  }

  captureInterval() {
    if (!this.shouldCapture()) {
      this.lastSampleAt = Date.now()
      return
    }

    const now = Date.now()
    const elapsedSeconds = Math.floor((now - this.lastSampleAt) / 1000)
    if (elapsedSeconds < Math.floor(this.intervalValue / 1000)) return

    this.sendSample(Math.min(elapsedSeconds, 30), now)
    this.lastSampleAt = now
  }

  flushPartial({ allowHidden = false } = {}) {
    if (!this.shouldCapture({ requireFocus: false, allowHidden })) return

    const now = Date.now()
    const elapsedSeconds = Math.floor((now - this.lastSampleAt) / 1000)
    if (elapsedSeconds < MIN_FLUSH_SECONDS) return

    this.sendSample(Math.min(elapsedSeconds, 30), now, { keepalive: true })
    this.lastSampleAt = now
  }

  shouldCapture({ requireFocus = true, allowHidden = false } = {}) {
    if (!this.tracking || (!allowHidden && document.visibilityState === "hidden")) return false
    if (requireFocus && typeof document.hasFocus === "function" && !document.hasFocus()) return false

    return Date.now() - this.lastInteractionAt <= this.idleAfterValue
  }

  idleAt(timestamp) {
    return timestamp - this.lastInteractionAt > this.idleAfterValue
  }

  sendSample(durationSeconds, timestamp, { keepalive = false } = {}) {
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    const headers = { "Content-Type": "application/json", "Accept": "application/json" }
    if (csrfToken) headers["X-CSRF-Token"] = csrfToken

    window.fetch(this.endpointValue, {
      method: "POST",
      credentials: "same-origin",
      keepalive,
      headers,
      body: JSON.stringify({
        activity: {
          workspace_slug: this.workspaceSlugValue || null,
          surface: this.activeSurface,
          bucket_started_at: new Date(timestamp - (durationSeconds * 1000)).toISOString(),
          duration_seconds: durationSeconds,
          sample_id: this.sampleId()
        }
      })
    }).catch(() => {})
  }

  normalizedSurface(value) {
    const surface = String(value || "other")
    return surface.length > 0 ? surface : "other"
  }

  sampleId() {
    if (window.crypto?.randomUUID) return window.crypto.randomUUID()

    return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}-${Math.random().toString(36).slice(2)}`
  }
}
