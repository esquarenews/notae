import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "nav", "navList", "detailHead", "detailTitle", "search", "section", "footer"]

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

  searchTargetConnected() {
    this.queueRefresh()
  }

  sectionTargetConnected() {
    this.queueRefresh()
  }

  footerTargetConnected() {
    this.queueRefresh()
  }

  showList(event) {
    event?.preventDefault()
    event?.stopPropagation()
    this.activeSectionIndex = null
    this.resetSearch()
    this.renderMobileState()
  }

  handleMenuToggle() {
    if (!this.mobileViewport()) return

    if (!this.element.open) {
      this.activeSectionIndex = null
      this.resetSearch()
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
      if (this.hasSearchTarget) this.searchTarget.hidden = false
      if (this.hasFooterTarget) this.footerTarget.hidden = false
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
      if (this.sectionUnavailable(section)) return

      const button = document.createElement("button")
      const label = document.createElement("span")
      const caret = document.createElement("span")

      button.type = "button"
      button.className = "notae-actions-mobile-nav-button"
      button.dataset.actionsMenuIndex = index.toString()
      label.className = "notae-actions-mobile-nav-button-label"
      label.textContent = this.sectionLabel(section)
      caret.className = "notae-actions-mobile-nav-button-caret"
      caret.setAttribute("aria-hidden", "true")
      caret.textContent = "›"
      button.append(label, caret)
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

    const section = this.sectionTargets[index]
    if (this.sectionUnavailable(section)) return
    if (this.activeSectionIndex === index) {
      this.showList()
      return
    }

    this.activeSectionIndex = index
    this.resetSearch()
    this.renderMobileState()

    const focusTarget = section.querySelector("input:not([type='hidden']), select, textarea, button, a[href]")
    if (focusTarget) focusTarget.focus({ preventScroll: true })
  }

  renderMobileState() {
    if (!this.hasPanelTarget) return
    if (!this.mobileViewport()) return

    const validIndex = Number.isInteger(this.activeSectionIndex) &&
      this.activeSectionIndex >= 0 &&
      this.activeSectionIndex < this.sectionTargets.length &&
      !this.sectionUnavailable(this.sectionTargets[this.activeSectionIndex])
    const showList = !validIndex

    this.panelTarget.classList.toggle("is-mobile-detail-open", !showList)

    if (this.hasNavTarget) this.navTarget.hidden = false
    if (this.hasDetailHeadTarget) this.detailHeadTarget.hidden = showList
    if (this.hasSearchTarget) this.searchTarget.hidden = true
    if (this.hasFooterTarget) this.footerTarget.hidden = true

    this.sectionTargets.forEach((section, index) => {
      if (this.sectionUnavailable(section)) {
        section.hidden = true
        return
      }

      section.hidden = showList || index !== this.activeSectionIndex
    })

    if (!showList && this.hasDetailTitleTarget) {
      this.detailTitleTarget.textContent = this.sectionLabel(this.sectionTargets[this.activeSectionIndex])
    }

    this.updateNavSelection()
  }

  sectionUnavailable(section) {
    return this.panelLocked() && section.hasAttribute("data-shell-actions-section")
  }

  panelLocked() {
    return this.hasPanelTarget && this.panelTarget.classList.contains("is-page-locked")
  }

  sectionLabel(section) {
    const explicitLabel = section.dataset.actionsMenuLabel
    if (explicitLabel) return explicitLabel

    const actionLabel = section.querySelector(".notae-actions-row-label")
    if (actionLabel && actionLabel.textContent) return actionLabel.textContent.trim()

    return "Section"
  }

  updateNavSelection() {
    this.navButtons.forEach((button) => {
      const index = Number.parseInt(button.dataset.actionsMenuIndex || "", 10)
      const active = Number.isInteger(index) && index === this.activeSectionIndex
      button.classList.toggle("is-active", active)
      button.setAttribute("aria-expanded", active ? "true" : "false")
    })
  }

  resetSearch() {
    if (!this.hasSearchTarget) return
    if (this.searchTarget.value === "") return

    this.searchTarget.value = ""
    this.searchTarget.dispatchEvent(new Event("input", { bubbles: true }))
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
