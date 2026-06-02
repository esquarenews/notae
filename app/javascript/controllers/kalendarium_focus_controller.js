import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["viewLink", "dateInput", "dateLabel", "dayLink", "weekTrack", "monthCell", "createAccordion", "createDialog", "createTitleInput", "createStartInput", "createEndInput", "createAllDayInput"]
  static values = {
    selectedDate: String,
    view: String,
    windowStart: String,
    widget: { type: Boolean, default: false }
  }

  connect() {
    if (this.hasSelectedDateValue) {
      this.applySelectedDate(this.selectedDateValue)
    }
  }

  selectDay(event) {
    if (!event.currentTarget?.dataset?.dayDate) return
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0) return

    event.preventDefault()

    const nextDate = event.currentTarget.dataset.dayDate
    this.selectedDateValue = nextDate
    this.applySelectedDate(nextDate)
    this.replaceCurrentUrlDate(nextDate)
  }

  prepareNewEvent(event) {
    const detail = event.detail || {}
    const dateString = detail.date
    if (!dateString) return

    this.selectedDateValue = dateString
    this.applySelectedDate(dateString)

    if (this.hasCreateAllDayInputTarget && this.createAllDayInputTarget.checked) {
      this.createAllDayInputTarget.checked = false
      this.dispatchChange(this.createAllDayInputTarget)
    }

    if (this.hasCreateStartInputTarget && detail.startLocal) {
      this.createStartInputTarget.value = detail.startLocal
      this.dispatchChange(this.createStartInputTarget)
    }

    if (this.hasCreateEndInputTarget && detail.endLocal) {
      this.createEndInputTarget.value = detail.endLocal
      this.dispatchChange(this.createEndInputTarget)
    }

    this.openCreateSurface()
    this.focusCreateTitleInput()
  }

  quickCreateDay(event) {
    if (this.interactiveTarget(event.target) && !this.dayFocusTarget(event.target)) return

    const dateString = event.currentTarget?.dataset?.dayDate
    if (!dateString) return

    event.preventDefault()
    this.prepareNewEvent({ detail: this.defaultQuickCreateDetail(dateString) })
  }

  openCreateModal(event) {
    event?.preventDefault()

    const dateString = this.hasSelectedDateValue && this.selectedDateValue ? this.selectedDateValue : this.todayDateString()
    this.prepareNewEvent({ detail: this.defaultQuickCreateDetail(dateString) })
  }

  closeCreateDialog(event) {
    event?.preventDefault()
    if (!this.hasCreateDialogTarget) return

    this.createDialogTarget.close()
  }

  backdropCloseCreateDialog(event) {
    if (!this.hasCreateDialogTarget) return
    if (event.target !== this.createDialogTarget) return

    this.createDialogTarget.close()
  }

  minimizeWidget(event) {
    event?.preventDefault()

    if (window.parent && window.parent !== window) {
      window.parent.postMessage({ type: "notae:kalendarium-widget:minimize" }, window.location.origin)
    }
  }

  applySelectedDate(dateString) {
    if (!dateString) return

    this.updateDateInputs(dateString)
    this.updateViewLinks(dateString)
    this.updateDateLabel(dateString)
    this.updateSelectionClasses(dateString)
  }

  updateDateInputs(dateString) {
    this.dateInputTargets.forEach((input) => {
      input.value = dateString
    })
  }

  updateViewLinks(dateString) {
    this.viewLinkTargets.forEach((link) => {
      let nextUrl
      try {
        nextUrl = new URL(link.href, window.location.origin)
      } catch (_error) {
        return
      }

      nextUrl.searchParams.set("date", dateString)
      link.href = `${nextUrl.pathname}${nextUrl.search}${nextUrl.hash}`
    })
  }

  updateDateLabel(dateString) {
    if (!this.hasDateLabelTarget) return

    const parsed = this.parseIsoDate(dateString)
    if (!parsed) return

    this.dateLabelTarget.textContent = this.formatDateLabel(parsed)
  }

  updateSelectionClasses(dateString) {
    this.dayLinkTargets.forEach((link) => {
      const isSelected = link.dataset.dayDate === dateString
      link.classList.toggle("is-selected", isSelected)
      if (isSelected) {
        link.setAttribute("aria-current", "date")
      } else {
        link.removeAttribute("aria-current")
      }
    })

    this.weekTrackTargets.forEach((track) => {
      const isSelected = track.dataset.dayDate === dateString
      track.classList.toggle("is-selected", isSelected)
    })

    this.monthCellTargets.forEach((cell) => {
      const isSelected = cell.dataset.dayDate === dateString
      cell.classList.toggle("is-selected", isSelected)
    })
  }

  replaceCurrentUrlDate(dateString) {
    if (!window.history?.replaceState) return

    let current
    try {
      current = new URL(window.location.href)
    } catch (_error) {
      return
    }

    current.searchParams.set("date", dateString)
    window.history.replaceState({}, "", `${current.pathname}${current.search}${current.hash}`)
  }

  dispatchChange(element) {
    element.dispatchEvent(new Event("change", { bubbles: true }))
  }

  openCreateSurface() {
    if (this.hasCreateDialogTarget) {
      if (!this.createDialogTarget.open) {
        this.createDialogTarget.showModal()
      }
      return
    }

    if (this.hasCreateAccordionTarget) {
      this.createAccordionTarget.open = true
      this.createAccordionTarget.scrollIntoView({ block: "nearest" })
    }
  }

  focusCreateTitleInput() {
    if (!this.hasCreateTitleInputTarget) return

    window.requestAnimationFrame(() => {
      this.createTitleInputTarget.focus()
      this.createTitleInputTarget.select()
    })
  }

  parseIsoDate(dateString) {
    const [year, month, day] = dateString.split("-").map((part) => Number.parseInt(part, 10))
    if (!year || !month || !day) return null

    return new Date(Date.UTC(year, month - 1, day))
  }

  formatDateLabel(dateObject) {
    const view = this.hasViewValue ? this.viewValue : "month"

    if (view === "day") {
      return new Intl.DateTimeFormat("en-AU", {
        weekday: "long",
        day: "numeric",
        month: "long",
        year: "numeric",
        timeZone: "UTC"
      }).format(dateObject)
    }

    if (view === "year") {
      return new Intl.DateTimeFormat("en-AU", {
        year: "numeric",
        timeZone: "UTC"
      }).format(dateObject)
    }

    if (view === "next_7_days") {
      const startDate = this.parseIsoDate(this.hasWindowStartValue ? this.windowStartValue : "") || dateObject
      const endDate = new Date(startDate.getTime())
      endDate.setUTCDate(endDate.getUTCDate() + 6)

      const startLabel = new Intl.DateTimeFormat("en-US", {
        month: "short",
        day: "numeric",
        timeZone: "UTC"
      }).format(startDate)
      const endLabel = new Intl.DateTimeFormat("en-US", {
        month: "short",
        day: "numeric",
        year: "numeric",
        timeZone: "UTC"
      }).format(endDate)

      return `${startLabel} - ${endLabel}`
    }

    return new Intl.DateTimeFormat("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric",
      timeZone: "UTC"
    }).format(dateObject)
  }

  defaultQuickCreateDetail(dateString) {
    return {
      date: dateString,
      startLocal: `${dateString}T09:00`,
      endLocal: `${dateString}T10:00`
    }
  }

  todayDateString() {
    const now = new Date()
    const year = now.getFullYear()
    const month = String(now.getMonth() + 1).padStart(2, "0")
    const day = String(now.getDate()).padStart(2, "0")

    return `${year}-${month}-${day}`
  }

  interactiveTarget(target) {
    if (!(target instanceof Element)) return false

    return target.closest("a, button, input, textarea, select, label, summary, details, form, .notae-kalendarium-event-card") !== null
  }

  dayFocusTarget(target) {
    if (!(target instanceof Element)) return false

    return target.closest("[data-kalendarium-day-focus='true']") !== null
  }
}
