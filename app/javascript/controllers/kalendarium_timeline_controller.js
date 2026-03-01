import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["scroller"]
  static values = {
    startHour: Number,
    slotHeight: Number
  }

  connect() {
    if (!this.hasScrollerTarget) return
    if (this.scrollerTarget.dataset.kalendariumTimelineInitialized === "true") return

    const startHour = this.hasStartHourValue ? this.startHourValue : 5
    const slotHeight = this.hasSlotHeightValue ? this.slotHeightValue : 28
    const slotsPerHour = 2
    this.scrollerTarget.scrollTop = startHour * slotsPerHour * slotHeight
    this.scrollerTarget.dataset.kalendariumTimelineInitialized = "true"
  }
}
