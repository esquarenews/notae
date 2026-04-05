import { Controller } from "@hotwired/stimulus"

const BLOCK_DRAG_MIME = "application/x-notae-block-id"

export default class extends Controller {
  static targets = ["item"]
  static values = {
    workspaceSlug: String,
    pageId: String,
    parentId: String
  }

  connect() {
    this.draggedItem = null
    this.activeDropItem = null
    this.activeDropPosition = null
    this.pendingDragFlush = null
  }

  disconnect() {
    this.pendingDragFlush = null
    this.clearDropState()
  }

  prepareDragStart(event) {
    const sourceItem = event.currentTarget.closest("[data-block-id]")
    if (!sourceItem) return

    this.pendingDragFlush = this.requestBlockFlush(sourceItem)
  }

  handleDragStart(event) {
    if (!event.dataTransfer) return
    const sourceItem = event.currentTarget.closest("[data-block-id]")
    if (!sourceItem) return

    this.draggedItem = sourceItem
    if (!this.pendingDragFlush) {
      this.pendingDragFlush = this.requestBlockFlush(sourceItem)
    }
    this.element.classList.add("is-drag-active")
    this.draggedItem.classList.add("is-dragging")
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData(BLOCK_DRAG_MIME, this.draggedItem.dataset.blockId)
  }

  handleDragOver(event) {
    if (!event.dataTransfer || !this.draggedItem) return

    event.preventDefault()
    event.dataTransfer.dropEffect = "move"

    const targetItem = event.currentTarget
    if (!targetItem || targetItem === this.draggedItem) return

    this.setDropCandidate(targetItem, this.shouldInsertBefore(event, targetItem) ? "before" : "after")
  }

  handleDragEnter(event) {
    if (!this.draggedItem) return

    const targetItem = event.currentTarget
    if (!targetItem || targetItem === this.draggedItem) return

    targetItem.classList.add("is-drop-candidate")
  }

  handleDragLeave(event) {
    const targetItem = event.currentTarget
    if (!targetItem || targetItem === this.activeDropItem) return

    targetItem.classList.remove("is-drop-candidate")
  }

  async handleDrop(event) {
    if (!event.dataTransfer) return

    event.preventDefault()
    event.stopPropagation()

    const draggedId = event.dataTransfer.getData(BLOCK_DRAG_MIME) || this.draggedItem?.dataset.blockId
    const placement = this.resolveDropPlacement(event, draggedId)

    if (!draggedId || !placement) {
      this.handleDragEnd()
      return
    }

    const url = `/w/${this.workspaceSlugValue}/pages/${this.pageIdValue}/blocks/${draggedId}/reorder`
    const payload = {
      target_parent_id: this.parentIdValue || null,
      target_index: placement.targetIndex
    }
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    try {
      const saved = await this.flushDraggedBlockSave()
      if (!saved) {
        window.location.reload()
        return
      }

      const response = await fetch(url, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {})
        },
        credentials: "same-origin",
        body: JSON.stringify(payload)
      })

      if (!response.ok) {
        window.location.reload()
        return
      }

      this.applyDropPlacement(placement)
    } catch (_error) {
      window.location.reload()
    } finally {
      this.handleDragEnd()
    }
  }

  handleDragEnd() {
    if (this.draggedItem) {
      this.draggedItem.classList.remove("is-dragging")
      this.draggedItem = null
    }

    this.pendingDragFlush = null
    this.clearDropState()
  }

  directSiblingItems() {
    return Array.from(this.element.children).filter((element) => element.dataset.blockId)
  }

  shouldInsertBefore(event, targetItem) {
    const rect = targetItem.getBoundingClientRect()
    const midpoint = rect.top + rect.height / 2

    return event.clientY < midpoint
  }

  requestBlockFlush(item) {
    const blockId = item?.dataset.blockId
    if (!blockId) return Promise.resolve(true)

    const detail = { blockId }
    window.dispatchEvent(new CustomEvent("notae:block-flush-save", { detail }))
    return Promise.resolve(detail.promise || true)
  }

  flushDraggedBlockSave() {
    if (this.pendingDragFlush) return this.pendingDragFlush
    if (!this.draggedItem) return Promise.resolve(true)

    this.pendingDragFlush = this.requestBlockFlush(this.draggedItem)
    return this.pendingDragFlush
  }

  resolveDropPlacement(event, draggedId) {
    const dropItem = this.activeDropItem || event.currentTarget
    if (!dropItem || dropItem === this.draggedItem) return null

    const dropPosition = this.activeDropPosition || (this.shouldInsertBefore(event, dropItem) ? "before" : "after")
    const siblings = this.directSiblingItems().filter((item) => item.dataset.blockId !== draggedId)
    const targetSiblingIndex = siblings.findIndex((item) => item === dropItem)
    if (targetSiblingIndex < 0) return null

    return {
      dropItem,
      dropPosition,
      targetIndex: targetSiblingIndex + (dropPosition === "after" ? 1 : 0)
    }
  }

  applyDropPlacement(placement) {
    if (!this.draggedItem || !placement?.dropItem || placement.dropItem === this.draggedItem) return

    if (placement.dropPosition === "before") {
      this.element.insertBefore(this.draggedItem, placement.dropItem)
      return
    }

    this.element.insertBefore(this.draggedItem, placement.dropItem.nextElementSibling)
  }

  setDropCandidate(targetItem, position) {
    if (this.activeDropItem && this.activeDropItem !== targetItem) {
      this.activeDropItem.classList.remove("is-drop-candidate", "is-drop-candidate-before", "is-drop-candidate-after")
    }

    targetItem.classList.add("is-drop-candidate")
    targetItem.classList.toggle("is-drop-candidate-before", position === "before")
    targetItem.classList.toggle("is-drop-candidate-after", position === "after")
    this.activeDropItem = targetItem
    this.activeDropPosition = position
  }

  clearDropState() {
    this.element.classList.remove("is-drag-active")

    if (this.activeDropItem) {
      this.activeDropItem.classList.remove("is-drop-candidate", "is-drop-candidate-before", "is-drop-candidate-after")
      this.activeDropItem = null
    }

    this.activeDropPosition = null

    this.directSiblingItems().forEach((item) => {
      item.classList.remove("is-drop-candidate", "is-drop-candidate-before", "is-drop-candidate-after")
    })
  }
}
