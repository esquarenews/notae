import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "viewPanel", "editPanel", "heading"]
  static values = { eventTitle: String }

  open(event) {
    this.openEdit(event)
  }

  openView(event) {
    if (event) {
      if (event.type === "keydown" && !["Enter", " "].includes(event.key)) return
      if (event.type === "keydown" && this.hasDialogTarget && this.dialogTarget.open) return
      if (this.interactiveTarget(event.target)) return
      if (event.type === "click" && this.hasDialogTarget && this.dialogTarget.contains(event.target)) return
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
    if (this.hasHeadingTarget) this.headingTarget.textContent = this.viewHeadingText()
  }

  showEditMode() {
    if (this.hasViewPanelTarget) this.viewPanelTarget.hidden = true
    if (this.hasEditPanelTarget) this.editPanelTarget.hidden = false
    if (this.hasHeadingTarget) this.headingTarget.textContent = this.editHeadingText()
  }

  interactiveTarget(target) {
    if (!(target instanceof Element)) return false

    return target.closest("a, button, input, textarea, select, label, summary, details, form") !== null
  }

  viewHeadingText() {
    if (this.hasEventTitleValue && this.eventTitleValue.trim().length > 0) {
      return this.eventTitleValue.trim()
    }

    return "Event details"
  }

  editHeadingText() {
    if (this.hasEventTitleValue && this.eventTitleValue.trim().length > 0) {
      return `Edit ${this.eventTitleValue.trim()}`
    }

    return "Edit event"
  }
}
