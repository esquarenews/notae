import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["scroller", "nowLine", "nowLineLabel"]
  static values = {
    startHour: Number,
    slotHeight: Number,
    allDayOffset: Number,
    timeZone: String,
    initialFocusMinutes: Number,
    centerCurrentTime: Boolean,
    taskScheduling: Boolean,
    taskDefaultDurationMinutes: Number
  }

  connect() {
    this.element.style.setProperty("--kal-all-day-offset", `${this.allDayOffsetForScroll()}px`)

    this.onLayoutChange = () => this.updateNowLine()
    this.onScrollerScroll = () => this.updateNowLine()
    this.handleWidgetMessage = this.handleWidgetMessage.bind(this)
    window.addEventListener("resize", this.onLayoutChange)
    window.addEventListener("notae:layout-changed", this.onLayoutChange)
    window.addEventListener("message", this.handleWidgetMessage)
    if (this.hasScrollerTarget) {
      this.scrollerTarget.addEventListener("scroll", this.onScrollerScroll, { passive: true })
    }

    if (this.hasScrollerTarget && this.scrollerTarget.dataset.kalendariumTimelineInitialized !== "true") {
      const startHour = this.hasStartHourValue ? this.startHourValue : 5
      const slotHeight = this.hasSlotHeightValue ? this.slotHeightValue : 28
      const slotsPerHour = 2
      const fallbackTop = startHour * slotsPerHour * slotHeight

      if (this.hasInitialFocusMinutesValue) {
        const rawTop = this.focusedScrollTop(((this.initialFocusMinutesValue / 30.0) * slotHeight), this.hasCenterCurrentTimeValue && this.centerCurrentTimeValue ? 0.5 : 0.2)
        this.scrollerTarget.scrollTop = Math.max(rawTop, 0)
      } else if (!this.centerOnCurrentTime()) {
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
    window.removeEventListener("message", this.handleWidgetMessage)
    if (this.hasScrollerTarget) {
      this.scrollerTarget.removeEventListener("scroll", this.onScrollerScroll)
    }

    if (this.nowTimer) {
      window.clearInterval(this.nowTimer)
      this.nowTimer = null
    }
  }

  centerOnCurrentTime() {
    if (!this.hasScrollerTarget) return false

    const now = this.currentZonedTime()
    const canFocusNow = now && this.hasNowDateInView(now.date)
    if (!canFocusNow) return false

    const slotHeight = this.hasSlotHeightValue ? this.slotHeightValue : 28
    const minutesIntoDay = (now.hour * 60) + now.minute
    const rawTop = this.focusedScrollTop(
      ((minutesIntoDay / 30.0) * slotHeight),
      this.hasCenterCurrentTimeValue && this.centerCurrentTimeValue ? 0.5 : 0.35
    )
    this.scrollerTarget.scrollTop = Math.max(rawTop, 0)
    return true
  }

  handleWidgetMessage(event) {
    if (event.origin !== window.location.origin) return

    const messageType = event.data?.type
    if (messageType === "notae:kalendarium-widget:center-current-time") {
      this.centerOnCurrentTime()
      this.updateNowLine()
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

  quickCreate(event) {
    if (this.interactiveTarget(event.target)) return

    const track = event.currentTarget
    if (!(track instanceof HTMLElement)) return

    const dateString = track.dataset.dayDate
    if (!dateString) return

    const rect = track.getBoundingClientRect()
    const rawY = event.clientY - rect.top
    const slotHeight = this.hasSlotHeightValue ? this.slotHeightValue : 28
    const usableY = Math.max(rawY - this.allDayOffsetForScroll(), 0)
    const slotIndex = Math.max(Math.floor(usableY / slotHeight), 0)
    const startMinutes = Math.min(slotIndex * 30, (24 * 60) - 30)
    const taskDurationMinutes = this.hasTaskDefaultDurationMinutesValue ? this.taskDefaultDurationMinutesValue : 20
    const endMinutes = this.taskSchedulingValue ? Math.min(startMinutes + taskDurationMinutes, 24 * 60) : startMinutes + 60

    if (this.taskSchedulingValue) {
      this.element.dispatchEvent(new CustomEvent("kalendarium:task-slot-draft", {
        bubbles: true,
        detail: {
          date: dateString,
          label: "Custom slot",
          startLocal: this.localTimestampFor(dateString, startMinutes),
          endLocal: this.localTimestampFor(dateString, endMinutes)
        }
      }))
      return
    }

    this.element.dispatchEvent(new CustomEvent("kalendarium:quick-create", {
      bubbles: true,
      detail: {
        date: dateString,
        startLocal: this.localTimestampFor(dateString, startMinutes),
        endLocal: this.localTimestampFor(dateString, endMinutes)
      }
    }))
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

  focusedScrollTop(focusPixels, viewportRatio) {
    return this.allDayOffsetForScroll() + focusPixels - (this.scrollerTarget.clientHeight * viewportRatio)
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

  interactiveTarget(target) {
    if (!(target instanceof Element)) return false

    return target.closest("a, button, input, textarea, select, label, summary, details, dialog, form, .notae-kalendarium-event-card") !== null
  }

  localTimestampFor(dateString, minutesIntoDay) {
    const [year, month, day] = dateString.split("-").map((part) => Number.parseInt(part, 10))
    if (!year || !month || !day) return ""

    const baseDate = new Date(year, month - 1, day, 0, 0, 0, 0)
    baseDate.setMinutes(minutesIntoDay)

    const formattedYear = String(baseDate.getFullYear())
    const formattedMonth = String(baseDate.getMonth() + 1).padStart(2, "0")
    const formattedDay = String(baseDate.getDate()).padStart(2, "0")
    const formattedHour = String(baseDate.getHours()).padStart(2, "0")
    const formattedMinute = String(baseDate.getMinutes()).padStart(2, "0")
    return `${formattedYear}-${formattedMonth}-${formattedDay}T${formattedHour}:${formattedMinute}`
  }
}
