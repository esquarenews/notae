import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["scroller", "nowLine", "nowLineLabel"]
  static values = {
    startHour: Number,
    slotHeight: Number,
    timeZone: String
  }

  connect() {
    if (this.hasScrollerTarget && this.scrollerTarget.dataset.kalendariumTimelineInitialized !== "true") {
      const startHour = this.hasStartHourValue ? this.startHourValue : 5
      const slotHeight = this.hasSlotHeightValue ? this.slotHeightValue : 28
      const slotsPerHour = 2
      const fallbackTop = startHour * slotsPerHour * slotHeight
      const now = this.currentZonedTime()
      const canFocusNow = now && this.hasNowDateInView(now.date)

      if (canFocusNow) {
        const minutesIntoDay = (now.hour * 60) + now.minute
        const rawTop = ((minutesIntoDay / 30.0) * slotHeight) - (this.scrollerTarget.clientHeight * 0.35)
        this.scrollerTarget.scrollTop = Math.max(rawTop, 0)
      } else {
        this.scrollerTarget.scrollTop = fallbackTop
      }

      this.scrollerTarget.dataset.kalendariumTimelineInitialized = "true"
    }

    this.updateNowLine()
    this.nowTimer = window.setInterval(() => this.updateNowLine(), 15000)
  }

  disconnect() {
    if (this.nowTimer) {
      window.clearInterval(this.nowTimer)
      this.nowTimer = null
    }
  }

  updateNowLine() {
    if (!this.hasNowLineTarget) return

    const now = this.currentZonedTime()
    if (!now) {
      this.nowLineTargets.forEach((line) => {
        line.hidden = true
      })
      return
    }

    const slotHeight = this.hasSlotHeightValue ? this.slotHeightValue : 28
    const topPixels = ((now.hour * 60 + now.minute + (now.second / 60.0)) / 30.0) * slotHeight
    const labelText = `${String(now.hour).padStart(2, "0")}:${String(now.minute).padStart(2, "0")}`

    this.nowLineTargets.forEach((line) => {
      const lineDate = line.dataset.nowDate
      const shouldShow = lineDate === now.date
      line.hidden = !shouldShow
      if (!shouldShow) return

      line.style.top = `${topPixels.toFixed(2)}px`
      const label = line.querySelector(".notae-kalendarium-now-line-label")
      if (label) label.textContent = `Now ${labelText}`
    })
  }

  currentZonedTime() {
    const formatter = this.zonedFormatter()
    const parts = formatter.formatToParts(new Date())
    const fields = {}
    parts.forEach((part) => {
      if (part.type !== "literal") fields[part.type] = part.value
    })

    const year = fields.year
    const month = fields.month
    const day = fields.day
    const hour = Number.parseInt(fields.hour, 10)
    const minute = Number.parseInt(fields.minute, 10)
    const second = Number.parseInt(fields.second, 10)
    if (!year || !month || !day || Number.isNaN(hour) || Number.isNaN(minute) || Number.isNaN(second)) return null

    return {
      date: `${year}-${month}-${day}`,
      hour,
      minute,
      second
    }
  }

  hasNowDateInView(dateString) {
    if (!this.hasNowLineTarget) return false
    return this.nowLineTargets.some((line) => line.dataset.nowDate === dateString)
  }

  zonedFormatter() {
    if (this._zonedFormatter) return this._zonedFormatter

    this._zonedFormatter = new Intl.DateTimeFormat("en-CA", {
      timeZone: this.hasTimeZoneValue ? this.timeZoneValue : Intl.DateTimeFormat().resolvedOptions().timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23"
    })

    return this._zonedFormatter
  }
}
