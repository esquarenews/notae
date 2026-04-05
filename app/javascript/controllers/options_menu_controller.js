import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "nav", "navList", "detailHead", "detailTitle", "section"]

  connect() {
    this.viewportQuery = window.matchMedia("(max-width: 960px)")
    this.visualViewport = window.visualViewport || null
    this.activeSectionIndex = null
    this.navButtons = []

    this.onViewportChange = () => this.syncViewportMode()
    this.onMenuToggle = () => this.handleMenuToggle()

    if (typeof this.viewportQuery.addEventListener === "function") {
      this.viewportQuery.addEventListener("change", this.onViewportChange)
    } else {
      this.viewportQuery.addListener(this.onViewportChange)
    }

    if (this.visualViewport && typeof this.visualViewport.addEventListener === "function") {
      this.visualViewport.addEventListener("resize", this.onViewportChange)
    }

    this.element.addEventListener("toggle", this.onMenuToggle)
    this.buildMobileNavigation()
    this.syncViewportMode()
  }

  disconnect() {
    if (this.viewportQuery) {
      if (typeof this.viewportQuery.removeEventListener === "function") {
        this.viewportQuery.removeEventListener("change", this.onViewportChange)
      } else {
        this.viewportQuery.removeListener(this.onViewportChange)
      }
    }

    if (this.visualViewport && typeof this.visualViewport.removeEventListener === "function") {
      this.visualViewport.removeEventListener("resize", this.onViewportChange)
    }

    this.element.removeEventListener("toggle", this.onMenuToggle)
  }

  refresh() {
    this.queueRefresh()
  }

  navTargetConnected() {
    this.queueRefresh()
  }

  navListTargetConnected() {
    this.queueRefresh()
  }

  detailHeadTargetConnected() {
    this.queueRefresh()
  }

  detailTitleTargetConnected() {
    this.queueRefresh()
  }

  sectionTargetConnected() {
    this.queueRefresh()
  }

  showList(event) {
    event?.preventDefault()
    event?.stopPropagation()
    this.activeSectionIndex = null
    this.renderMobileState()
  }

  handleMenuToggle() {
    if (!this.mobileViewport()) return
    if (!this.element.open) {
      this.activeSectionIndex = null
      this.renderMobileState()
      return
    }

    this.showList()
  }

  syncViewportMode() {
    if (!this.hasPanelTarget) return

    const mobile = this.mobileViewport()
    this.panelTarget.classList.toggle("is-mobile-drilldown", mobile)

    if (!mobile) {
      this.activeSectionIndex = null
      this.panelTarget.classList.remove("is-mobile-detail-open")
      if (this.hasNavTarget) this.navTarget.hidden = true
      if (this.hasDetailHeadTarget) this.detailHeadTarget.hidden = true
      this.sectionTargets.forEach((section) => {
        section.hidden = false
      })
      this.updateNavSelection()
      return
    }

    this.buildMobileNavigation()
    this.renderMobileState()
  }

  buildMobileNavigation() {
    if (!this.hasNavListTarget) return

    this.navListTarget.innerHTML = ""
    this.navButtons = []

    this.sectionTargets.forEach((section, index) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "notae-options-mobile-nav-button"
      button.dataset.optionsMenuIndex = index.toString()
      button.textContent = this.sectionLabel(section)
      button.addEventListener("click", (event) => this.openSection(index, event))
      this.navListTarget.appendChild(button)
      this.navButtons.push(button)
    })

    this.updateNavSelection()
  }

  openSection(index, event) {
    event?.preventDefault()
    event?.stopPropagation()

    if (!this.mobileViewport()) return
    if (index < 0 || index >= this.sectionTargets.length) return
    if (this.activeSectionIndex === index) {
      this.showList()
      return
    }

    this.activeSectionIndex = index
    this.renderMobileState()

    const section = this.sectionTargets[index]
    const focusTarget = section.querySelector("input:not([type='hidden']), select, textarea, button, a[href]")
    if (focusTarget) focusTarget.focus({ preventScroll: true })
  }

  renderMobileState() {
    if (!this.hasPanelTarget) return
    if (!this.mobileViewport()) return

    const hasSections = this.sectionTargets.length > 0
    const validIndex = Number.isInteger(this.activeSectionIndex) &&
      this.activeSectionIndex >= 0 &&
      this.activeSectionIndex < this.sectionTargets.length
    const showList = !hasSections || !validIndex

    this.panelTarget.classList.toggle("is-mobile-detail-open", !showList)

    if (this.hasNavTarget) this.navTarget.hidden = false
    if (this.hasDetailHeadTarget) this.detailHeadTarget.hidden = showList

    this.sectionTargets.forEach((section, index) => {
      section.hidden = showList || index !== this.activeSectionIndex
    })

    if (!showList && this.hasDetailTitleTarget) {
      this.detailTitleTarget.textContent = this.sectionLabel(this.sectionTargets[this.activeSectionIndex])
    }

    this.updateNavSelection()
  }

  sectionLabel(section) {
    const explicitLabel = section.dataset.optionsMenuLabel
    if (explicitLabel) return explicitLabel

    const heading = section.querySelector("h3")
    if (heading && heading.textContent) return heading.textContent.trim()

    return "Section"
  }

  updateNavSelection() {
    this.navButtons.forEach((button) => {
      const index = Number.parseInt(button.dataset.optionsMenuIndex || "", 10)
      const active = Number.isInteger(index) && index === this.activeSectionIndex
      button.classList.toggle("is-active", active)
      button.setAttribute("aria-expanded", active ? "true" : "false")
    })
  }

  mobileViewport() {
    const shell = this.element.closest(".notae-shell")
    if (shell && shell.classList.contains("is-mobile-viewport")) return true

    const visualWidth = this.visualViewport?.width
    if (typeof visualWidth === "number" && visualWidth > 0) {
      return visualWidth <= 960
    }

    if (this.viewportQuery) return this.viewportQuery.matches
    return window.innerWidth <= 960
  }

  queueRefresh() {
    if (this.refreshQueued) return

    this.refreshQueued = true
    window.requestAnimationFrame(() => {
      this.refreshQueued = false
      this.buildMobileNavigation()
      this.syncViewportMode()
    })
  }
}
