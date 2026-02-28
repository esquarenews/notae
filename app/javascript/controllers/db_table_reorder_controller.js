import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row"]
  static values = {
    workspaceSlug: String,
    databaseId: String,
    viewId: String,
    month: String
  }

  connect() {
    this.draggedRowId = null
    this.dropPlacement = "after"
    this.activeDropRow = null
  }

  dragstart(event) {
    const handle = event.currentTarget
    const rowId = handle.dataset.dbTableReorderRowId
    if (!rowId || !event.dataTransfer) return

    this.draggedRowId = rowId
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", rowId)
    handle.classList.add("is-dragging")
  }

  dragend(event) {
    event.currentTarget.classList.remove("is-dragging")
    this.clearDropIndicator()
    this.draggedRowId = null
  }

  dragover(event) {
    const targetRow = event.target.closest("[data-db-table-reorder-row-id]")
    if (!targetRow) return

    const targetRowId = targetRow.dataset.dbTableReorderRowId
    if (!targetRowId || targetRowId === this.draggedRowId) return

    event.preventDefault()
    event.dataTransfer.dropEffect = "move"

    const rowRect = targetRow.getBoundingClientRect()
    const placeBefore = event.clientY < rowRect.top + rowRect.height / 2
    this.setDropIndicator(targetRow, placeBefore ? "before" : "after")
  }

  dragleave(event) {
    const relatedTarget = event.relatedTarget
    if (!this.activeDropRow) return
    if (relatedTarget && this.activeDropRow.contains(relatedTarget)) return

    this.clearDropIndicator()
  }

  async drop(event) {
    event.preventDefault()

    const targetRow = event.target.closest("[data-db-table-reorder-row-id]")
    const rowId = this.draggedRowId || event.dataTransfer?.getData("text/plain")
    if (!targetRow || !rowId) {
      this.clearDropIndicator()
      return
    }

    const orderedRows = this.draggableRows
    const draggedIndex = orderedRows.findIndex((row) => row.dataset.dbTableReorderRowId === rowId)
    const targetIndexRaw = orderedRows.findIndex((row) => row.dataset.dbTableReorderRowId === targetRow.dataset.dbTableReorderRowId)

    if (draggedIndex < 0 || targetIndexRaw < 0) {
      this.clearDropIndicator()
      return
    }

    const insertionBase = targetIndexRaw + (this.dropPlacement === "after" ? 1 : 0)
    const targetIndex = draggedIndex < insertionBase ? insertionBase - 1 : insertionBase

    this.clearDropIndicator()
    if (targetIndex === draggedIndex) return

    await this.submitMove(rowId, targetIndex)
  }

  get draggableRows() {
    return this.rowTargets.filter((row) => {
      if (!row.dataset.dbTableReorderRowId) return false
      if (row.classList.contains("notae-db-grid-new-row")) return false
      if (row.classList.contains("notae-db-grid-add-row-control")) return false
      return true
    })
  }

  async submitMove(rowId, targetIndex) {
    const payload = {
      property_id: null,
      target_value: "",
      target_index: targetIndex,
      view_id: this.viewIdValue || null,
      month: this.monthValue || null,
      clear_sort: true
    }

    const response = await fetch(
      `/w/${this.workspaceSlugValue}/databases/${this.databaseIdValue}/db_rows/${rowId}/move`,
      {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
        },
        body: JSON.stringify(payload)
      }
    )

    if (!response.ok) return

    let redirectUrl = null
    try {
      const data = await response.json()
      redirectUrl = data.redirect_url
    } catch (_error) {
      redirectUrl = null
    }

    window.location.href = redirectUrl || this.manualOrderUrl()
  }

  manualOrderUrl() {
    const url = new URL(window.location.href)
    url.searchParams.delete("sort_property_id")
    url.searchParams.delete("sort_direction")
    return url.toString()
  }

  setDropIndicator(row, placement) {
    if (this.activeDropRow && this.activeDropRow !== row) {
      this.activeDropRow.classList.remove("is-drop-before", "is-drop-after")
    }

    this.activeDropRow = row
    this.dropPlacement = placement
    row.classList.toggle("is-drop-before", placement === "before")
    row.classList.toggle("is-drop-after", placement === "after")
  }

  clearDropIndicator() {
    if (!this.activeDropRow) return

    this.activeDropRow.classList.remove("is-drop-before", "is-drop-after")
    this.activeDropRow = null
  }
}
