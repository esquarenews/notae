import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    workspaceSlug: String,
    databaseId: String,
    viewId: String,
    propertyId: String,
    month: String
  }

  connect() {
    this.draggedCard = null
    this.dropLane = null
    this.editingCard = null
    this.placeholder = document.createElement("div")
    this.placeholder.className = "notae-db-board-card-placeholder"
  }

  dragstart(event) {
    const card = event.currentTarget
    const rowId = card?.dataset.databaseDragRowId
    if (!rowId || card?.classList.contains("is-editing")) {
      event.preventDefault()
      return
    }

    this.draggedCard = card
    card.classList.add("is-dragging")

    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", rowId)
  }

  dragenter(event) {
    event.preventDefault()
    this.highlightLane(event.currentTarget)
  }

  dragover(event) {
    event.preventDefault()

    const lane = event.currentTarget
    if (!(lane instanceof HTMLElement)) return

    this.highlightLane(lane)
    if (!(this.draggedCard instanceof HTMLElement)) return

    const afterCard = this.afterCardForPointer(lane, event.clientY)
    if (afterCard) {
      lane.insertBefore(this.placeholder, afterCard)
    } else {
      lane.appendChild(this.placeholder)
    }
  }

  dragleave(event) {
    const lane = event.currentTarget
    if (!(lane instanceof HTMLElement)) return

    const relatedTarget = event.relatedTarget
    if (relatedTarget instanceof Node && lane.contains(relatedTarget)) return
    if (lane.contains(this.placeholder)) return

    lane.classList.remove("is-drop-target")
  }

  async drop(event) {
    event.preventDefault()

    const rowId = event.dataTransfer.getData("text/plain")
    const lane = event.currentTarget
    if (!rowId || !(lane instanceof HTMLElement) || !(this.draggedCard instanceof HTMLElement)) return

    const targetValue = lane.dataset.databaseDragTargetValue || ""
    const targetIndex = this.currentTargetIndex(lane)
    const payload = {
      property_id: this.propertyIdValue || null,
      target_value: targetValue,
      target_index: targetIndex,
      view_id: this.viewIdValue || null,
      month: this.monthValue || null
    }

    lane.classList.add("is-drop-committing")
    this.draggedCard.classList.add("is-drop-settling")

    if (lane.contains(this.placeholder)) {
      lane.insertBefore(this.draggedCard, this.placeholder)
    }

    try {
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

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`)
      }

      const result = await response.json()
      await this.wait(180)
      window.location.assign(result.redirect_url || window.location.href)
    } catch (error) {
      console.error("Board move failed", error)
      window.location.reload()
    } finally {
      this.clearDropState()
    }
  }

  dragend() {
    this.clearDropState()
  }

  beginEdit(event) {
    if (event.target.closest("input, textarea, button, select, a, summary")) return

    const card = event.currentTarget
    if (!(card instanceof HTMLElement)) return
    if (this.draggedCard instanceof HTMLElement) return

    this.showEdit(card)
  }

  submitEditFromKeydown(event) {
    event.preventDefault()
    this.commitEdit(event.target.closest("[data-database-drag-row-id]"))
  }

  submitEdit(event) {
    event.preventDefault()
    this.commitEdit(event.target.closest("[data-database-drag-row-id]"))
  }

  submitEditOnBlur(event) {
    const card = event.target.closest("[data-database-drag-row-id]")
    if (!(card instanceof HTMLElement)) return

    setTimeout(() => {
      if (card.contains(document.activeElement)) return
      this.commitEdit(card)
    }, 0)
  }

  cancelEdit(event) {
    event.preventDefault()
    const card = event.target.closest("[data-database-drag-row-id]")
    if (!(card instanceof HTMLElement)) return

    const input = this.editInputFor(card)
    if (input) {
      input.value = card.dataset.databaseDragTitle || ""
      input.setCustomValidity("")
    }

    this.hideEdit(card)
  }

  async commitEdit(card) {
    if (!(card instanceof HTMLElement)) return
    if (card.dataset.editPending === "true") return

    const input = this.editInputFor(card)
    const titleNode = this.titleNodeFor(card)
    if (!(input instanceof HTMLInputElement) || !(titleNode instanceof HTMLElement)) return

    const nextTitle = input.value.trim() || "Untitled row"
    const currentTitle = card.dataset.databaseDragTitle || titleNode.textContent?.trim() || ""
    input.setCustomValidity("")

    if (nextTitle === currentTitle) {
      this.hideEdit(card)
      return
    }

    card.dataset.editPending = "true"

    try {
      const response = await fetch(card.dataset.databaseDragUpdateUrl, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
        },
        body: JSON.stringify({
          db_row: {
            title: nextTitle,
            autosave_title: "1"
          }
        })
      })

      const payload = await response.json()
      if (!response.ok) {
        throw new Error(payload.error || `HTTP ${response.status}`)
      }

      card.dataset.databaseDragTitle = payload.title
      titleNode.textContent = payload.title
      input.value = payload.title
      this.updateEditedMeta(payload.topbar_edited_at_html)
      this.hideEdit(card)
    } catch (error) {
      input.setCustomValidity(error.message)
      input.reportValidity()
      input.focus({ preventScroll: true })
      input.select()
    } finally {
      delete card.dataset.editPending
    }
  }

  showEdit(card) {
    if (!(card instanceof HTMLElement)) return

    if (this.editingCard && this.editingCard !== card) {
      this.hideEdit(this.editingCard)
    }

    const display = this.displayFor(card)
    const form = this.editFormFor(card)
    const input = this.editInputFor(card)
    if (!display || !form || !input) return

    card.classList.add("is-editing")
    card.setAttribute("draggable", "false")
    display.hidden = true
    form.hidden = false
    input.value = card.dataset.databaseDragTitle || input.value
    input.focus({ preventScroll: true })
    input.select()
    this.editingCard = card
  }

  hideEdit(card) {
    if (!(card instanceof HTMLElement)) return

    const display = this.displayFor(card)
    const form = this.editFormFor(card)
    if (!display || !form) return

    card.classList.remove("is-editing")
    card.setAttribute("draggable", "true")
    display.hidden = false
    form.hidden = true
    if (this.editingCard === card) {
      this.editingCard = null
    }
  }

  displayFor(card) {
    return card.querySelector("[data-board-card-display]")
  }

  editFormFor(card) {
    return card.querySelector(".notae-db-board-card-edit-form")
  }

  editInputFor(card) {
    return card.querySelector(".notae-db-board-card-edit-input")
  }

  titleNodeFor(card) {
    return card.querySelector("[data-board-card-title]")
  }

  highlightLane(lane) {
    if (!(lane instanceof HTMLElement)) return

    if (this.dropLane && this.dropLane !== lane) {
      this.dropLane.classList.remove("is-drop-target")
    }

    lane.classList.add("is-drop-target")
    this.dropLane = lane
  }

  afterCardForPointer(lane, pointerY) {
    const candidates = this.laneCards(lane).filter((card) => card !== this.draggedCard)

    return candidates.reduce((closest, candidate) => {
      const rect = candidate.getBoundingClientRect()
      const offset = pointerY - rect.top - rect.height / 2
      if (offset < 0 && offset > closest.offset) {
        return { offset, element: candidate }
      }

      return closest
    }, { offset: Number.NEGATIVE_INFINITY, element: null }).element
  }

  laneCards(lane) {
    return Array.from(lane.querySelectorAll("[data-database-drag-row-id]"))
  }

  currentTargetIndex(lane) {
    if (lane.contains(this.placeholder)) {
      const orderedItems = Array.from(lane.querySelectorAll("[data-database-drag-row-id], .notae-db-board-card-placeholder"))
        .filter((item) => item !== this.draggedCard)
      return orderedItems.indexOf(this.placeholder)
    }

    return this.laneCards(lane).filter((card) => card !== this.draggedCard).length
  }

  clearDropState() {
    this.dropLane?.classList.remove("is-drop-target", "is-drop-committing")
    this.draggedCard?.classList.remove("is-dragging", "is-drop-settling")
    this.placeholder.remove()
    this.dropLane = null
    this.draggedCard = null
  }

  updateEditedMeta(html) {
    if (!html) return

    const target = document.getElementById("database_topbar_edited_at")
    if (target instanceof HTMLElement) {
      target.innerHTML = html
    }
  }

  wait(duration) {
    return new Promise((resolve) => window.setTimeout(resolve, duration))
  }
}
