import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["viewLink", "dateInput", "dateLabel", "dayLink", "weekTrack", "monthCell", "createAccordion", "createTitleInput", "createStartInput", "createEndInput", "createAllDayInput"]
  static values = {
    selectedDate: String,
    view: String,
    windowStart: String
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

    if (this.hasCreateAccordionTarget) {
      this.createAccordionTarget.open = true
      this.createAccordionTarget.scrollIntoView({ block: "nearest" })
    }

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

    if (this.hasCreateTitleInputTarget) {
      window.requestAnimationFrame(() => {
        this.createTitleInputTarget.focus()
        this.createTitleInputTarget.select()
      })
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
}
