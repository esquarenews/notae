import { Controller } from "@hotwired/stimulus"

const ARCHIVE_LONG_PRESS_MS = 850
const ARCHIVE_LONG_PRESS_MOVE_TOLERANCE = 14

export default class extends Controller {
  static targets = ["quickSwitcher", "quickInput", "quickResults", "shortcutGuide"]

  connect() {
    this.quickItems = []
    this.filteredQuickItems = []
    this.quickSelectedIndex = 0
    this.easterEggSequence = ""
    this.easterEggSequenceTimer = null
    this.archiveLongPressTimer = null
    this.archiveLongPressPointerId = null
    this.archiveLongPressStart = null

    this.onWindowKeydown = (event) => this.handleWindowKeydown(event)
    this.onPointerDown = (event) => this.beginArchiveLongPress(event)
    this.onPointerMove = (event) => this.trackArchiveLongPressMove(event)
    this.onPointerUp = (event) => this.cancelArchiveLongPress(event)
    this.onContextMenu = (event) => this.handleArchiveLongPressContextMenu(event)

    window.addEventListener("keydown", this.onWindowKeydown)
    this.element.addEventListener("pointerdown", this.onPointerDown, true)
    this.element.addEventListener("pointermove", this.onPointerMove, true)
    this.element.addEventListener("pointerup", this.onPointerUp, true)
    this.element.addEventListener("pointercancel", this.onPointerUp, true)
    this.element.addEventListener("contextmenu", this.onContextMenu, true)
  }

  disconnect() {
    window.removeEventListener("keydown", this.onWindowKeydown)
    this.element.removeEventListener("pointerdown", this.onPointerDown, true)
    this.element.removeEventListener("pointermove", this.onPointerMove, true)
    this.element.removeEventListener("pointerup", this.onPointerUp, true)
    this.element.removeEventListener("pointercancel", this.onPointerUp, true)
    this.element.removeEventListener("contextmenu", this.onContextMenu, true)
    if (this.easterEggSequenceTimer) {
      window.clearTimeout(this.easterEggSequenceTimer)
    }
    this.cancelArchiveLongPress()
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

    if (!query) {
      this.filteredQuickItems = this.quickItems.slice(0, 30)
    } else {
      this.filteredQuickItems = this.quickItems
        .filter((item) => item.title.toLowerCase().includes(query))
        .slice(0, 30)

      if (this.archiveGameMatchesQuery(query)) {
        const archiveItem = this.archiveGameQuickItem()
        this.filteredQuickItems = [
          archiveItem,
          ...this.filteredQuickItems.filter((item) => item.url !== archiveItem.url)
        ].slice(0, 30)
      }
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

  beginArchiveLongPress(event) {
    if (!this.archiveLongPressTarget(event.target) || !this.currentWorkspaceSlug()) return
    if (event.pointerType === "mouse" && !this.coarsePointer()) return
    if (event.pointerType === "mouse" && event.button !== 0) return

    this.cancelArchiveLongPress()
    this.archiveLongPressPointerId = event.pointerId
    this.archiveLongPressStart = { x: event.clientX, y: event.clientY }

    if (event.pointerType === "touch" || event.pointerType === "pen" || this.coarsePointer()) {
      event.preventDefault()
    }

    this.archiveLongPressTimer = window.setTimeout(() => {
      this.archiveLongPressTimer = null
      this.archiveLongPressPointerId = null
      this.archiveLongPressStart = null
      this.openArchiveGame()
    }, ARCHIVE_LONG_PRESS_MS)
  }

  trackArchiveLongPressMove(event) {
    if (!this.archiveLongPressStart || event.pointerId !== this.archiveLongPressPointerId) return

    const movement = Math.hypot(
      event.clientX - this.archiveLongPressStart.x,
      event.clientY - this.archiveLongPressStart.y
    )
    if (movement > ARCHIVE_LONG_PRESS_MOVE_TOLERANCE) {
      this.cancelArchiveLongPress()
    }
  }

  cancelArchiveLongPress() {
    if (this.archiveLongPressTimer) {
      window.clearTimeout(this.archiveLongPressTimer)
    }
    this.archiveLongPressTimer = null
    this.archiveLongPressPointerId = null
    this.archiveLongPressStart = null
  }

  handleArchiveLongPressContextMenu(event) {
    if (this.archiveLongPressTarget(event.target) && this.coarsePointer()) {
      event.preventDefault()
    }
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

  archiveGameMatchesQuery(query) {
    if (!query || query.length < 3 || !this.currentWorkspaceSlug()) return false

    return "archive".startsWith(query) || "the archive".includes(query)
  }

  archiveGamePath(workspaceSlug) {
    return `/w/${encodeURIComponent(workspaceSlug)}/_archive`
  }

  currentWorkspaceSlug() {
    const bodySlug = document.body.dataset.aiRailWorkspaceSlugValue?.toString().trim()
    if (bodySlug) return bodySlug

    const workspacePath = window.location.pathname.match(/^\/w\/([^/]+)/)
    if (!workspacePath) return ""

    return decodeURIComponent(workspacePath[1])
  }

  interactiveElement(target) {
    return Boolean(target?.closest?.("input, textarea, select, button, a, [contenteditable='true']"))
  }

  archiveLongPressTarget(target) {
    if (this.interactiveElement(target)) return false

    return Boolean(target?.closest?.(".notae-topbar-title, .notae-topbar-page-icon"))
  }

  coarsePointer() {
    return Boolean(window.matchMedia?.("(pointer: coarse)")?.matches)
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
