import { Controller } from "@hotwired/stimulus"

const POINTER_DRAG_THRESHOLD_PX = 5
const EDGE_SCROLL_ZONE_PX = 64
const EDGE_SCROLL_STEP_PX = 14

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
    this.pointerDragState = null
  }

  disconnect() {
    this.pointerDragState = null
    this.pendingDragFlush = null
    this.draggedItem = null
    this.clearDropState()
  }

  prepareDragStart(event) {
    if (!event.isPrimary || event.button !== 0) return

    const sourceItem = event.currentTarget.closest("[data-block-id]")
    if (!sourceItem) return

    event.preventDefault()
    this.pendingDragFlush = this.requestBlockFlush(sourceItem)
    this.pointerDragState = {
      pointerId: event.pointerId,
      originX: event.clientX,
      originY: event.clientY,
      handle: event.currentTarget,
      sourceItem
    }

    event.currentTarget.setPointerCapture(event.pointerId)
  }

  handlePointerMove(event) {
    const state = this.pointerDragState
    if (!state || event.pointerId !== state.pointerId) return

    const distance = Math.hypot(event.clientX - state.originX, event.clientY - state.originY)
    if (!this.draggedItem && distance < POINTER_DRAG_THRESHOLD_PX) return

    event.preventDefault()
    this.beginPointerDrag(state.sourceItem)
    this.autoScrollNearEdge(event.clientY)

    const targetItem = this.directSiblingItemAtPoint(event.clientX, event.clientY)
    if (!targetItem || targetItem === this.draggedItem) {
      this.clearActiveDropCandidate()
      return
    }

    this.setDropCandidate(targetItem, this.shouldInsertBefore(event, targetItem) ? "before" : "after")
  }

  handlePointerEnd(event) {
    const state = this.pointerDragState
    if (!state || event.pointerId !== state.pointerId) return

    event.preventDefault()
    this.releasePointerCapture(state)
    this.pointerDragState = null

    const draggedId = this.draggedItem?.dataset.blockId
    const placement = this.resolveDropPlacement(event, draggedId)
    if (!draggedId || !placement) {
      this.handleDragEnd()
      return
    }

    this.persistDrop(draggedId, placement)
  }

  handlePointerCancel(event) {
    const state = this.pointerDragState
    if (!state || event.pointerId !== state.pointerId) return

    this.releasePointerCapture(state)
    this.pointerDragState = null
    this.handleDragEnd()
  }

  beginPointerDrag(sourceItem) {
    if (this.draggedItem) return

    this.draggedItem = sourceItem
    this.element.classList.add("is-drag-active")
    this.draggedItem.classList.add("is-dragging")
  }

  async persistDrop(draggedId, placement) {
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
    this.pointerDragState = null
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
    const dropItem = this.activeDropItem || this.directSiblingItemAtPoint(event.clientX, event.clientY)
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

  clearActiveDropCandidate() {
    if (!this.activeDropItem) return

    this.activeDropItem.classList.remove("is-drop-candidate", "is-drop-candidate-before", "is-drop-candidate-after")
    this.activeDropItem = null
    this.activeDropPosition = null
  }

  directSiblingItemAtPoint(clientX, clientY) {
    const pointedElement = document.elementFromPoint(clientX, clientY)
    let candidate = pointedElement?.closest?.("[data-block-id]")

    while (candidate && candidate.parentElement !== this.element) {
      candidate = candidate.parentElement?.closest?.("[data-block-id]")
    }

    return candidate?.parentElement === this.element ? candidate : null
  }

  autoScrollNearEdge(clientY) {
    const scrollContainer = this.element.closest(".notae-content-scroll")
    if (!scrollContainer) return

    const rect = scrollContainer.getBoundingClientRect()
    if (clientY < rect.top + EDGE_SCROLL_ZONE_PX) {
      scrollContainer.scrollBy({ top: -EDGE_SCROLL_STEP_PX, behavior: "auto" })
    } else if (clientY > rect.bottom - EDGE_SCROLL_ZONE_PX) {
      scrollContainer.scrollBy({ top: EDGE_SCROLL_STEP_PX, behavior: "auto" })
    }
  }

  releasePointerCapture(state) {
    if (!state?.handle?.hasPointerCapture?.(state.pointerId)) return

    state.handle.releasePointerCapture(state.pointerId)
  }

  clearDropState() {
    this.element.classList.remove("is-drag-active")

    this.clearActiveDropCandidate()

    this.directSiblingItems().forEach((item) => {
      item.classList.remove("is-drop-candidate", "is-drop-candidate-before", "is-drop-candidate-after")
    })
  }
}
