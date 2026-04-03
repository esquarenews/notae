import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "input"]

  choose(event) {
    event.preventDefault()

    const iconValue = event.currentTarget.dataset.iconValue
    if (!iconValue || !this.hasFormTarget || !this.hasInputTarget) return

    this.inputTarget.value = iconValue
    this.formTarget.requestSubmit()
  }
}
