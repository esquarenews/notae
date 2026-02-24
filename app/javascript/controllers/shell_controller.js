import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.onKeydown = (event) => {
      if (event.key === "Escape") this.close()
    }
    window.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    window.removeEventListener("keydown", this.onKeydown)
    this.unlockBody()
  }

  toggle() {
    this.element.classList.contains("sidebar-open") ? this.close() : this.open()
  }

  open() {
    this.element.classList.add("sidebar-open")
    document.body.classList.add("notae-sidebar-open")
  }

  close() {
    this.element.classList.remove("sidebar-open")
    this.unlockBody()
  }

  unlockBody() {
    document.body.classList.remove("notae-sidebar-open")
  }
}
