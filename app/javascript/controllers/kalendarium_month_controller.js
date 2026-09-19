import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["grid", "dayCell", "agenda", "agendaTitle", "dayAgenda", "toast", "toastMessage", "undoButton"]

  connect() {
    this.touchOrigin = null
    this.longPressTimer = null
    this.moveDraft = null
    this.lastMove = null
  }

  disconnect() {
    this.cancelLongPress()
  }

  touchStart(event) {
    if (event.touches.length !== 1 || this.interactiveTarget(event.target)) return
    const touch = event.touches[0]
    this.touchOrigin = { x: touch.clientX, y: touch.clientY, at: Date.now() }
  }

  touchEnd(event) {
    if (!this.touchOrigin || event.changedTouches.length !== 1) return
    const touch = event.changedTouches[0]
    const dx = touch.clientX - this.touchOrigin.x
    const dy = touch.clientY - this.touchOrigin.y
    const elapsed = Date.now() - this.touchOrigin.at
    this.touchOrigin = null

    if (elapsed > 700 || Math.abs(dx) < 60 || Math.abs(dx) < Math.abs(dy) * 1.4) return
    const destination = dx < 0
      ? this.gridTarget.dataset.kalendariumMonthNextUrlValue
      : this.gridTarget.dataset.kalendariumMonthPreviousUrlValue
    if (destination) Turbo.visit(destination)
  }

  openAgenda(event) {
    if (!this.mobileMonthView()) return
    if (this.suppressNextClick) {
      event.preventDefault()
      event.stopPropagation()
      this.suppressNextClick = false
      return
    }
    if (this.moveDraft) {
      event.preventDefault()
      this.moveToDay(event.currentTarget.closest("[data-day-date]")?.dataset.dayDate)
      return
    }
    if (this.interactiveTarget(event.target) && !event.target.closest(".notae-kalendarium-month-overflow-label, .notae-kalendarium-month-day-focus-link")) return

    const cell = event.currentTarget.closest("[data-day-date]")
    if (!cell || !this.hasAgendaTarget) return
    event.preventDefault()
    this.showAgenda(cell.dataset.dayDate)
  }

  showAgenda(dateString) {
    const panel = this.dayAgendaTargets.find((candidate) => candidate.dataset.dayDate === dateString)
    if (!panel) return

    this.dayAgendaTargets.forEach((candidate) => { candidate.hidden = candidate !== panel })
    this.agendaTitleTarget.textContent = panel.dataset.dayLabel || "Events"
    if (!this.agendaTarget.open) this.agendaTarget.showModal()
  }

  closeAgenda(event) {
    event?.preventDefault()
    if (this.hasAgendaTarget) this.agendaTarget.close()
  }

  backdropCloseAgenda(event) {
    if (event.target === this.agendaTarget) this.agendaTarget.close()
  }

  quickAdd(event) {
    const date = event.currentTarget.dataset.dayDate
    if (!date) return
    this.closeAgenda()
    this.element.dispatchEvent(new CustomEvent("kalendarium:quick-create", {
      bubbles: true,
      detail: { date, startLocal: `${date}T09:00`, endLocal: `${date}T10:00` }
    }))
  }

  openEvent(event) {
    const eventCard = document.getElementById(event.currentTarget.dataset.eventDomId)
    if (!eventCard) return
    this.closeAgenda()
    eventCard.dispatchEvent(new MouseEvent("dblclick", { bubbles: true, cancelable: true }))
  }

  beginLongPress(event) {
    if (!this.mobileMonthView() || event.pointerType === "mouse" || event.target.closest("dialog") || event.currentTarget.dataset.kalendariumEventRecurring === "true") return
    this.longPressOrigin = { x: event.clientX, y: event.clientY }
    this.longPressTimer = window.setTimeout(() => {
      const card = event.currentTarget
      const cell = card.closest("[data-day-date]")
      this.suppressNextClick = true
      this.activateMove({
        eventId: card.dataset.kalendariumEventId,
        eventTitle: card.dataset.kalendariumEventTitle,
        eventDomId: card.id,
        sourceDate: cell?.dataset.dayDate
      })
      navigator.vibrate?.(25)
    }, 520)
  }

  moveLongPress(event) {
    if (!this.longPressOrigin) return
    if (Math.hypot(event.clientX - this.longPressOrigin.x, event.clientY - this.longPressOrigin.y) > 10) this.cancelLongPress()
  }

  endLongPress() {
    this.cancelLongPress()
  }

  cancelLongPress() {
    if (this.longPressTimer) window.clearTimeout(this.longPressTimer)
    this.longPressTimer = null
    this.longPressOrigin = null
  }

  startMove(event) {
    event.preventDefault()
    this.activateMove(event.currentTarget.dataset)
    this.closeAgenda()
  }

  activateMove(data) {
    if (!data.eventId || !data.sourceDate) return
    this.moveDraft = {
      eventId: data.eventId,
      eventTitle: data.eventTitle || "Event",
      eventDomId: data.eventDomId,
      sourceDate: data.sourceDate
    }
    this.dayCellTargets.forEach((cell) => cell.classList.add("is-move-target"))
    document.getElementById(this.moveDraft.eventDomId)?.classList.add("is-awaiting-move")
    this.showToast(`Choose a new day for ${this.moveDraft.eventTitle}`, false)
  }

  cancelMove(event) {
    event?.preventDefault()
    this.clearMoveMode()
    this.hideToast()
  }

  async moveToDay(targetDate) {
    if (!this.moveDraft || !targetDate || targetDate === this.moveDraft.sourceDate) {
      this.cancelMove()
      return
    }

    const move = { ...this.moveDraft, targetDate }
    this.clearMoveMode()
    const result = await this.persistMove(move.eventId, targetDate)
    if (!result.ok) {
      this.showToast(result.error || "Event could not be moved", false)
      return
    }

    this.moveCard(move.eventDomId, targetDate)
    this.lastMove = move
    this.showToast(result.notice || `${move.eventTitle} moved`, true)
  }

  async undoMove(event) {
    event.preventDefault()
    if (!this.lastMove) return
    const move = this.lastMove
    this.lastMove = null
    const result = await this.persistMove(move.eventId, move.sourceDate)
    if (!result.ok) {
      this.showToast(result.error || "Move could not be undone", false)
      return
    }
    this.moveCard(move.eventDomId, move.sourceDate)
    this.showToast("Move undone", false)
  }

  async persistMove(eventId, targetDate) {
    try {
      const response = await fetch(`${window.location.pathname.replace(/\/kalendarium$/, "/kalendarium/events")}/${eventId}/reschedule`, {
        method: "PATCH",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        },
        body: JSON.stringify({ target_date: targetDate })
      })
      const payload = await response.json()
      return response.ok ? { ok: true, ...payload } : { ok: false, error: payload.error }
    } catch (_error) {
      return { ok: false, error: "Event could not be moved. Check your connection and try again." }
    }
  }

  moveCard(domId, targetDate) {
    const card = document.getElementById(domId)
    const target = this.dayCellTargets.find((cell) => cell.dataset.dayDate === targetDate)
    const events = target?.querySelector(".notae-kalendarium-month-events")
    if (card && events) events.append(card)

    const eventId = card?.dataset.kalendariumEventId
    const agendaItem = this.element.querySelector(`[data-agenda-event-id="${CSS.escape(eventId || "")}"]`)
    const targetAgenda = this.dayAgendaTargets.find((panel) => panel.dataset.dayDate === targetDate)
    if (agendaItem && targetAgenda) {
      let list = targetAgenda.querySelector(".notae-kalendarium-day-agenda-list")
      if (!list) {
        list = document.createElement("ul")
        list.className = "notae-kalendarium-day-agenda-list"
        targetAgenda.querySelector(".notae-kalendarium-day-agenda-empty")?.remove()
        targetAgenda.prepend(list)
      }
      list.append(agendaItem)
      agendaItem.dataset.agendaDate = targetDate
    }
  }

  clearMoveMode() {
    this.dayCellTargets.forEach((cell) => cell.classList.remove("is-move-target"))
    if (this.moveDraft) document.getElementById(this.moveDraft.eventDomId)?.classList.remove("is-awaiting-move")
    this.moveDraft = null
  }

  showToast(message, undoable) {
    if (!this.hasToastTarget) return
    this.toastMessageTarget.textContent = message
    this.undoButtonTarget.hidden = !undoable
    this.toastTarget.hidden = false
  }

  hideToast() {
    if (this.hasToastTarget) this.toastTarget.hidden = true
  }

  mobileMonthView() {
    return window.matchMedia("(max-width: 760px)").matches
  }

  interactiveTarget(target) {
    return target instanceof Element && target.closest("a, button, input, textarea, select, label, dialog, .notae-kalendarium-event-card") !== null
  }
}
