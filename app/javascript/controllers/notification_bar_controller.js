import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["clock"]
  static values = { timeZone: String }

  connect() {
    this.renderClock()
    this.startClock()
  }

  disconnect() {
    this.stopClock()
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

  resolvedTimeZone() {
    const value = this.timeZoneValue?.trim()
    return value && value.length > 0 ? value : undefined
  }
}
