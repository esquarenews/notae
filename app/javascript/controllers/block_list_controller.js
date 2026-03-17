import { Controller } from "@hotwired/stimulus"

const DRAG_MOVE_THRESHOLD_PX = 2
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
  }

  disconnect() {
    this.clearDropState()
  }

  handleDragStart(event) {
    if (!event.dataTransfer) return
    const sourceItem = event.currentTarget.closest("[data-block-id]")
    if (!sourceItem) return

    this.draggedItem = sourceItem
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

    const beforeRects = this.captureRects()
    const insertBefore = this.shouldInsertBefore(event, targetItem)

    if (insertBefore) {
      if (targetItem.previousElementSibling === this.draggedItem) {
        this.setDropCandidate(targetItem, "before")
        return
      }

      this.element.insertBefore(this.draggedItem, targetItem)
      this.animateFromRects(beforeRects)
      this.setDropCandidate(targetItem, "before")
      return
    }

    if (targetItem.nextElementSibling === this.draggedItem) {
      this.setDropCandidate(targetItem, "after")
      return
    }

    this.element.insertBefore(this.draggedItem, targetItem.nextElementSibling)
    this.animateFromRects(beforeRects)
    this.setDropCandidate(targetItem, "after")
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
    const siblings = this.directSiblingItems()
    const targetIndex = siblings.findIndex((item) => item.dataset.blockId === draggedId)

    if (!draggedId || targetIndex < 0) {
      this.handleDragEnd()
      return
    }

    const url = `/w/${this.workspaceSlugValue}/pages/${this.pageIdValue}/blocks/${draggedId}/reorder`
    const payload = {
      target_parent_id: this.parentIdValue || null,
      target_index: targetIndex
    }
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    try {
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
      }
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

  captureRects() {
    const rects = new Map()
    this.directSiblingItems().forEach((item) => {
      rects.set(item.dataset.blockId, item.getBoundingClientRect())
    })
    return rects
  }

  animateFromRects(beforeRects) {
    this.directSiblingItems().forEach((item) => {
      const before = beforeRects.get(item.dataset.blockId)
      if (!before) return

      const after = item.getBoundingClientRect()
      const deltaY = before.top - after.top
      if (Math.abs(deltaY) < DRAG_MOVE_THRESHOLD_PX) return

      item.style.transition = "none"
      item.style.transform = `translateY(${deltaY}px)`

      requestAnimationFrame(() => {
        item.style.transition = "transform 170ms cubic-bezier(0.2, 0.8, 0.2, 1)"
        item.style.transform = ""
      })
    })
  }

  setDropCandidate(targetItem, position) {
    if (this.activeDropItem && this.activeDropItem !== targetItem) {
      this.activeDropItem.classList.remove("is-drop-candidate", "is-drop-candidate-before", "is-drop-candidate-after")
    }

    targetItem.classList.add("is-drop-candidate")
    targetItem.classList.toggle("is-drop-candidate-before", position === "before")
    targetItem.classList.toggle("is-drop-candidate-after", position === "after")
    this.activeDropItem = targetItem
  }

  clearDropState() {
    this.element.classList.remove("is-drag-active")

    if (this.activeDropItem) {
      this.activeDropItem.classList.remove("is-drop-candidate", "is-drop-candidate-before", "is-drop-candidate-after")
      this.activeDropItem = null
    }

    this.directSiblingItems().forEach((item) => {
      item.classList.remove("is-drop-candidate", "is-drop-candidate-before", "is-drop-candidate-after")
    })
  }
}
