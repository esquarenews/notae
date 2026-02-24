import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    workspaceSlug: String,
    databaseId: String,
    viewId: String,
    propertyId: String,
    month: String
  }

  dragstart(event) {
    const rowId = event.currentTarget.dataset.databaseDragRowId
    if (!rowId) return

    event.dataTransfer.setData("text/plain", rowId)
  }

  dragover(event) {
    event.preventDefault()
  }

  async drop(event) {
    event.preventDefault()

    const rowId = event.dataTransfer.getData("text/plain")
    const target = event.currentTarget
    if (!rowId || !target) return

    const targetValue = target.dataset.databaseDragTargetValue || ""
    const targetIndex = target.querySelectorAll("[data-database-drag-row-id]").length
    const payload = {
      property_id: this.propertyIdValue || null,
      target_value: targetValue,
      target_index: targetIndex,
      view_id: this.viewIdValue || null,
      month: this.monthValue || null
    }

    const response = await fetch(
      `/w/${this.workspaceSlugValue}/databases/${this.databaseIdValue}/db_rows/${rowId}/move`,
      {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
        },
        body: JSON.stringify(payload)
      }
    )

    if (response.ok) {
      window.location.reload()
    }
  }
}
