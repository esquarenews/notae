import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item"]
  static values = {
    workspaceSlug: String,
    pageId: String,
    parentId: String
  }

  connect() {
    this.itemTargets.forEach((item) => {
      item.addEventListener("dragstart", this.handleDragStart)
      item.addEventListener("dragover", this.handleDragOver)
      item.addEventListener("drop", this.handleDrop)
    })
  }

  disconnect() {
    this.itemTargets.forEach((item) => {
      item.removeEventListener("dragstart", this.handleDragStart)
      item.removeEventListener("dragover", this.handleDragOver)
      item.removeEventListener("drop", this.handleDrop)
    })
  }

  handleDragStart = (event) => {
    event.dataTransfer.setData("text/plain", event.currentTarget.dataset.blockId)
  }

  handleDragOver = (event) => {
    event.preventDefault()
  }

  handleDrop = async (event) => {
    event.preventDefault()

    const draggedId = event.dataTransfer.getData("text/plain")
    const targetItem = event.currentTarget
    const siblings = this.itemTargets
    const targetIndex = siblings.findIndex((item) => item.dataset.blockId === targetItem.dataset.blockId)

    if (!draggedId || targetIndex < 0) return

    const url = `/w/${this.workspaceSlugValue}/pages/${this.pageIdValue}/blocks/${draggedId}/reorder`
    const payload = {
      target_parent_id: this.parentIdValue || null,
      target_index: targetIndex
    }

    await fetch(url, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
      },
      body: JSON.stringify(payload)
    })

    window.location.reload()
  }
}
