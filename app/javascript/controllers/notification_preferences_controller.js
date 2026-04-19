import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["masterToggle", "itemToggle"]

  connect() {
    this.syncMaster()
  }

  toggleAll() {
    if (!this.hasMasterToggleTarget) return

    const enabled = this.masterToggleTarget.checked
    this.itemToggleTargets.forEach((toggle) => {
      toggle.checked = enabled
    })
  }

  syncMaster() {
    if (!this.hasMasterToggleTarget) return

    this.masterToggleTarget.checked =
      this.itemToggleTargets.length > 0 && this.itemToggleTargets.every((toggle) => toggle.checked)
  }
}
