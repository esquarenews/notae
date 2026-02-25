import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    openLinksInNewWindow: Boolean
  }

  connect() {
    this.clickHandler = (event) => this.handleDocumentClick(event)
    document.addEventListener("click", this.clickHandler, true)
  }

  disconnect() {
    document.removeEventListener("click", this.clickHandler, true)
  }

  handleDocumentClick(event) {
    if (!this.openLinksInNewWindowValue) return
    if (event.defaultPrevented) return
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

    const link = event.target.closest("a[href]")
    if (!link) return
    if (link.dataset.noNewWindow === "true") return
    if (link.target && link.target !== "_self") return

    const href = link.getAttribute("href")
    if (!href || href.startsWith("#")) return
    if (href.startsWith("mailto:") || href.startsWith("tel:") || href.startsWith("javascript:")) return

    const url = new URL(href, window.location.origin)
    if (url.origin === window.location.origin) return

    link.target = "_blank"
    link.rel = "noopener noreferrer"
  }
}
