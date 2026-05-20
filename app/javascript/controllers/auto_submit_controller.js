import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static VIEW_STATE_KEY = "notae:auto-submit:view-state"
  static VIEW_STATE_TTL_MS = 10_000
  static INPUT_DEBOUNCE_MS = 650

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
  static activeControllerCount = 0
  static pendingFocusSelector = ""
  static pendingFocusCapturedAt = 0
  static documentPointerDownHandler = null

  connect() {
    this.debounceTimers = new Map()
    this.handleSubmitStart = (event) => {
      const form = this.eventForm(event)
      this.markSubmitting(form)
    }
    this.handleSubmitEnd = (event) => {
      const form = this.eventForm(event)
      this.clearSubmitting(form)
      if (!this.nextRowFocusRequested) return

      this.nextRowFocusRequested = false
      this.focusNextCreatedRow()
    }
    this.clearSubmitting()

    this.element.addEventListener("turbo:submit-start", this.handleSubmitStart)
    this.element.addEventListener("turbo:submit-end", this.handleSubmitEnd)

    if (this.focusOnConnectValue || this.hasPendingConnectFocusTarget()) {
      this.focusPrimaryInput()
    }

    this.constructor.installDocumentPointerListener()
    this.restoreViewState()
  }

  disconnect() {
    this.clearDebounceTimers()
    this.constructor.removeDocumentPointerListener()
    this.element.removeEventListener("turbo:submit-start", this.handleSubmitStart)
    this.element.removeEventListener("turbo:submit-end", this.handleSubmitEnd)
  }

  static installDocumentPointerListener() {
    this.activeControllerCount += 1
    if (this.documentPointerDownHandler) return

    this.documentPointerDownHandler = (event) => this.capturePendingFocusTarget(event)
    document.addEventListener("pointerdown", this.documentPointerDownHandler, true)
  }

  static removeDocumentPointerListener() {
    this.activeControllerCount = Math.max(this.activeControllerCount - 1, 0)
    if (this.activeControllerCount > 0 || !this.documentPointerDownHandler) return

    document.removeEventListener("pointerdown", this.documentPointerDownHandler, true)
    this.documentPointerDownHandler = null
    this.clearPendingFocusTarget()
  }

  formFor(event) {
    return event.target?.form || event.target?.closest("form")
  }

  eventForm(event) {
    const target = event?.target
    if (target instanceof HTMLFormElement) return target

    return this.formFor(event)
  }

  submit(event) {
    this.clearDebounceTimerFor(event.target)
    this.applyTaskStatusVisualState(event.target)

    const form = this.formFor(event)
    if (!form) {
      this.submitDetachedInput(event.target)
      return
    }

    this.captureViewState(event.target, form)
    this.requestSubmitOnce(form)
  }

  submitDebounced(event) {
    const target = event.target
    if (!(target instanceof HTMLInputElement) && !(target instanceof HTMLTextAreaElement)) return

    const existingTimer = this.debounceTimers.get(target)
    if (existingTimer) window.clearTimeout(existingTimer)

    const timer = window.setTimeout(() => {
      this.debounceTimers.delete(target)
      this.submit({ target })
    }, this.constructor.INPUT_DEBOUNCE_MS)

    this.debounceTimers.set(target, timer)
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

    form.dataset.preserveScroll = "true"
    if (form.closest(".notae-settings-shell")) {
      form.dataset.turboStream = "true"
    }
    this.markSubmitting(form)
    if (submitter) {
      form.requestSubmit(submitter)
    } else {
      form.requestSubmit()
    }
  }

  async submitDetachedInput(target) {
    if (!(target instanceof HTMLInputElement) && !(target instanceof HTMLSelectElement) && !(target instanceof HTMLTextAreaElement)) return
    if (!target.dataset.autoSubmitUrl || !target.dataset.autoSubmitParamName) return
    if (target.dataset.autoSubmitPending === "true") return

    if (typeof target.checkValidity === "function" && !target.checkValidity()) {
      if (typeof target.reportValidity === "function") target.reportValidity()
      return
    }

    this.captureViewState(target, { action: target.dataset.autoSubmitUrl })
    delete target.dataset.autoSubmitFailed
    target.dataset.autoSubmitPending = "true"

    const body = new FormData()
    body.append(target.dataset.autoSubmitParamName, this.detachedInputValue(target))

    try {
      const response = await fetch(target.dataset.autoSubmitUrl, {
        method: (target.dataset.autoSubmitMethod || "patch").toUpperCase(),
        credentials: "same-origin",
        headers: this.detachedInputHeaders(),
        body
      })
      const responseBody = await response.text()
      const contentType = response.headers.get("content-type") || ""

      if (contentType.includes("turbo-stream") && window.Turbo?.renderStreamMessage) {
        window.Turbo.renderStreamMessage(responseBody)
      } else if (response.redirected) {
        window.location.assign(response.url)
      } else if (!response.ok) {
        throw new Error(`Detached autosubmit failed: ${response.status}`)
      }
    } catch (_error) {
      target.dataset.autoSubmitFailed = "true"
    } finally {
      delete target.dataset.autoSubmitPending
    }
  }

  detachedInputValue(target) {
    if (target instanceof HTMLInputElement && target.type === "checkbox") {
      return target.checked ? (target.value || "true") : "false"
    }

    return target.value
  }

  detachedInputHeaders() {
    const headers = {
      Accept: "text/vnd.turbo-stream.html, text/html, application/xhtml+xml",
      "X-Requested-With": "XMLHttpRequest"
    }
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    if (csrfToken) headers["X-CSRF-Token"] = csrfToken

    return headers
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
      formAction: form?.action || "",
      pendingFocusSelector: this.constructor.pendingFocusSelector,
      pendingFocusCapturedAt: this.constructor.pendingFocusCapturedAt
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

    const selector = this.preferredFocusSelector(payload)
    const target = selector ? document.querySelector(selector) : null
    if (!(target instanceof HTMLElement)) return

    window.sessionStorage.removeItem(this.constructor.VIEW_STATE_KEY)
    this.clearPendingFocusTarget()
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

  preferredFocusSelector(payload) {
    const pendingCapturedAt = Number(payload?.pendingFocusCapturedAt || 0)
    const submittedAt = Number(payload?.capturedAt || 0)

    if (payload?.pendingFocusSelector && pendingCapturedAt >= submittedAt) {
      return payload.pendingFocusSelector
    }

    return payload?.focusSelector || ""
  }

  focusSelectorFor(target) {
    return this.constructor.focusSelectorFor(target)
  }

  static focusSelectorFor(target) {
    if (!(target instanceof HTMLElement)) return ""

    if (target.id) return `#${CSS.escape(target.id)}`

    const name = target.getAttribute("name")?.trim()
    if (name) return `[name="${this.escapeAttribute(name)}"]`

    return ""
  }

  static escapeAttribute(value) {
    return value.replace(/\\/g, "\\\\").replace(/"/g, '\\"')
  }

  escapeAttribute(value) {
    return this.constructor.escapeAttribute(value)
  }

  static capturePendingFocusTarget(event) {
    const target = event?.target
    if (!(target instanceof HTMLElement)) return

    const focusTarget = target.closest("input, textarea, select, [contenteditable='true']")
    if (!(focusTarget instanceof HTMLElement)) return

    this.pendingFocusSelector = this.focusSelectorFor(focusTarget)
    this.pendingFocusCapturedAt = Date.now()
  }

  static clearPendingFocusTarget() {
    this.pendingFocusSelector = ""
    this.pendingFocusCapturedAt = 0
  }

  clearPendingFocusTarget() {
    this.constructor.clearPendingFocusTarget()
  }

  markSubmitting(form = this.element) {
    if (!(form instanceof HTMLFormElement)) return

    form.dataset.autoSubmitPending = "true"
  }

  clearSubmitting(form = this.element) {
    if (!(form instanceof HTMLFormElement)) return

    delete form.dataset.autoSubmitPending
  }

  hasPendingConnectFocusTarget() {
    return Boolean(this.element?.querySelector?.('form[data-auto-submit-focus-on-connect-value="true"]'))
  }

  focusPrimaryInput() {
    const focusRoot = this.element?.querySelector?.('form[data-auto-submit-focus-on-connect-value="true"]') || this.element
    const input = focusRoot?.querySelector?.('input[type="text"], input:not([type]), textarea')
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

  clearDebounceTimers() {
    if (!this.debounceTimers) return

    this.debounceTimers.forEach((timer) => window.clearTimeout(timer))
    this.debounceTimers.clear()
  }

  clearDebounceTimerFor(target) {
    if (!this.debounceTimers || !target) return

    const timer = this.debounceTimers.get(target)
    if (!timer) return

    window.clearTimeout(timer)
    this.debounceTimers.delete(target)
  }
}
