import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["clock", "clockButton", "alerts", "alert", "calendarPanel"]
  static values = { timeZone: String, workspaceKey: String }

  connect() {
    this.renderClock()
    this.startClock()
    this.applyStoredAlertState()
    this.handleWidgetMessage = this.handleWidgetMessage.bind(this)
    window.addEventListener("message", this.handleWidgetMessage)
    this.refreshCalendarState()
  }

  disconnect() {
    this.stopClock()
    window.removeEventListener("message", this.handleWidgetMessage)
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
    this.element.classList.add("is-calendar-open")
    this.refreshCalendarState()
  }

  closeCalendar(event) {
    event?.preventDefault()

    if (!this.hasCalendarPanelTarget) return

    this.calendarPanelTarget.hidden = true
    this.element.classList.remove("is-calendar-open")
    this.refreshCalendarState()
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
    if (!this.hasAlertTarget) {
      this.refreshVisibility()
      return
    }

    this.alertTargets.forEach((alert) => {
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
      const hasVisibleAlerts = this.alertTargets.some((alert) => !alert.hidden)
      this.alertsTarget.hidden = !hasVisibleAlerts
    }

    const clockVisible = this.hasClockTarget && !this.clockTarget.hidden
    const alertsVisible = this.hasAlertsTarget && !this.alertsTarget.hidden
    this.element.hidden = !(clockVisible || alertsVisible)
  }

  refreshCalendarState() {
    if (!this.hasClockButtonTarget) return

    const expanded = this.hasCalendarPanelTarget && !this.calendarPanelTarget.hidden
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

  alertForEvent(event) {
    return event.target?.closest("[data-notification-bar-alert-key]") || null
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
}
