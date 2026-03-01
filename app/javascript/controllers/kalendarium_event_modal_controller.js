import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "viewPanel", "editPanel", "heading"]

  open(event) {
    this.openEdit(event)
  }

  openView(event) {
    if (event) {
      if (event.type === "keydown" && !["Enter", " "].includes(event.key)) return
      if (event.type === "click" && this.hasDialogTarget && this.dialogTarget.contains(event.target)) return
      if (event.type === "click" && this.interactiveTarget(event.target)) return
      event.preventDefault()
    }

    if (!this.hasDialogTarget) return

    this.showViewMode()
    this.dialogTarget.showModal()
  }

  openEdit(event) {
    if (event) event.preventDefault()
    if (!this.hasDialogTarget) return

    this.showEditMode()
    this.dialogTarget.showModal()
  }

  close(event) {
    if (event) event.preventDefault()
    if (!this.hasDialogTarget) return

    this.dialogTarget.close()
  }

  backdropClose(event) {
    if (!this.hasDialogTarget) return
    if (event.target !== this.dialogTarget) return

    this.dialogTarget.close()
  }

  showViewMode() {
    if (this.hasViewPanelTarget) this.viewPanelTarget.hidden = false
    if (this.hasEditPanelTarget) this.editPanelTarget.hidden = true
    if (this.hasHeadingTarget) this.headingTarget.textContent = "Event details"
  }

  showEditMode() {
    if (this.hasViewPanelTarget) this.viewPanelTarget.hidden = true
    if (this.hasEditPanelTarget) this.editPanelTarget.hidden = false
    if (this.hasHeadingTarget) this.headingTarget.textContent = "Edit event"
  }

  interactiveTarget(target) {
    if (!(target instanceof Element)) return false

    return target.closest("a, button, input, textarea, select, label, summary, details, form") !== null
  }
}
