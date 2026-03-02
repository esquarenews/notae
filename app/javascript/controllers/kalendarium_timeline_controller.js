import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["scroller", "nowLine", "nowLineLabel"]
  static values = {
    startHour: Number,
    slotHeight: Number,
    allDayOffset: Number,
    timeZone: String
  }

  connect() {
    this.onLayoutChange = () => this.updateNowLine()
    this.onScrollerScroll = () => this.updateNowLine()
    window.addEventListener("resize", this.onLayoutChange)
    window.addEventListener("notae:layout-changed", this.onLayoutChange)
    if (this.hasScrollerTarget) {
      this.scrollerTarget.addEventListener("scroll", this.onScrollerScroll, { passive: true })
    }

    if (this.hasScrollerTarget && this.scrollerTarget.dataset.kalendariumTimelineInitialized !== "true") {
      const startHour = this.hasStartHourValue ? this.startHourValue : 5
      const slotHeight = this.hasSlotHeightValue ? this.slotHeightValue : 28
      const slotsPerHour = 2
      const fallbackTop = startHour * slotsPerHour * slotHeight
      const now = this.currentZonedTime()
      const canFocusNow = now && this.hasNowDateInView(now.date)

      if (canFocusNow) {
        const minutesIntoDay = (now.hour * 60) + now.minute
        const rawTop = this.allDayOffsetForScroll() + ((minutesIntoDay / 30.0) * slotHeight) - (this.scrollerTarget.clientHeight * 0.35)
        this.scrollerTarget.scrollTop = Math.max(rawTop, 0)
      } else {
        this.scrollerTarget.scrollTop = this.allDayOffsetForScroll() + fallbackTop
      }

      this.scrollerTarget.dataset.kalendariumTimelineInitialized = "true"
    }

    this.updateNowLine()
    this.nowTimer = window.setInterval(() => this.updateNowLine(), 15000)
  }

  disconnect() {
    window.removeEventListener("resize", this.onLayoutChange)
    window.removeEventListener("notae:layout-changed", this.onLayoutChange)
    if (this.hasScrollerTarget) {
      this.scrollerTarget.removeEventListener("scroll", this.onScrollerScroll)
    }

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
      if (label) {
        label.textContent = `Now ${labelText}`
        this.positionNowLabel(label, line)
      }
    })
  }

  positionNowLabel(label, line) {
    label.classList.remove("is-left")
    label.style.left = ""
    label.style.maxWidth = ""

    const scroller = this.hasScrollerTarget ? this.scrollerTarget : line.closest(".notae-kalendarium-timeline-scroller")
    if (!scroller) return

    const viewportPadding = 6
    const scrollerRect = scroller.getBoundingClientRect()
    const lineRect = line.getBoundingClientRect()
    let labelRect = label.getBoundingClientRect()

    // Keep the badge inside the visible scroll viewport when side rails narrow the timeline.
    if (labelRect.right > scrollerRect.right - viewportPadding || labelRect.right > lineRect.right - 2) {
      label.classList.add("is-left")
      labelRect = label.getBoundingClientRect()
    }

    if (label.classList.contains("is-left") && labelRect.left < scrollerRect.left + viewportPadding) {
      const shiftPixels = (scrollerRect.left + viewportPadding) - labelRect.left
      label.style.left = `calc(0.42rem + ${shiftPixels.toFixed(2)}px)`
      labelRect = label.getBoundingClientRect()
    }

    const availableWidth = scrollerRect.width - (viewportPadding * 2)
    if (availableWidth > 0 && labelRect.width > availableWidth) {
      label.style.maxWidth = `${Math.floor(availableWidth)}px`
    }
  }

  allDayOffsetForScroll() {
    if (!this.hasAllDayOffsetValue) return 0

    const parsed = Number.parseFloat(this.allDayOffsetValue)
    if (Number.isNaN(parsed) || parsed <= 0) return 0

    return parsed
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
