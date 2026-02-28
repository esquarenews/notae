import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["createMenu", "actionsMenu", "optionsMenu", "workspaceDialog", "workspaceNameInput", "workspaceSlugInput"]

  connect() {
    this.onKeydown = (event) => {
      if (event.key === "Escape") {
        this.closeCreateMenu()
        this.closeCommentsMenu()
        this.close()
      }
    }
    this.onWindowClick = (event) => this.handleWindowClick(event)
    window.addEventListener("keydown", this.onKeydown)
    window.addEventListener("click", this.onWindowClick)
  }

  disconnect() {
    window.removeEventListener("keydown", this.onKeydown)
    window.removeEventListener("click", this.onWindowClick)
    this.unlockBody()
    this.closeCreateMenu()
    this.closeActionsMenu()
    this.closeOptionsMenu()
  }

  toggle() {
    this.element.classList.contains("sidebar-open") ? this.close() : this.open()
  }

  open() {
    this.element.classList.add("sidebar-open")
    document.body.classList.add("notae-sidebar-open")
  }

  close() {
    this.element.classList.remove("sidebar-open")
    this.unlockBody()
    this.closeCreateMenu()
    this.closeWorkspaceDialog()
    this.closeActionsMenu()
    this.closeOptionsMenu()
    this.closeCommentsMenu()
  }

  unlockBody() {
    document.body.classList.remove("notae-sidebar-open")
  }

  toggleCreateMenu(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.hasCreateMenuTarget) return

    this.createMenuTarget.classList.toggle("is-hidden")
  }

  closeCreateMenu() {
    if (!this.hasCreateMenuTarget) return

    this.createMenuTarget.classList.add("is-hidden")
  }

  openWorkspaceDialog(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.hasWorkspaceDialogTarget) return

    this.closeCreateMenu()
    this.workspaceDialogTarget.classList.remove("is-hidden")
    if (this.hasWorkspaceSlugInputTarget) {
      this.workspaceSlugInputTarget.dataset.userEdited = "false"
    }
    if (this.hasWorkspaceNameInputTarget) {
      this.workspaceNameInputTarget.focus()
    }
  }

  closeWorkspaceDialog(event) {
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }
    if (!this.hasWorkspaceDialogTarget) return

    this.workspaceDialogTarget.classList.add("is-hidden")
  }

  syncWorkspaceSlug(event) {
    if (!this.hasWorkspaceSlugInputTarget) return
    if (this.workspaceSlugInputTarget.dataset.userEdited === "true") return

    const normalized = (event.target?.value || "")
      .toLowerCase()
      .trim()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .replace(/-{2,}/g, "-")
    this.workspaceSlugInputTarget.value = normalized
  }

  markWorkspaceSlugEdited() {
    if (!this.hasWorkspaceSlugInputTarget) return

    this.workspaceSlugInputTarget.dataset.userEdited = "true"
  }

  closeActionsMenu() {
    if (!this.hasActionsMenuTarget) return

    this.actionsMenuTarget.removeAttribute("open")
    this.resetActionsFilter(this.actionsMenuTarget)
    this.clearMenuQuery("actions_menu")
  }

  closeOptionsMenu() {
    if (!this.hasOptionsMenuTarget) return

    this.optionsMenuTarget.removeAttribute("open")
    this.clearMenuQuery("options_menu")
  }

  openCommentsMenu(event) {
    event.preventDefault()
    event.stopPropagation()

    const commentsMenu = this.element.querySelector("[data-shell-comments-menu]")
    if (!commentsMenu) return

    commentsMenu.setAttribute("open", "open")
    const input = commentsMenu.querySelector("input[name='comment[body]']")
    if (input) input.focus()
  }

  closeCommentsMenu() {
    const commentsMenu = this.element.querySelector("[data-shell-comments-menu]")
    if (!commentsMenu) return

    commentsMenu.removeAttribute("open")
  }

  openOptionsMenu(event) {
    event.preventDefault()
    event.stopPropagation()

    const optionsMenu = this.element.querySelector("[data-shell-options-menu]")
    if (!optionsMenu) return

    optionsMenu.setAttribute("open", "open")
  }

  copyPageLink(event) {
    event.preventDefault()
    const url = new URL(window.location.href)
    url.searchParams.delete("actions_menu")
    url.searchParams.delete("options_menu")
    this.copyText(url.toString())
  }

  copyFromDataset(event) {
    event.preventDefault()
    const value = event.currentTarget?.dataset?.copyValue
    if (!value) return

    this.copyText(value)
  }

  copyPageContents(event) {
    event.preventDefault()

    const source =
      event.target.closest("[data-shell-actions-panel]")?.querySelector("[data-shell-page-content]") ||
      this.actionsMenuTarget?.querySelector("[data-shell-page-content]")
    if (!source) return

    this.copyText(source.value || source.textContent || "")
  }

  undo(event) {
    event.preventDefault()
    document.execCommand("undo")
  }

  filterActionsMenu(event) {
    const query = event.target.value.toLowerCase().trim()
    const panel = event.target.closest("[data-shell-actions-panel]")
    if (!panel) return

    const items = panel.querySelectorAll("[data-shell-action-item]")
    items.forEach((item) => {
      const terms = (item.dataset.shellActionTerms || item.textContent || "").toLowerCase()
      item.hidden = query.length > 0 && !terms.includes(query)
    })

    panel.querySelectorAll("[data-shell-actions-section]").forEach((section) => {
      const visibleItems = Array.from(section.querySelectorAll("[data-shell-action-item]")).some((item) => !item.hidden)
      section.hidden = !visibleItems
    })
  }

  handleWindowClick(event) {
    this.handleCreateMenuWindowClick(event)
    this.handleActionsMenuWindowClick(event)
    this.handleOptionsMenuWindowClick(event)
  }

  handleCreateMenuWindowClick(event) {
    if (!this.hasCreateMenuTarget) return
    if (this.createMenuTarget.classList.contains("is-hidden")) return

    if (event.target.closest("[data-shell-create-toggle]") || event.target.closest("[data-shell-target='createMenu']")) {
      return
    }

    this.closeCreateMenu()
  }

  handleActionsMenuWindowClick(event) {
    if (!this.hasActionsMenuTarget) return
    if (!this.actionsMenuTarget.hasAttribute("open")) return
    if (event.target.closest("[data-shell-actions-menu]")) return

    this.closeActionsMenu()
  }

  handleOptionsMenuWindowClick(event) {
    if (!this.hasOptionsMenuTarget) return
    if (!this.optionsMenuTarget.hasAttribute("open")) return
    if (event.target.closest("[data-shell-options-menu]")) return

    this.closeOptionsMenu()
  }

  resetActionsFilter(menuElement) {
    const searchInput = menuElement.querySelector(".notae-actions-search")
    if (searchInput) searchInput.value = ""

    menuElement.querySelectorAll("[data-shell-action-item]").forEach((item) => {
      item.hidden = false
    })

    menuElement.querySelectorAll("[data-shell-actions-section]").forEach((section) => {
      section.hidden = false
    })
  }

  copyText(value) {
    const text = (value || "").toString()
    if (!text.length) return

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).catch(() => this.copyTextFallback(text))
      return
    }

    this.copyTextFallback(text)
  }

  copyTextFallback(text) {
    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.setAttribute("readonly", "readonly")
    textarea.style.position = "fixed"
    textarea.style.opacity = "0"
    document.body.appendChild(textarea)
    textarea.select()
    document.execCommand("copy")
    textarea.remove()
  }

  clearMenuQuery(paramKey) {
    const url = new URL(window.location.href)
    if (!url.searchParams.has(paramKey)) return

    url.searchParams.delete(paramKey)
    const suffix = `${url.pathname}${url.search}${url.hash}`
    window.history.replaceState({}, "", suffix)
  }

  noop(event) {
    event.stopPropagation()
  }
}
