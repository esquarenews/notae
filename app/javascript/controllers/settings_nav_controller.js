import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.viewportQuery = window.matchMedia("(max-width: 880px)")
    this.onViewportChange = () => this.syncState()
    this.wasMobile = this.viewportQuery.matches

    if (typeof this.viewportQuery.addEventListener === "function") {
      this.viewportQuery.addEventListener("change", this.onViewportChange)
    } else {
      this.viewportQuery.addListener(this.onViewportChange)
    }

    this.syncState()
  }

  disconnect() {
    if (!this.viewportQuery) return

    if (typeof this.viewportQuery.removeEventListener === "function") {
      this.viewportQuery.removeEventListener("change", this.onViewportChange)
    } else {
      this.viewportQuery.removeListener(this.onViewportChange)
    }
  }

  syncState() {
    const mobile = this.viewportQuery.matches

    if (mobile) {
      if (this.wasMobile === false) {
        this.element.removeAttribute("open")
      }
    } else {
      this.element.setAttribute("open", "open")
    }

    this.wasMobile = mobile
  }
}
