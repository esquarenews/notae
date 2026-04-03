import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "insertAfterInput", "fileInput"]
  static values = { defaultBlockId: String }

  open(event) {
    if (event) event.preventDefault()
    this.closeMenu(event)
    this.prepareTarget()
    if (!this.hasDialogTarget) return

    this.dialogTarget.showModal()
    if (this.hasFileInputTarget) this.fileInputTarget.focus()
  }

  close(event) {
    if (event) event.preventDefault()
    if (!this.hasDialogTarget || !this.dialogTarget.open) return

    this.dialogTarget.close()
  }

  backdropClose(event) {
    if (!this.hasDialogTarget) return
    if (event.target !== this.dialogTarget) return

    this.close()
  }

  prepareSubmit() {
    this.prepareTarget()
  }

  prepareTarget() {
    if (!this.hasInsertAfterInputTarget) return

    this.insertAfterInputTarget.value = this.resolveBlockId()
  }

  resolveBlockId() {
    const selectedBlockId = window.notaeAiInsertionPoint?.blockId
    if (selectedBlockId && this.blockExists(selectedBlockId)) return String(selectedBlockId)
    if (this.defaultBlockIdValue && this.blockExists(this.defaultBlockIdValue)) return this.defaultBlockIdValue

    return ""
  }

  blockExists(blockId) {
    if (!blockId) return false

    const block = document.getElementById(`block_${blockId}`)
    return !!block
  }

  closeMenu(event) {
    const menu = event?.currentTarget?.closest("details")
    if (menu?.open) menu.open = false
  }
}
