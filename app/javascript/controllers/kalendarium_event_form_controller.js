import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "titleInput",
    "startInput",
    "endInput",
    "allDayInput",
    "rruleInput",
    "frequencySelect",
    "customPanel",
    "intervalInput",
    "unitSelect",
    "weekdayCheckbox",
    "endsSelect",
    "untilInput",
    "countInput",
    "pasteButton"
  ]
  static values = {
    enforceFutureEnd: { type: Boolean, default: false },
    previewEnabled: { type: Boolean, default: false }
  }
  static copyStorageKey = "notae:kalendarium:event-copy"

  connect() {
    this.onAccordionToggle = () => this.accordionToggled()
    this.accordionElement = this.element.closest("details")
    this.dialogElement = this.element.closest("dialog")
    if (this.previewEnabledValue && this.accordionElement) {
      this.accordionElement.addEventListener("toggle", this.onAccordionToggle)
    }

    if (this.allDaySelected) {
      this.applyAllDayTimes()
    }

    this.syncEndConstraints()
    this.initializeRecurrenceControls()
    this.refreshPasteAvailability()
    this.publishPreview()
  }

  disconnect() {
    if (this.previewEnabledValue && this.accordionElement) {
      this.accordionElement.removeEventListener("toggle", this.onAccordionToggle)
    }

    this.clearPreview()
  }

  cancel(event) {
    event?.preventDefault()

    if (typeof this.element.reset === "function") {
      this.element.reset()
    }

    const selectedDate = this.selectedDateValue()
    if (selectedDate) {
      if (this.hasStartInputTarget) {
        this.startInputTarget.value = `${selectedDate}T09:00`
      }

      if (this.hasEndInputTarget) {
        this.endInputTarget.value = `${selectedDate}T10:00`
      }
    }

    this.syncEndConstraints()
    this.clearPreview()

    if (this.accordionElement) {
      this.accordionElement.open = false
    }

    if (this.dialogElement?.open) {
      this.dialogElement.close()
    }
  }

  titleChanged() {
    this.publishPreview()
  }

  startChanged() {
    if (this.allDaySelected) {
      this.normalizeStartTimeToDayBoundary()
      this.normalizeEndTimeToDayBoundary()
    }

    this.syncEndConstraints()
    this.updateWeeklyFrequencyLabel()
    this.updateRruleFromFrequency()
    this.publishPreview()
  }

  endChanged() {
    if (this.allDaySelected) {
      this.normalizeEndTimeToDayBoundary()
    }

    this.syncEndConstraints()
    this.publishPreview()
  }

  toggleAllDay() {
    if (this.allDaySelected) {
      this.applyAllDayTimes()
    }

    this.syncEndConstraints()
    this.publishPreview()
  }

  frequencyChanged() {
    this.updateRruleFromFrequency()
  }

  customRecurrenceChanged() {
    this.updateRruleFromFrequency()
  }

  copyEvent(event) {
    event?.preventDefault()

    const payload = {
      title: this.namedValue("kalendarium_event[title]"),
      calendarId: this.namedValue("kalendarium_event[kalendarium_calendar_id]"),
      projectId: this.namedValue("kalendarium_event[kalendarium_project_id]"),
      startsAtLocal: this.namedValue("kalendarium_event[starts_at_local]"),
      endsAtLocal: this.namedValue("kalendarium_event[ends_at_local]"),
      allDay: this.checkboxChecked("kalendarium_event[all_day]"),
      meetingCaptureEnabled: this.checkboxChecked("kalendarium_event[meeting_capture_enabled]"),
      location: this.namedValue("kalendarium_event[location]"),
      description: this.namedValue("kalendarium_event[description]"),
      rrule: this.hasRruleInputTarget ? this.rruleInputTarget.value : ""
    }

    window.localStorage?.setItem(this.constructor.copyStorageKey, JSON.stringify(payload))
    this.refreshPasteAvailability()
  }

  pasteEvent(event) {
    event?.preventDefault()

    const payload = this.copiedEventPayload()
    if (!payload) return

    const startBeforePaste = this.hasStartInputTarget ? this.startInputTarget.value : ""
    this.setNamedValue("kalendarium_event[title]", payload.title)
    this.setNamedValue("kalendarium_event[kalendarium_calendar_id]", payload.calendarId)
    this.setNamedValue("kalendarium_event[kalendarium_project_id]", payload.projectId)
    this.setNamedValue("kalendarium_event[location]", payload.location)
    this.setNamedValue("kalendarium_event[description]", payload.description)
    this.setCheckboxValue("kalendarium_event[all_day]", payload.allDay)
    this.setCheckboxValue("kalendarium_event[meeting_capture_enabled]", payload.meetingCaptureEnabled)

    if (this.hasRruleInputTarget) {
      this.rruleInputTarget.value = payload.rrule || ""
      this.initializeRecurrenceControls()
    }

    if (startBeforePaste && this.hasStartInputTarget) {
      this.startInputTarget.value = startBeforePaste
      const durationMinutes = this.copiedDurationMinutes(payload)
      if (this.hasEndInputTarget && durationMinutes > 0) {
        this.endInputTarget.value = this.addMinutesToLocalValue(startBeforePaste, durationMinutes)
      }
    }

    this.syncEndConstraints()
    this.publishPreview()
  }

  applyAllDayTimes() {
    this.normalizeStartTimeToDayBoundary()
    this.normalizeEndTimeToDayBoundary()
  }

  normalizeStartTimeToDayBoundary() {
    if (!this.hasStartInputTarget) return

    const startDate = this.datePortion(this.startInputTarget.value)
    if (!startDate) return

    this.startInputTarget.value = `${startDate}T00:00`
  }

  normalizeEndTimeToDayBoundary() {
    if (!this.hasEndInputTarget) return

    const startDate = this.hasStartInputTarget ? this.datePortion(this.startInputTarget.value) : null
    const endDate = this.datePortion(this.endInputTarget.value)
    const chosenDate = this.maxDateString(startDate, endDate)
    if (!chosenDate) return

    this.endInputTarget.value = `${chosenDate}T23:59`
  }

  syncEndConstraints() {
    if (!this.hasEndInputTarget) return

    if (this.enforceFutureEndValue) {
      let minimum = this.nowLocalTimestamp()
      if (this.hasStartInputTarget && this.startInputTarget.value) {
        minimum = this.maxDateTimeString(minimum, this.startInputTarget.value)
      }

      this.endInputTarget.min = minimum
      if (this.endInputTarget.value && this.endInputTarget.value < minimum) {
        this.endInputTarget.value = minimum
      }
      return
    }

    if (this.hasStartInputTarget && this.startInputTarget.value) {
      this.endInputTarget.min = this.startInputTarget.value
      if (this.endInputTarget.value && this.endInputTarget.value < this.startInputTarget.value) {
        this.endInputTarget.value = this.startInputTarget.value
      }
      return
    }

    this.endInputTarget.removeAttribute("min")
  }

  initializeRecurrenceControls() {
    if (!this.hasFrequencySelectTarget || !this.hasRruleInputTarget) return

    const parsed = this.parseRrule(this.rruleInputTarget.value)
    this.frequencySelectTarget.value = parsed.frequency

    if (this.hasIntervalInputTarget) this.intervalInputTarget.value = parsed.interval
    if (this.hasUnitSelectTarget) this.unitSelectTarget.value = parsed.unit
    if (this.hasEndsSelectTarget) this.endsSelectTarget.value = parsed.ends
    if (this.hasUntilInputTarget) this.untilInputTarget.value = parsed.until
    if (this.hasCountInputTarget) this.countInputTarget.value = parsed.count
    if (this.hasWeekdayCheckboxTarget) {
      this.weekdayCheckboxTargets.forEach((checkbox) => {
        checkbox.checked = parsed.weekdays.includes(checkbox.value)
      })
    }

    this.updateWeeklyFrequencyLabel()
    this.syncCustomPanelVisibility()
    this.syncCustomEndControls()
  }

  updateRruleFromFrequency() {
    if (!this.hasFrequencySelectTarget || !this.hasRruleInputTarget) return

    const frequency = this.frequencySelectTarget.value
    if (frequency === "never") {
      this.rruleInputTarget.value = ""
    } else if (frequency === "daily") {
      this.rruleInputTarget.value = "FREQ=DAILY"
    } else if (frequency === "weekly") {
      this.rruleInputTarget.value = `FREQ=WEEKLY;BYDAY=${this.startWeekdayCode()}`
    } else {
      this.rruleInputTarget.value = this.customRruleValue()
    }

    this.syncCustomPanelVisibility()
    this.syncCustomEndControls()
  }

  customRruleValue() {
    const unit = this.hasUnitSelectTarget ? this.unitSelectTarget.value : "WEEKLY"
    const interval = Math.max(Number.parseInt(this.hasIntervalInputTarget ? this.intervalInputTarget.value : "1", 10) || 1, 1)
    const parts = [`FREQ=${unit}`, `INTERVAL=${interval}`]

    if (unit === "WEEKLY") {
      const days = this.selectedWeekdays()
      parts.push(`BYDAY=${days.length > 0 ? days.join(",") : this.startWeekdayCode()}`)
    }

    const ends = this.hasEndsSelectTarget ? this.endsSelectTarget.value : "never"
    if (ends === "until" && this.hasUntilInputTarget && this.untilInputTarget.value) {
      parts.push(`UNTIL=${this.untilInputTarget.value.replaceAll("-", "")}T235959Z`)
    } else if (ends === "count" && this.hasCountInputTarget) {
      const count = Math.max(Number.parseInt(this.countInputTarget.value, 10) || 1, 1)
      parts.push(`COUNT=${count}`)
    }

    return parts.join(";")
  }

  parseRrule(value) {
    const parts = Object.fromEntries(
      value.toString().split(";").filter(Boolean).map((entry) => {
        const [key, ...rest] = entry.split("=")
        return [key, rest.join("=")]
      })
    )
    const frequency = parts.FREQ === "DAILY" && !parts.INTERVAL && !parts.COUNT && !parts.UNTIL ? "daily" :
      parts.FREQ === "WEEKLY" && !parts.INTERVAL && !parts.COUNT && !parts.UNTIL ? "weekly" :
        parts.FREQ ? "custom" : "never"

    return {
      frequency,
      interval: parts.INTERVAL || "1",
      unit: parts.FREQ || "WEEKLY",
      weekdays: (parts.BYDAY || "").split(",").filter(Boolean),
      ends: parts.UNTIL ? "until" : parts.COUNT ? "count" : "never",
      until: parts.UNTIL ? `${parts.UNTIL.slice(0, 4)}-${parts.UNTIL.slice(4, 6)}-${parts.UNTIL.slice(6, 8)}` : "",
      count: parts.COUNT || "10"
    }
  }

  syncCustomPanelVisibility() {
    if (!this.hasCustomPanelTarget || !this.hasFrequencySelectTarget) return

    this.customPanelTarget.hidden = this.frequencySelectTarget.value !== "custom"
  }

  syncCustomEndControls() {
    const ends = this.hasEndsSelectTarget ? this.endsSelectTarget.value : "never"
    if (this.hasUntilInputTarget) this.untilInputTarget.hidden = ends !== "until"
    if (this.hasCountInputTarget) this.countInputTarget.hidden = ends !== "count"
  }

  updateWeeklyFrequencyLabel() {
    if (!this.hasFrequencySelectTarget) return

    const option = Array.from(this.frequencySelectTarget.options).find((candidate) => candidate.value === "weekly")
    if (option) option.textContent = `Every week on ${this.startWeekdayName()}`
  }

  selectedWeekdays() {
    if (!this.hasWeekdayCheckboxTarget) return []

    return this.weekdayCheckboxTargets.filter((checkbox) => checkbox.checked).map((checkbox) => checkbox.value)
  }

  startWeekdayCode() {
    const codes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
    return codes[this.startDateObject().getDay()]
  }

  startWeekdayName() {
    return new Intl.DateTimeFormat("en-AU", { weekday: "long" }).format(this.startDateObject())
  }

  startDateObject() {
    if (this.hasStartInputTarget && this.startInputTarget.value) {
      const parsed = new Date(this.startInputTarget.value)
      if (!Number.isNaN(parsed.getTime())) return parsed
    }

    return new Date()
  }

  get allDaySelected() {
    return this.hasAllDayInputTarget && this.allDayInputTarget.checked
  }

  nowLocalTimestamp() {
    const now = new Date()
    const year = now.getFullYear()
    const month = String(now.getMonth() + 1).padStart(2, "0")
    const day = String(now.getDate()).padStart(2, "0")
    const hours = String(now.getHours()).padStart(2, "0")
    const minutes = String(now.getMinutes()).padStart(2, "0")
    return `${year}-${month}-${day}T${hours}:${minutes}`
  }

  datePortion(value) {
    if (!value) return null

    const parts = value.split("T")
    return parts[0] || null
  }

  maxDateString(firstDate, secondDate) {
    if (firstDate && secondDate) return firstDate >= secondDate ? firstDate : secondDate
    return firstDate || secondDate || null
  }

  maxDateTimeString(firstValue, secondValue) {
    if (firstValue && secondValue) return firstValue >= secondValue ? firstValue : secondValue
    return firstValue || secondValue || ""
  }

  accordionToggled() {
    if (this.accordionElement?.open) {
      this.publishPreview()
    } else {
      this.clearPreview()
    }
  }

  publishPreview() {
    if (!this.previewEnabledValue) return
    if (this.accordionElement && !this.accordionElement.open) {
      this.clearPreview()
      return
    }

    const detail = this.previewDetail()
    if (!detail) {
      this.clearPreview()
      return
    }

    this.dispatchPreview("kalendarium:preview-event", detail)
  }

  clearPreview() {
    if (!this.previewEnabledValue) return

    this.dispatchPreview("kalendarium:preview-clear", {})
  }

  previewDetail() {
    if (!this.hasStartInputTarget || !this.hasEndInputTarget) return null
    if (!this.startInputTarget.value || !this.endInputTarget.value) return null

    const dateString = this.datePortion(this.startInputTarget.value)
    if (!dateString) return null

    return {
      title: this.hasTitleInputTarget ? this.titleInputTarget.value : "",
      date: dateString,
      startLocal: this.startInputTarget.value,
      endLocal: this.endInputTarget.value,
      allDay: this.allDaySelected
    }
  }

  dispatchPreview(name, detail) {
    const shell = this.element.closest(".notae-kalendarium")
    if (!shell) return

    shell.dispatchEvent(new CustomEvent(name, {
      bubbles: true,
      detail
    }))
  }

  selectedDateValue() {
    const dateInput = this.element.querySelector("input[name='date']")
    const selectedDate = this.datePortion(dateInput?.value)
    if (selectedDate) return selectedDate

    return this.hasStartInputTarget ? this.datePortion(this.startInputTarget.value) : null
  }

  refreshPasteAvailability() {
    if (!this.hasPasteButtonTarget) return

    this.pasteButtonTarget.disabled = this.copiedEventPayload() === null
  }

  copiedEventPayload() {
    const raw = window.localStorage?.getItem(this.constructor.copyStorageKey)
    if (!raw) return null

    try {
      const payload = JSON.parse(raw)
      return payload && typeof payload === "object" ? payload : null
    } catch (_error) {
      return null
    }
  }

  copiedDurationMinutes(payload) {
    const start = new Date(payload.startsAtLocal)
    const end = new Date(payload.endsAtLocal)
    if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) return 60

    return Math.max(Math.round((end.getTime() - start.getTime()) / 60000), 1)
  }

  addMinutesToLocalValue(localValue, minutes) {
    const date = new Date(localValue)
    date.setMinutes(date.getMinutes() + minutes)

    const year = date.getFullYear()
    const month = String(date.getMonth() + 1).padStart(2, "0")
    const day = String(date.getDate()).padStart(2, "0")
    const hours = String(date.getHours()).padStart(2, "0")
    const nextMinutes = String(date.getMinutes()).padStart(2, "0")
    return `${year}-${month}-${day}T${hours}:${nextMinutes}`
  }

  namedValue(name) {
    return this.element.querySelector(`[name='${name}']`)?.value || ""
  }

  setNamedValue(name, value) {
    const field = this.element.querySelector(`[name='${name}']`)
    if (!field) return

    field.value = value || ""
    field.dispatchEvent(new Event("change", { bubbles: true }))
  }

  checkboxChecked(name) {
    return this.element.querySelector(`[name='${name}']`)?.checked || false
  }

  setCheckboxValue(name, value) {
    const field = this.element.querySelector(`[name='${name}']`)
    if (!field) return

    field.checked = Boolean(value)
    field.dispatchEvent(new Event("change", { bubbles: true }))
  }
}
