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

  connect() {
    this.handleSubmitStart = () => this.markSubmitting()
    this.handleSubmitEnd = () => this.clearSubmitting()
    this.clearSubmitting()

    if (this.element instanceof HTMLFormElement) {
      this.element.addEventListener("turbo:submit-start", this.handleSubmitStart)
      this.element.addEventListener("turbo:submit-end", this.handleSubmitEnd)
    }
  }

  disconnect() {
    if (this.element instanceof HTMLFormElement) {
      this.element.removeEventListener("turbo:submit-start", this.handleSubmitStart)
      this.element.removeEventListener("turbo:submit-end", this.handleSubmitEnd)
    }
  }

  formFor(event) {
    return event.target?.form || event.target?.closest("form")
  }

  submit(event) {
    this.applyTaskStatusVisualState(event.target)

    const form = this.formFor(event)
    if (!form) return

    this.requestSubmitOnce(form)
  }

  submitOnEnter(event) {
    event.preventDefault()
    const form = this.formFor(event)
    if (!form) return

    let submitter
    const createNextOnEnter = event.target?.dataset?.autoSubmitCreateNextRowOnEnter === "true"
    if (createNextOnEnter) {
      submitter = form.querySelector('button[name="db_row[create_next_row]"]')
    }

    this.requestSubmitOnce(form, submitter)
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

  requestSubmitOnce(form, submitter = undefined) {
    if (!(form instanceof HTMLFormElement)) return
    if (form.dataset.autoSubmitPending === "true") return

    if (typeof form.checkValidity === "function" && !form.checkValidity()) {
      if (typeof form.reportValidity === "function") form.reportValidity()
      return
    }

    this.markSubmitting(form)
    if (submitter) {
      form.requestSubmit(submitter)
    } else {
      form.requestSubmit()
    }
  }

  markSubmitting(form = this.element) {
    if (!(form instanceof HTMLFormElement)) return

    form.dataset.autoSubmitPending = "true"
  }

  clearSubmitting(form = this.element) {
    if (!(form instanceof HTMLFormElement)) return

    delete form.dataset.autoSubmitPending
  }
}
