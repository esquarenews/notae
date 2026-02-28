import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["summary", "panel"]
  static values = {
    gap: Number,
    margin: Number
  }

  connect() {
    this.boundReposition = this.reposition.bind(this)
  }

  disconnect() {
    this.teardownListeners()
    this.resetPanelStyles()
  }

  toggle() {
    this.syncOpenStateClass()

    if (this.element.open) {
      this.setupListeners()
      this.reposition()
      return
    }

    this.teardownListeners()
    this.resetPanelStyles()
  }

  reposition() {
    if (!this.element.open || !this.hasSummaryTarget || !this.hasPanelTarget) return

    const panel = this.panelTarget
    const summary = this.summaryTarget
    const margin = this.hasMarginValue ? this.marginValue : 12
    const gap = this.hasGapValue ? this.gapValue : 6

    panel.classList.add("is-floating")
    panel.style.visibility = "hidden"
    panel.style.maxHeight = ""
    panel.style.top = "0px"
    panel.style.left = "0px"

    const summaryRect = summary.getBoundingClientRect()
    const panelRect = panel.getBoundingClientRect()
    const measuredHeight = Math.max(panelRect.height, panel.scrollHeight || 0)
    const measuredWidth = Math.max(panelRect.width, panel.scrollWidth || 0)
    const availableBelow = Math.max(0, window.innerHeight - summaryRect.bottom - margin)
    const availableAbove = Math.max(0, summaryRect.top - margin)
    const openBelow = availableBelow >= measuredHeight || availableBelow >= availableAbove
    const maxHeight = Math.max(140, openBelow ? availableBelow : availableAbove)
    const panelHeight = Math.min(Math.max(measuredHeight, 1), maxHeight)

    let top
    if (openBelow) {
      top = summaryRect.bottom + gap
    } else {
      top = summaryRect.top - gap - panelHeight
    }

    const maxLeft = Math.max(margin, window.innerWidth - measuredWidth - margin)
    const left = Math.min(Math.max(summaryRect.left, margin), maxLeft)
    const maxTop = Math.max(margin, window.innerHeight - panelHeight - margin)
    const clampedTop = Math.min(Math.max(top, margin), maxTop)

    panel.style.top = `${clampedTop}px`
    panel.style.left = `${left}px`
    panel.style.maxHeight = `${maxHeight}px`
    panel.style.visibility = ""
  }

  setupListeners() {
    window.addEventListener("resize", this.boundReposition)
    window.addEventListener("scroll", this.boundReposition, true)
  }

  teardownListeners() {
    window.removeEventListener("resize", this.boundReposition)
    window.removeEventListener("scroll", this.boundReposition, true)
  }

  resetPanelStyles() {
    if (!this.hasPanelTarget) return

    const panel = this.panelTarget
    panel.classList.remove("is-floating")
    panel.style.top = ""
    panel.style.left = ""
    panel.style.maxHeight = ""
    panel.style.visibility = ""
  }

  syncOpenStateClass() {
    const controls = this.element.closest(".notae-db-row-hover-controls")
    if (!controls) return

    controls.classList.toggle("is-menu-open", this.element.open)
  }
}
