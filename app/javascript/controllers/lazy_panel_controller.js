import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container"]
  static values = {
    url: String,
    loaded: Boolean,
    loadingText: { type: String, default: "Loading…" },
    errorText: { type: String, default: "Could not load this panel." },
    focusSelector: String
  }

  connect() {
    this.pendingRequest = null
    this.onToggle = () => this.handleToggle()
    this.element.addEventListener("toggle", this.onToggle)

    if (this.element.open) {
      this.ensureLoaded()
      return
    }

    this.clearStatus()
  }

  disconnect() {
    this.element.removeEventListener("toggle", this.onToggle)
  }

  async handleToggle() {
    if (!this.element.open) return

    await this.ensureLoaded()
    this.focusTarget()
  }

  async ensureLoaded() {
    if (!this.hasContainerTarget || this.loadedValue) return true
    if (!this.hasUrlValue || this.urlValue.length === 0) return false
    if (this.pendingRequest) return this.pendingRequest

    this.renderStatus("loading")

    this.pendingRequest = fetch(this.urlValue, {
      credentials: "same-origin",
      headers: {
        Accept: "text/html",
        "X-Requested-With": "XMLHttpRequest"
      }
    })
      .then(async (response) => {
        if (!response.ok) throw new Error(`Failed to load panel: ${response.status}`)

        const html = await response.text()
        this.containerTarget.innerHTML = html
        this.loadedValue = true
        this.dispatch("loaded")
        return true
      })
      .catch(() => {
        this.renderStatus("error")
        this.dispatch("error")
        return false
      })
      .finally(() => {
        this.pendingRequest = null
      })

    return this.pendingRequest
  }

  focusTarget() {
    if (!this.hasFocusSelectorValue || !this.element.open) return

    const target = this.element.querySelector(this.focusSelectorValue)
    if (target && typeof target.focus === "function") {
      target.focus({ preventScroll: true })
    }
  }

  clearStatus() {
    if (!this.hasContainerTarget || this.loadedValue) return

    this.containerTarget.innerHTML = ""
    this.containerTarget.removeAttribute("data-lazy-panel-state")
  }

  renderStatus(state) {
    if (!this.hasContainerTarget || this.loadedValue) return

    const text = state === "error" ? this.errorTextValue : this.loadingTextValue
    const spinner = state === "loading" ? '<span class="notae-lazy-panel-spinner" aria-hidden="true"></span>' : ""
    this.containerTarget.dataset.lazyPanelState = state
    this.containerTarget.innerHTML = `
      <div class="notae-lazy-panel-status is-${state}" role="status" aria-live="polite">
        ${spinner}
        <span>${text}</span>
      </div>
    `
  }
}
