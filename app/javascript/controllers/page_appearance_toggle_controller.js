import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    class: String
  }

  submit(event) {
    event.preventDefault()

    const field = this.toggleField()
    const button = this.submitButton()
    const switchElement = this.switchElement()
    const layout = this.pageLayout()
    if (!field || !button || !layout || !this.hasClassValue) {
      this.element.submit()
      return
    }

    const previousActive = layout.classList.contains(this.classValue)
    const requestedActive = field.value === "true"
    const formData = new FormData(this.element)
    this.applyState({ active: requestedActive, layout, switchElement, field })
    this.markBusy(button, true)

    this.persist(formData)
      .then((payload) => {
        const confirmedActive = this.confirmedActiveFromPayload(payload, requestedActive)
        this.applyState({ active: confirmedActive, layout, switchElement, field })
      })
      .catch(() => {
        this.applyState({ active: previousActive, layout, switchElement, field })
        button.classList.add("is-error")
        window.setTimeout(() => button.classList.remove("is-error"), 1800)
      })
      .finally(() => {
        this.markBusy(button, false)
      })
  }

  persist(formData) {
    return fetch(this.element.action, {
      method: this.element.method.toUpperCase(),
      body: formData,
      credentials: "same-origin",
      headers: {
        "Accept": "application/json",
        "X-Requested-With": "XMLHttpRequest",
        "X-CSRF-Token": this.csrfToken()
      }
    }).then((response) => {
      if (!response.ok) throw new Error(`Page appearance update failed (${response.status})`)
      return response.json()
    })
  }

  confirmedActiveFromPayload(payload, fallback) {
    if (this.classValue === "is-full-width") return Boolean(payload.full_width)
    if (this.classValue === "is-small-text") return Boolean(payload.small_text)
    if (this.classValue === "is-reader-mode") return Boolean(payload.remove_blocks)

    return fallback
  }

  applyState({ active, layout, switchElement, field }) {
    layout.classList.toggle(this.classValue, active)
    switchElement?.classList.toggle("is-on", active)
    field.value = (!active).toString()
  }

  markBusy(button, busy) {
    button.disabled = busy
    button.classList.toggle("is-working", busy)
    if (busy) {
      button.setAttribute("aria-busy", "true")
    } else {
      button.removeAttribute("aria-busy")
    }
  }

  toggleField() {
    return this.element.querySelector('input[name^="page["][type="hidden"]:not([name="authenticity_token"])')
  }

  submitButton() {
    return this.element.querySelector('button[type="submit"]')
  }

  switchElement() {
    return this.element.querySelector(".notae-actions-switch")
  }

  pageLayout() {
    return document.querySelector(".notae-doc-layout")
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }
}
