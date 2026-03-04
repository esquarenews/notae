import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static STATUS_CLASS_BY_VALUE = {
    "not started": "is-status-not-started",
    "started": "is-status-started",
    "overdue": "is-status-overdue",
    "hold": "is-status-hold",
    "done": "is-status-done"
  }

  static LEGACY_STATUS_MAP = {
    "planning": "not started",
    "in progress": "started",
    "on hold": "hold",
    "complete": "done",
    "completed": "done"
  }

  static STATUS_CLASSES = Object.values(this.STATUS_CLASS_BY_VALUE)

  formFor(event) {
    return event.target?.form || event.target?.closest("form")
  }

  submit(event) {
    this.applyTaskStatusVisualState(event.target)

    const form = this.formFor(event)
    if (!form) return

    form.requestSubmit()
  }

  submitOnEnter(event) {
    event.preventDefault()
    const form = this.formFor(event)
    if (!form) return

    const createNextOnEnter = event.target?.dataset?.autoSubmitCreateNextRowOnEnter === "true"
    if (createNextOnEnter) {
      const createNextField = form.querySelector('input[name="db_row[create_next_row]"]')
      if (createNextField) createNextField.value = "1"
    }

    form.requestSubmit()
  }

  submitAndCreateNextOnEnter(event) {
    this.submitOnEnter(event)
  }

  navigate(event) {
    const destination = event.target?.value?.toString().trim()
    if (!destination) return

    window.location.assign(destination)
  }

  applyTaskStatusVisualState(target) {
    if (!(target instanceof HTMLSelectElement)) return
    if (!target.classList.contains("notae-db-cell-select-status")) return

    const normalized = this.normalizeTaskStatusValue(target.value)
    this.applyTaskStatusSelectClasses(target, normalized)
    this.applyTaskStatusRowClasses(target, normalized)
  }

  normalizeTaskStatusValue(value) {
    const raw = value?.toString().trim().toLowerCase() || ""
    return this.constructor.LEGACY_STATUS_MAP[raw] || raw
  }

  applyTaskStatusSelectClasses(select, normalizedStatus) {
    select.classList.remove(...this.constructor.STATUS_CLASSES)
    const statusClass = this.constructor.STATUS_CLASS_BY_VALUE[normalizedStatus]
    if (statusClass) {
      select.classList.add(statusClass)
    }
  }

  applyTaskStatusRowClasses(select, normalizedStatus) {
    const row = select.closest("tr.notae-db-grid-data-row")
    if (!row) return

    row.classList.toggle("is-row-color-gray", normalizedStatus === "done")
  }
}
