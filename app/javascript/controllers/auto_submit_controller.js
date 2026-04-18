import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static VIEW_STATE_KEY = "notae:auto-submit:view-state"
  static VIEW_STATE_TTL_MS = 10_000
  static values = {
    focusOnConnect: Boolean
  }

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
    this.handleSubmitEnd = () => {
      this.clearSubmitting()
      if (!this.nextRowFocusRequested) return

      this.nextRowFocusRequested = false
      this.focusNextCreatedRow()
    }
    this.clearSubmitting()

    if (this.element instanceof HTMLFormElement) {
      this.element.addEventListener("turbo:submit-start", this.handleSubmitStart)
      this.element.addEventListener("turbo:submit-end", this.handleSubmitEnd)
    }

    if (this.focusOnConnectValue) {
      this.focusPrimaryInput()
    }

    this.restoreViewState()
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

    this.captureViewState(event.target, form)
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

    this.nextRowFocusRequested = createNextOnEnter
    this.captureViewState(event.target, form)
    if (createNextOnEnter) {
      this.focusNextCreatedRow()
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

  captureViewState(target, form) {
    const focusSelector = this.focusSelectorFor(target)
    if (!focusSelector) return

    const payload = {
      path: window.location.pathname,
      search: window.location.search,
      focusSelector,
      scrollY: window.scrollY,
      capturedAt: Date.now(),
      formAction: form?.action || ""
    }

    window.sessionStorage.setItem(this.constructor.VIEW_STATE_KEY, JSON.stringify(payload))
  }

  restoreViewState() {
    const raw = window.sessionStorage.getItem(this.constructor.VIEW_STATE_KEY)
    if (!raw) return

    let payload
    try {
      payload = JSON.parse(raw)
    } catch (_error) {
      window.sessionStorage.removeItem(this.constructor.VIEW_STATE_KEY)
      return
    }

    const stale = !payload?.capturedAt || (Date.now() - payload.capturedAt) > this.constructor.VIEW_STATE_TTL_MS
    const wrongPath = payload?.path !== window.location.pathname || (payload?.search || "") !== window.location.search
    if (stale || wrongPath) {
      window.sessionStorage.removeItem(this.constructor.VIEW_STATE_KEY)
      return
    }

    const target = payload?.focusSelector ? document.querySelector(payload.focusSelector) : null
    if (!(target instanceof HTMLElement)) return

    window.sessionStorage.removeItem(this.constructor.VIEW_STATE_KEY)
    requestAnimationFrame(() => {
      window.scrollTo({ top: Number(payload.scrollY) || 0, behavior: "auto" })
      requestAnimationFrame(() => {
        target.focus({ preventScroll: true })
        if (typeof target.select === "function" && (target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement)) {
          target.select()
        }
      })
    })
  }

  focusSelectorFor(target) {
    if (!(target instanceof HTMLElement)) return ""

    if (target.id) return `#${CSS.escape(target.id)}`

    const name = target.getAttribute("name")?.trim()
    if (name) return `[name="${this.escapeAttribute(name)}"]`

    return ""
  }

  escapeAttribute(value) {
    return value.replace(/\\/g, "\\\\").replace(/"/g, '\\"')
  }

  markSubmitting(form = this.element) {
    if (!(form instanceof HTMLFormElement)) return

    form.dataset.autoSubmitPending = "true"
  }

  clearSubmitting(form = this.element) {
    if (!(form instanceof HTMLFormElement)) return

    delete form.dataset.autoSubmitPending
  }

  focusPrimaryInput() {
    const input = this.element?.querySelector?.('input[type="text"], input:not([type]), textarea')
    if (!(input instanceof HTMLElement)) return

    requestAnimationFrame(() => {
      input.focus({ preventScroll: true })
      if (typeof input.select === "function") {
        input.select()
      }
    })
  }

  focusNextCreatedRow(attempt = 0) {
    setTimeout(() => {
      const pendingForm = Array.from(document.querySelectorAll('form[data-auto-submit-focus-on-connect-value="true"]'))
        .reverse()
        .find((form) => form.dataset.autoSubmitPending !== "true")
      const input = pendingForm?.querySelector?.('input[type="text"], input:not([type]), textarea')
      if (!(input instanceof HTMLElement)) {
        if (attempt < 20) {
          this.focusNextCreatedRow(attempt + 1)
        }
        return
      }

      if (document.activeElement !== input) {
        input.focus({ preventScroll: true })
        if (typeof input.select === "function") {
          input.select()
        }
      }

      if (attempt < 20) {
        this.focusNextCreatedRow(attempt + 1)
      }
    }, attempt === 0 ? 0 : 75)
  }
}
