import { Controller } from "@hotwired/stimulus"

const ALERT_POLL_INTERVAL_MS = 15000

export default class extends Controller {
  static targets = ["clock", "clockButton", "alerts", "alert", "calendarPanel", "calendarFrame"]
  static values = { timeZone: String, workspaceKey: String, refreshPath: String }

  connect() {
    this.renderClock()
    this.startClock()
    this.applyStoredAlertState()
    this.handleWidgetMessage = this.handleWidgetMessage.bind(this)
    this.beforeCache = this.beforeCache.bind(this)
    this.visibilityChangeHandler = () => this.syncAlertPolling({ immediate: document.visibilityState === "visible" })
    this.calendarFrameLoadHandler = () => this.requestCalendarRecenter()
    this.alertPollTimer = null
    this.alertPollRequest = null
    window.addEventListener("message", this.handleWidgetMessage)
    document.addEventListener("turbo:before-cache", this.beforeCache)
    document.addEventListener("visibilitychange", this.visibilityChangeHandler)
    if (this.hasCalendarFrameTarget) {
      this.calendarFrameTarget.addEventListener("load", this.calendarFrameLoadHandler)
    }
    this.syncCalendarState()
    this.syncAlertPolling({ immediate: true })
  }

  disconnect() {
    this.stopClock()
    window.removeEventListener("message", this.handleWidgetMessage)
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    document.removeEventListener("visibilitychange", this.visibilityChangeHandler)
    if (this.hasCalendarFrameTarget) {
      this.calendarFrameTarget.removeEventListener("load", this.calendarFrameLoadHandler)
    }
    this.stopAlertPolling()
  }

  startClock() {
    this.stopClock()
    this.clockTimer = window.setInterval(() => this.renderClock(), 30000)
  }

  stopClock() {
    if (!this.clockTimer) return

    window.clearInterval(this.clockTimer)
    this.clockTimer = null
  }

  renderClock() {
    if (!this.hasClockTarget) return

    const now = new Date()
    const timeZone = this.resolvedTimeZone()
    const dateLabel = new Intl.DateTimeFormat(undefined, {
      weekday: "short",
      day: "numeric",
      month: "short",
      timeZone
    }).format(now)
    const timeLabel = new Intl.DateTimeFormat(undefined, {
      hour: "numeric",
      minute: "2-digit",
      timeZone
    }).format(now)

    this.clockTarget.textContent = `${dateLabel} · ${timeLabel}`
  }

  toggleCalendar(event) {
    event?.preventDefault()

    if (!this.hasCalendarPanelTarget) return

    if (this.calendarPanelTarget.hidden) {
      this.openCalendar()
    } else {
      this.closeCalendar()
    }
  }

  openCalendar() {
    if (!this.hasCalendarPanelTarget) return

    this.calendarPanelTarget.hidden = false
    this.syncCalendarState()
    window.requestAnimationFrame(() => this.requestCalendarRecenter({ retries: 6 }))
  }

  closeCalendar(event) {
    event?.preventDefault()

    if (!this.hasCalendarPanelTarget) return

    this.calendarPanelTarget.hidden = true
    this.syncCalendarState()
  }

  beforeCache() {
    this.closeCalendar()
  }

  dismissAlert(event) {
    event.preventDefault()
    event.stopPropagation()

    const alert = this.alertForEvent(event)
    if (!alert) return

    this.writeSessionDismissal(this.alertKey(alert))
    this.hideAlert(alert)
  }

  snoozeAlert(event) {
    event.preventDefault()
    event.stopPropagation()

    const alert = this.alertForEvent(event)
    if (!alert) return

    this.writeLocalSnooze(this.alertKey(alert), Date.now() + (60 * 60 * 1000))
    this.hideAlert(alert)
  }

  resolvedTimeZone() {
    const value = this.timeZoneValue?.trim()
    return value && value.length > 0 ? value : undefined
  }

  applyStoredAlertState() {
    const alerts = this.alertElements()
    if (alerts.length < 1) {
      this.refreshVisibility()
      return
    }

    alerts.forEach((alert) => {
      const key = this.alertKey(alert)
      if (!key) return

      alert.hidden = this.dismissedInSession(key) || this.snoozedLocally(key)
    })

    this.refreshVisibility()
  }

  hideAlert(alert) {
    alert.hidden = true
    this.refreshVisibility()
  }

  refreshVisibility() {
    if (this.hasAlertsTarget) {
      const hasVisibleAlerts = this.alertElements().some((alert) => !alert.hidden)
      this.alertsTarget.hidden = !hasVisibleAlerts
    }

    const clockVisible = this.hasClockTarget && !this.clockTarget.hidden
    const alertsVisible = this.hasAlertsTarget && !this.alertsTarget.hidden
    this.element.hidden = !(clockVisible || alertsVisible)
  }

  syncCalendarState() {
    const expanded = this.hasCalendarPanelTarget && !this.calendarPanelTarget.hidden
    this.element.classList.toggle("is-calendar-open", expanded)

    if (!this.hasClockButtonTarget) return

    this.clockButtonTarget.setAttribute("aria-expanded", expanded ? "true" : "false")
    this.clockButtonTarget.setAttribute("aria-label", expanded ? "Close compact Kalendārium" : "Open compact Kalendārium")
  }

  handleWidgetMessage(event) {
    if (event.origin !== window.location.origin) return

    const messageType = event.data?.type
    if (messageType === "notae:kalendarium-widget:minimize") {
      this.closeCalendar()
    }
  }

  requestCalendarRecenter({ retries = 0 } = {}) {
    if (!this.hasCalendarFrameTarget) return

    const frameWindow = this.calendarFrameTarget.contentWindow
    if (!frameWindow) {
      if (retries > 0) {
        window.setTimeout(() => this.requestCalendarRecenter({ retries: retries - 1 }), 120)
      }
      return
    }

    frameWindow.postMessage({
      type: "notae:kalendarium-widget:center-current-time",
      timeZone: this.browserTimeZone()
    }, window.location.origin)

    if (retries > 0) {
      window.setTimeout(() => this.requestCalendarRecenter({ retries: retries - 1 }), 120)
    }
  }

  browserTimeZone() {
    return Intl.DateTimeFormat().resolvedOptions().timeZone
  }

  alertForEvent(event) {
    return event.target?.closest("[data-notification-bar-alert-key]") || null
  }

  alertElements() {
    return Array.from(this.element.querySelectorAll("[data-notification-bar-target='alert']"))
  }

  alertKey(alert) {
    return alert?.dataset?.notificationBarAlertKey?.trim() || ""
  }

  dismissedInSession(alertKey) {
    const key = this.sessionStorageKey(alertKey)
    if (!key) return false

    try {
      return window.sessionStorage.getItem(key) === "1"
    } catch (_error) {
      return false
    }
  }

  snoozedLocally(alertKey) {
    const key = this.localStorageKey(alertKey)
    if (!key) return false

    try {
      const raw = window.localStorage.getItem(key)
      if (!raw) return false

      const snoozeUntil = Number.parseInt(raw, 10)
      if (!Number.isFinite(snoozeUntil) || snoozeUntil <= Date.now()) {
        window.localStorage.removeItem(key)
        return false
      }

      return true
    } catch (_error) {
      return false
    }
  }

  writeSessionDismissal(alertKey) {
    const key = this.sessionStorageKey(alertKey)
    if (!key) return

    try {
      window.sessionStorage.setItem(key, "1")
    } catch (_error) {
      // Ignore storage failures and continue with in-memory hiding.
    }
  }

  writeLocalSnooze(alertKey, untilTimestamp) {
    const key = this.localStorageKey(alertKey)
    if (!key) return

    try {
      window.localStorage.setItem(key, String(untilTimestamp))
    } catch (_error) {
      // Ignore storage failures and continue with in-memory hiding.
    }
  }

  sessionStorageKey(alertKey) {
    const workspaceKey = this.workspaceKeyValue?.trim()
    if (!workspaceKey || !alertKey) return ""

    return `notae:notification-bar:dismiss:${workspaceKey}:${alertKey}`
  }

  localStorageKey(alertKey) {
    const workspaceKey = this.workspaceKeyValue?.trim()
    if (!workspaceKey || !alertKey) return ""

    return `notae:notification-bar:snooze:${workspaceKey}:${alertKey}`
  }

  syncAlertPolling({ immediate = false } = {}) {
    if (!this.hasAlertsTarget || !this.hasRefreshPathValue || !this.refreshPathValue || document.visibilityState !== "visible") {
      this.stopAlertPolling()
      return
    }

    if (!this.alertPollTimer) {
      this.alertPollTimer = window.setInterval(() => {
        this.pollAlerts()
      }, ALERT_POLL_INTERVAL_MS)
    }

    if (immediate) this.pollAlerts()
  }

  stopAlertPolling() {
    if (this.alertPollTimer) {
      window.clearInterval(this.alertPollTimer)
      this.alertPollTimer = null
    }
  }

  async pollAlerts({ force = false } = {}) {
    if (!this.hasRefreshPathValue || !this.refreshPathValue) return
    if (document.visibilityState !== "visible") return
    if (!force && this.alertPollRequest) return this.alertPollRequest

    this.alertPollRequest = (async () => {
      try {
        const response = await fetch(this.refreshPathValue, {
          headers: {
            Accept: "application/json",
            "X-Requested-With": "XMLHttpRequest"
          },
          credentials: "same-origin"
        })
        if (!response.ok) return

        const payload = await response.json()
        if (!this.hasAlertsTarget) return

        this.alertsTarget.innerHTML = payload?.data?.html?.toString() || ""
        window.requestAnimationFrame(() => this.applyStoredAlertState())
      } catch (_error) {
        // Ignore transient polling failures.
      } finally {
        this.alertPollRequest = null
      }
    })()

    return this.alertPollRequest
  }
}
