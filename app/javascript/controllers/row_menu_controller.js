import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "panel"]
  static values = {
    gap: Number,
    margin: Number
  }

  connect() {
    this.isOpen = false
    this.controlsElement = this.element.closest(".notae-db-row-hover-controls")
    this.placeholder = null
    this.buttonElement = this.buttonTarget
    this.panelElement = this.panelTarget

    this.boundDocumentClick = this.handleDocumentClick.bind(this)
    this.boundKeydown = this.handleKeydown.bind(this)
    this.boundReposition = this.reposition.bind(this)
    this.boundBeforeCache = this.beforeCache.bind(this)

    this.buttonElement.setAttribute("aria-expanded", "false")
    this.panelElement.hidden = true
    this.panelElement.setAttribute("aria-hidden", "true")

    document.addEventListener("turbo:before-cache", this.boundBeforeCache)
  }

  disconnect() {
    this.close({ focusButton: false })
    document.removeEventListener("turbo:before-cache", this.boundBeforeCache)
  }

  toggle(event) {
    event.preventDefault()

    if (this.isOpen) {
      this.close({ focusButton: true })
      return
    }

    this.open()
  }

  open() {
    this.isOpen = true
    this.controlsElement?.classList.add("is-menu-open")
    this.buttonElement.setAttribute("aria-expanded", "true")
    this.portalPanel()
    this.panelElement.classList.add("is-floating")
    this.panelElement.hidden = false
    this.panelElement.setAttribute("aria-hidden", "false")

    this.setupListeners()
    this.reposition()
    window.requestAnimationFrame(() => this.reposition())
  }

  close({ focusButton = false } = {}) {
    if (!this.isOpen) {
      this.resetPanelState()
      return
    }

    this.isOpen = false
    this.controlsElement?.classList.remove("is-menu-open")
    this.buttonElement.setAttribute("aria-expanded", "false")

    this.teardownListeners()
    this.resetPanelState()

    if (focusButton) {
      this.buttonElement.focus()
    }
  }

  reposition() {
    if (!this.isOpen) return

    const panel = this.panelElement
    const buttonRect = this.buttonElement.getBoundingClientRect()
    const margin = this.hasMarginValue ? this.marginValue : 12
    const gap = this.hasGapValue ? this.gapValue : 6

    panel.style.visibility = "hidden"
    panel.style.top = "0px"
    panel.style.left = "0px"
    panel.style.maxHeight = ""

    const panelRect = panel.getBoundingClientRect()
    const panelHeight = Math.max(panelRect.height, panel.scrollHeight || 0, 1)
    const panelWidth = Math.max(panelRect.width, panel.scrollWidth || 0, 1)

    const availableBelow = Math.max(0, window.innerHeight - buttonRect.bottom - margin)
    const availableAbove = Math.max(0, buttonRect.top - margin)
    const openBelow = availableBelow >= panelHeight || availableBelow >= availableAbove

    const maxHeight = Math.max(180, openBelow ? availableBelow : availableAbove)
    const renderedHeight = Math.min(panelHeight, maxHeight)

    const top = openBelow ? buttonRect.bottom + gap : buttonRect.top - gap - renderedHeight
    const maxTop = Math.max(margin, window.innerHeight - renderedHeight - margin)
    const clampedTop = Math.min(Math.max(top, margin), maxTop)

    const desiredLeft = buttonRect.left
    const maxLeft = Math.max(margin, window.innerWidth - panelWidth - margin)
    const clampedLeft = Math.min(Math.max(desiredLeft, margin), maxLeft)

    panel.style.top = `${clampedTop}px`
    panel.style.left = `${clampedLeft}px`
    panel.style.maxHeight = `${maxHeight}px`
    panel.style.visibility = ""
  }

  setupListeners() {
    document.addEventListener("click", this.boundDocumentClick, true)
    document.addEventListener("keydown", this.boundKeydown)
    window.addEventListener("resize", this.boundReposition)
    window.addEventListener("scroll", this.boundReposition, true)
  }

  teardownListeners() {
    document.removeEventListener("click", this.boundDocumentClick, true)
    document.removeEventListener("keydown", this.boundKeydown)
    window.removeEventListener("resize", this.boundReposition)
    window.removeEventListener("scroll", this.boundReposition, true)
  }

  handleDocumentClick(event) {
    if (!this.isOpen) return

    const clickedInsideTrigger = this.element.contains(event.target)
    const clickedInsidePanel = this.panelElement.contains(event.target)
    if (clickedInsideTrigger || clickedInsidePanel) return

    this.close()
  }

  handleKeydown(event) {
    if (!this.isOpen) return

    if (event.key === "Escape") {
      event.preventDefault()
      this.close({ focusButton: true })
    }
  }

  beforeCache() {
    this.close({ focusButton: false })
  }

  resetPanelState() {
    this.restorePanel()
    this.panelElement.classList.remove("is-floating")
    this.panelElement.classList.remove("is-portaled")
    this.panelElement.style.top = ""
    this.panelElement.style.left = ""
    this.panelElement.style.maxHeight = ""
    this.panelElement.style.visibility = ""
    this.panelElement.hidden = true
    this.panelElement.setAttribute("aria-hidden", "true")
  }

  portalPanel() {
    if (this.panelElement.parentNode === document.body) return

    this.placeholder = document.createComment("row-menu-placeholder")
    this.panelElement.parentNode.insertBefore(this.placeholder, this.panelElement)
    document.body.appendChild(this.panelElement)
    this.panelElement.classList.add("is-portaled")
  }

  restorePanel() {
    if (this.panelElement.parentNode !== document.body) return

    if (this.placeholder?.parentNode) {
      this.placeholder.parentNode.insertBefore(this.panelElement, this.placeholder)
      this.placeholder.remove()
      this.placeholder = null
      return
    }

    this.element.appendChild(this.panelElement)
  }
}
