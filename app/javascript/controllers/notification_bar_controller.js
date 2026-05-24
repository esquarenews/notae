import { Controller } from "@hotwired/stimulus"

const ALERT_POLL_INTERVAL_MS = 15000
const BAR_GUTTER_PX = 20
const DRAG_THRESHOLD_PX = 4

export default class extends Controller {
  static targets = ["clock", "clockButton", "alerts", "alert", "calendarPanel", "calendarFrame", "timesheetTimer", "timesheetTimerLabel", "timesheetTimerElapsed", "timesheetTimerCalendar"]
  static values = { timeZone: String, workspaceKey: String, refreshPath: String, calendarSrc: String }

  connect() {
    const shouldPollImmediately = this.element.dataset.notificationBarAlertsBootstrapped !== "true"

    this.renderClock()
    this.startClock()
    this.applyStoredAlertState()
    this.handleWidgetMessage = this.handleWidgetMessage.bind(this)
    this.beforeCache = this.beforeCache.bind(this)
    this.visibilityChangeHandler = () => this.syncAlertPolling({ immediate: document.visibilityState === "visible" })
    this.calendarFrameLoadHandler = () => this.requestCalendarRecenter()
    this.timesheetStartedHandler = (event) => this.showTimesheetTimer(event.detail)
    this.timesheetStoppedHandler = () => this.hideTimesheetTimer()
    this.pointerMoveHandler = (event) => this.drag(event)
    this.pointerUpHandler = () => this.stopDrag()
    this.resizeHandler = () => this.applyStoredBarPosition()
    this.pushReceivedHandler = () => this.pollAlerts({ force: true })
    this.alertPollTimer = null
    this.alertPollRequest = null
    this.dragPointerId = null
    this.dragOriginX = null
    this.dragOriginLeft = null
    this.dragMoved = false
    window.addEventListener("message", this.handleWidgetMessage)
    window.addEventListener("notae:timesheet-timer-started", this.timesheetStartedHandler)
    window.addEventListener("notae:timesheet-timer-stopped", this.timesheetStoppedHandler)
    document.addEventListener("turbo:before-cache", this.beforeCache)
    document.addEventListener("visibilitychange", this.visibilityChangeHandler)
    window.addEventListener("resize", this.resizeHandler)
    window.addEventListener("notae:push-received", this.pushReceivedHandler)
    if (this.hasCalendarFrameTarget) {
      this.calendarFrameTarget.addEventListener("load", this.calendarFrameLoadHandler)
    }
    this.applyStoredBarPosition()
    this.syncCalendarState()
    this.startTimesheetTimer()
    this.element.dataset.notificationBarAlertsBootstrapped = "true"
    this.syncAlertPolling({ immediate: shouldPollImmediately })
  }

  disconnect() {
    this.stopClock()
    window.removeEventListener("message", this.handleWidgetMessage)
    window.removeEventListener("notae:timesheet-timer-started", this.timesheetStartedHandler)
    window.removeEventListener("notae:timesheet-timer-stopped", this.timesheetStoppedHandler)
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    document.removeEventListener("visibilitychange", this.visibilityChangeHandler)
    window.removeEventListener("resize", this.resizeHandler)
    window.removeEventListener("notae:push-received", this.pushReceivedHandler)
    this.releaseDragListeners()
    if (this.hasCalendarFrameTarget) {
      this.calendarFrameTarget.removeEventListener("load", this.calendarFrameLoadHandler)
    }
    this.stopAlertPolling()
    this.stopTimesheetTimer()
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

  startTimesheetTimer() {
    this.stopTimesheetTimer()
    this.renderTimesheetTimer()
    this.timesheetTimerUpdateTimer = window.setInterval(() => this.renderTimesheetTimer(), 1000)
  }

  stopTimesheetTimer() {
    if (!this.timesheetTimerUpdateTimer) return

    window.clearInterval(this.timesheetTimerUpdateTimer)
    this.timesheetTimerUpdateTimer = null
  }

  showTimesheetTimer(detail = {}) {
    if (!this.hasTimesheetTimerTarget) return

    const startedAt = detail.startedAt?.toString().trim()
    if (startedAt) this.timesheetTimerTarget.dataset.startedAt = startedAt
    if (this.hasTimesheetTimerLabelTarget && detail.label) {
      this.timesheetTimerLabelTarget.textContent = detail.label.toString()
    }

    this.timesheetTimerTarget.hidden = false
    if (this.hasTimesheetTimerCalendarTarget) this.timesheetTimerCalendarTarget.hidden = false
    this.renderTimesheetTimer()
    this.refreshVisibility()
  }

  hideTimesheetTimer() {
    if (!this.hasTimesheetTimerTarget) return

    this.timesheetTimerTarget.hidden = true
    if (this.hasTimesheetTimerCalendarTarget) this.timesheetTimerCalendarTarget.hidden = true
    this.refreshVisibility()
  }

  renderTimesheetTimer() {
    if (!this.hasTimesheetTimerTarget || !this.hasTimesheetTimerElapsedTarget) return
    if (this.timesheetTimerTarget.hidden) return

    const startedAt = this.timesheetTimerStartedAt()
    if (!startedAt) return

    const elapsed = this.formatElapsed(Date.now() - startedAt.getTime())
    this.timesheetTimerElapsedTargets.forEach((target) => {
      target.textContent = elapsed
    })
  }

  updateTimesheetTimerFromPayload(timer) {
    if (timer?.started_at) {
      this.showTimesheetTimer({
        startedAt: timer.started_at,
        label: timer.label || "Time sheet"
      })
    } else {
      this.hideTimesheetTimer()
    }
  }

  timesheetTimerStartedAt() {
    const raw = this.timesheetTimerTarget.dataset.startedAt?.trim()
    if (!raw) return null

    const parsed = new Date(raw)
    return Number.isNaN(parsed.getTime()) ? null : parsed
  }

  formatElapsed(milliseconds) {
    const totalSeconds = Math.max(Math.floor(milliseconds / 1000), 0)
    const hours = Math.floor(totalSeconds / 3600)
    const minutes = Math.floor((totalSeconds % 3600) / 60)
    const seconds = totalSeconds % 60
    const pad = (value) => value.toString().padStart(2, "0")

    return `${pad(hours)}:${pad(minutes)}:${pad(seconds)}`
  }

  startDrag(event) {
    if (!this.hasClockButtonTarget) return
    if (event.button !== 0) return

    this.dragPointerId = event.pointerId
    this.dragOriginX = event.clientX
    this.dragOriginLeft = this.currentBarLeft()
    this.dragMoved = false

    this.clockButtonTarget.setPointerCapture?.(event.pointerId)
    this.clockButtonTarget.classList.add("is-dragging")
    window.addEventListener("pointermove", this.pointerMoveHandler)
    window.addEventListener("pointerup", this.pointerUpHandler, { once: false })
  }

  drag(event) {
    if (this.dragPointerId === null || event.pointerId !== this.dragPointerId) return

    const deltaX = event.clientX - this.dragOriginX
    if (!this.dragMoved && Math.abs(deltaX) < DRAG_THRESHOLD_PX) return

    this.dragMoved = true
    const nextLeft = this.clampBarLeft(this.dragOriginLeft + deltaX)
    this.applyBarLeft(nextLeft)
    this.persistBarLeft(nextLeft)
    event.preventDefault()
  }

  stopDrag() {
    if (this.dragPointerId === null) return

    this.clockButtonTarget?.classList.remove("is-dragging")
    this.releaseDragListeners()
    this.dragPointerId = null
    this.dragOriginX = null
    this.dragOriginLeft = null
    this.dragMoved = false
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

    this.ensureCalendarFrameLoaded()
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
    this.stopDrag()
    this.closeCalendar()
  }

  dismissAlert(event) {
    event.preventDefault()
    event.stopPropagation()
    event.stopImmediatePropagation?.()

    const alert = this.alertForControl(event.currentTarget) || this.alertForEvent(event)
    if (!alert) return

    this.writeSessionDismissal(this.alertKey(alert))
    this.hideAlert(alert)
  }

  snoozeAlert(event) {
    event.preventDefault()
    event.stopPropagation()
    event.stopImmediatePropagation?.()

    const alert = this.alertForControl(event.currentTarget) || this.alertForEvent(event)
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
    const timerVisible = this.hasTimesheetTimerTarget && !this.timesheetTimerTarget.hidden
    this.element.hidden = !(clockVisible || alertsVisible || timerVisible)
  }

  syncCalendarState() {
    const expanded = this.hasCalendarPanelTarget && !this.calendarPanelTarget.hidden
    this.element.classList.toggle("is-calendar-open", expanded)

    if (!this.hasClockButtonTarget) return

    this.clockButtonTarget.setAttribute("aria-expanded", expanded ? "true" : "false")
    this.clockButtonTarget.setAttribute("aria-label", expanded ? "Close compact Kalendārium" : "Open compact Kalendārium")
  }

  applyStoredBarPosition() {
    const storedLeft = this.readStoredBarLeft()
    if (!Number.isFinite(storedLeft)) return

    this.applyBarLeft(this.clampBarLeft(storedLeft))
  }

  handleWidgetMessage(event) {
    if (event.origin !== window.location.origin) return

    const messageType = event.data?.type
    if (messageType === "notae:kalendarium-widget:minimize") {
      this.closeCalendar()
    }
  }

  ensureCalendarFrameLoaded() {
    if (!this.hasCalendarFrameTarget) return
    if (this.calendarFrameTarget.getAttribute("src")) return

    const src = this.calendarFrameTarget.dataset.notificationBarCalendarSrc || this.calendarSrcValue
    if (src) this.calendarFrameTarget.setAttribute("src", src)
  }

  requestCalendarRecenter({ retries = 0 } = {}) {
    if (!this.hasCalendarFrameTarget) return
    if (!this.calendarFrameTarget.getAttribute("src")) return

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

  currentBarLeft() {
    const computedLeft = Number.parseFloat(window.getComputedStyle(this.element).left)
    if (Number.isFinite(computedLeft)) return computedLeft

    const rect = this.element.getBoundingClientRect()
    return rect.left
  }

  clampBarLeft(value) {
    const maxLeft = Math.max(BAR_GUTTER_PX, window.innerWidth - this.element.offsetWidth - BAR_GUTTER_PX)
    return Math.min(Math.max(value, BAR_GUTTER_PX), maxLeft)
  }

  applyBarLeft(value) {
    this.element.style.left = `${value}px`
    this.element.style.right = "auto"
  }

  persistBarLeft(value) {
    try {
      window.localStorage.setItem(this.barPositionStorageKey(), String(Math.round(value)))
    } catch (_error) {
      // Ignore storage failures and keep the dragged position for the current page only.
    }
  }

  readStoredBarLeft() {
    try {
      const raw = window.localStorage.getItem(this.barPositionStorageKey())
      if (!raw) return null

      const parsed = Number.parseFloat(raw)
      return Number.isFinite(parsed) ? parsed : null
    } catch (_error) {
      return null
    }
  }

  barPositionStorageKey() {
    return `notae:notification-bar:left:${this.workspaceKeyValue || "global"}`
  }

  releaseDragListeners() {
    window.removeEventListener("pointermove", this.pointerMoveHandler)
    window.removeEventListener("pointerup", this.pointerUpHandler)
  }

  alertForEvent(event) {
    return event.target?.closest("[data-notification-bar-alert-key]") || null
  }

  alertForControl(control) {
    return control?.closest?.("[data-notification-bar-alert-key]") || null
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
        this.updateTimesheetTimerFromPayload(payload?.data?.active_timesheet_timer)
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
