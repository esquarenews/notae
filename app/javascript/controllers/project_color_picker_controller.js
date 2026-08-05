import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "swatch"]

  open(event) {
    if (!this.hasInputTarget || event.target === this.inputTarget) return

    event.preventDefault()

    if (typeof this.inputTarget.showPicker === "function") {
      this.inputTarget.showPicker()
    } else {
      this.inputTarget.click()
    }
  }

  save() {
    if (!this.hasInputTarget) return

    this.swatchTargets.forEach((swatch) => {
      swatch.style.setProperty("--kal-color", this.inputTarget.value)
    })
    this.element.requestSubmit()
  }
}
