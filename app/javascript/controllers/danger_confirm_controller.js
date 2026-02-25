import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "nameInput", "confirmButton"]
  static values = { workspaceName: String }

  connect() {
    this.sync()
  }

  open(event) {
    event.preventDefault()
    if (!this.hasDialogTarget) return

    this.dialogTarget.showModal()
    this.resetInput()
  }

  close(event) {
    if (event) event.preventDefault()
    if (!this.hasDialogTarget) return

    this.dialogTarget.close()
  }

  backdropClose(event) {
    if (event.target === this.dialogTarget) {
      this.close()
    }
  }

  sync() {
    if (!this.hasNameInputTarget || !this.hasConfirmButtonTarget) return

    const matches = this.nameInputTarget.value.trim() === this.workspaceNameValue
    this.confirmButtonTarget.disabled = !matches
  }

  resetInput() {
    if (!this.hasNameInputTarget) return

    this.nameInputTarget.value = ""
    this.sync()
    this.nameInputTarget.focus()
  }
}
