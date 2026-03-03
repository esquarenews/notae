import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status"]
  static values = {
    defaultHref: String
  }

  connect() {
    this.originalHref = this.currentIconHref() || this.defaultHrefValue || "/icon.svg"
  }

  preview(event) {
    const url = event.params.url
    const name = event.params.name
    if (!url) return

    this.applyIcon(url)
    this.updateStatus(`Previewing: ${name || url}`)
  }

  restore() {
    this.applyIcon(this.originalHref)
    this.updateStatus("Previewing: Current default")
  }

  currentIconHref() {
    const svgLink = document.querySelector("link[rel='icon'][type='image/svg+xml']")
    if (svgLink?.getAttribute("href")) return svgLink.getAttribute("href")
    const genericLink = document.querySelector("link[rel='icon']")
    return genericLink?.getAttribute("href") || null
  }

  applyIcon(url) {
    const links = Array.from(document.querySelectorAll("link[rel~='icon']"))
    if (links.length === 0) {
      const fallback = document.createElement("link")
      fallback.setAttribute("rel", "icon")
      fallback.setAttribute("href", url)
      document.head.appendChild(fallback)
      return
    }

    links.forEach((link) => {
      link.setAttribute("href", url)
      if (url.endsWith(".svg")) {
        link.setAttribute("type", "image/svg+xml")
      }
    })
  }

  updateStatus(text) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
  }
}
