import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog"]

  open(event) {
    event.preventDefault()
    if (!this.hasDialogTarget) return

    this.dialogTarget.showModal()
  }

  close(event) {
    event.preventDefault()
    if (!this.hasDialogTarget) return

    this.dialogTarget.close()
  }

  backdropClose(event) {
    if (!this.hasDialogTarget) return
    if (event.target !== this.dialogTarget) return

    this.dialogTarget.close()
  }
}
