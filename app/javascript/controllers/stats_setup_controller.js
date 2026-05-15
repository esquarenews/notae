import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form"]

  insertAfter(event) {
    if (event.isComposing || event.shiftKey || event.metaKey || event.ctrlKey || event.altKey) return

    const row = event.currentTarget.closest("[data-stats-setup-row-id]")
    const rowId = row?.dataset?.statsSetupRowId
    if (!rowId || !this.hasFormTarget) return

    event.preventDefault()
    this.submitWith("add_definition_after_id", rowId)
  }

  submitWith(name, value) {
    const hiddenInput = document.createElement("input")
    hiddenInput.type = "hidden"
    hiddenInput.name = name
    hiddenInput.value = value
    this.formTarget.appendChild(hiddenInput)
    this.formTarget.requestSubmit()
  }
}
