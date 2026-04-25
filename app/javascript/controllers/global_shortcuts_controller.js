import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["quickSwitcher", "quickInput", "quickResults", "shortcutGuide"]

  connect() {
    this.quickItems = []
    this.filteredQuickItems = []
    this.quickSelectedIndex = 0
    this.easterEggSequence = ""
    this.easterEggSequenceTimer = null

    this.onWindowKeydown = (event) => this.handleWindowKeydown(event)
    window.addEventListener("keydown", this.onWindowKeydown)
  }

  disconnect() {
    window.removeEventListener("keydown", this.onWindowKeydown)
    if (this.easterEggSequenceTimer) {
      window.clearTimeout(this.easterEggSequenceTimer)
    }
  }

  openQuickSwitcher() {
    this.closeAll()
    this.loadQuickItems()
    this.quickInputTarget.value = ""
    this.quickSelectedIndex = 0
    this.filteredQuickItems = this.quickItems.slice(0, 30)
    this.renderQuickResults()
    this.quickSwitcherTarget.classList.remove("is-hidden")
    this.quickInputTarget.focus()
  }

  openShortcutGuide() {
    this.closeAll()
    this.shortcutGuideTarget.classList.remove("is-hidden")
  }

  closeAll() {
    this.quickSwitcherTarget.classList.add("is-hidden")
    this.shortcutGuideTarget.classList.add("is-hidden")
  }

  noop(event) {
    event.stopPropagation()
  }

  filterQuickResults() {
    const query = this.quickInputTarget.value.toLowerCase().trim()
    this.quickSelectedIndex = 0

    if (query === "archive" && this.currentWorkspaceSlug()) {
      this.filteredQuickItems = [this.archiveGameQuickItem()]
    } else if (!query) {
      this.filteredQuickItems = this.quickItems.slice(0, 30)
    } else {
      this.filteredQuickItems = this.quickItems
        .filter((item) => item.title.toLowerCase().includes(query))
        .slice(0, 30)
    }

    this.renderQuickResults()
  }

  handleQuickInputKeydown(event) {
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.moveSelection(1)
      return
    }

    if (event.key === "ArrowUp") {
      event.preventDefault()
      this.moveSelection(-1)
      return
    }

    if (event.key === "Enter") {
      event.preventDefault()
      this.navigateToSelectedQuickItem()
      return
    }

    if (event.key === "Escape") {
      event.preventDefault()
      this.closeAll()
    }
  }

  chooseQuickResult(event) {
    event.preventDefault()
    const index = Number(event.currentTarget.dataset.index)
    if (Number.isFinite(index)) {
      this.quickSelectedIndex = index
      this.navigateToSelectedQuickItem()
    }
  }

  hoverQuickResult(event) {
    const index = Number(event.currentTarget.dataset.index)
    if (Number.isFinite(index)) {
      this.quickSelectedIndex = index
      this.renderQuickResults()
    }
  }

  handleWindowKeydown(event) {
    const metaOrCtrl = event.metaKey || event.ctrlKey
    const key = event.key.toLowerCase()

    if (metaOrCtrl && !event.shiftKey && !event.altKey && key === "k") {
      event.preventDefault()
      this.openQuickSwitcher()
      return
    }

    if (metaOrCtrl && !event.altKey && (event.key === "/" || event.key === "?")) {
      event.preventDefault()
      this.openShortcutGuide()
      return
    }

    if (!metaOrCtrl && !event.altKey && !event.shiftKey && key.length === 1 && !this.interactiveElement(event.target)) {
      this.trackArchiveSequence(key)
      if (this.easterEggSequence === "archive") {
        event.preventDefault()
        this.openArchiveGame()
        return
      }
    }

    if (event.key === "Escape" && (this.quickSwitcherOpen() || this.shortcutGuideOpen())) {
      event.preventDefault()
      this.closeAll()
    }
  }

  trackArchiveSequence(key) {
    if (!this.currentWorkspaceSlug()) return

    this.easterEggSequence = `${this.easterEggSequence}${key}`.slice(-7)
    if (this.easterEggSequenceTimer) {
      window.clearTimeout(this.easterEggSequenceTimer)
    }
    this.easterEggSequenceTimer = window.setTimeout(() => {
      this.easterEggSequence = ""
    }, 2200)
  }

  openArchiveGame() {
    const workspaceSlug = this.currentWorkspaceSlug()
    if (!workspaceSlug) return

    const path = this.archiveGamePath(workspaceSlug)
    if (window.Turbo?.visit) {
      window.Turbo.visit(path)
    } else {
      window.location.assign(path)
    }
  }

  archiveGameQuickItem() {
    return {
      title: "The Archive",
      url: this.archiveGamePath(this.currentWorkspaceSlug())
    }
  }

  archiveGamePath(workspaceSlug) {
    return `/w/${encodeURIComponent(workspaceSlug)}/_archive`
  }

  currentWorkspaceSlug() {
    return document.body.dataset.aiRailWorkspaceSlugValue?.toString().trim()
  }

  interactiveElement(target) {
    return Boolean(target?.closest?.("input, textarea, select, button, a, [contenteditable='true']"))
  }

  quickSwitcherOpen() {
    return !this.quickSwitcherTarget.classList.contains("is-hidden")
  }

  shortcutGuideOpen() {
    return !this.shortcutGuideTarget.classList.contains("is-hidden")
  }

  loadQuickItems() {
    const links = Array.from(document.querySelectorAll(".notae-sidebar a[href*='/pages/']"))
    const seen = new Set()

    this.quickItems = links
      .map((link) => ({
        title: link.textContent.toString().trim(),
        url: link.getAttribute("href")
      }))
      .filter((item) => item.title.length > 0 && item.url)
      .filter((item) => {
        if (seen.has(item.url)) return false
        seen.add(item.url)
        return true
      })
  }

  moveSelection(delta) {
    if (this.filteredQuickItems.length === 0) return

    const next = this.quickSelectedIndex + delta
    if (next < 0) {
      this.quickSelectedIndex = this.filteredQuickItems.length - 1
    } else if (next >= this.filteredQuickItems.length) {
      this.quickSelectedIndex = 0
    } else {
      this.quickSelectedIndex = next
    }

    this.renderQuickResults()
  }

  navigateToSelectedQuickItem() {
    if (this.filteredQuickItems.length === 0) return

    const item = this.filteredQuickItems[this.quickSelectedIndex]
    if (!item) return

    window.location.assign(item.url)
  }

  renderQuickResults() {
    if (this.filteredQuickItems.length === 0) {
      this.quickResultsTarget.innerHTML = '<p class="notae-quick-empty">No matching Notarum.</p>'
      return
    }

    this.quickResultsTarget.innerHTML = this.filteredQuickItems
      .map((item, index) => {
        const activeClass = index === this.quickSelectedIndex ? " active" : ""
        return `<button type="button" class="notae-quick-result${activeClass}" data-index="${index}" data-action="click->global-shortcuts#chooseQuickResult mouseenter->global-shortcuts#hoverQuickResult">${this.escapeHtml(item.title)}</button>`
      })
      .join("")
  }

  escapeHtml(value) {
    return value.toString()
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;")
  }
}
