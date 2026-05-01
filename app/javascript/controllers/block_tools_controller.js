import { Controller } from "@hotwired/stimulus"

const MENU_VIEWPORT_MARGIN = 12
const MENU_TRIGGER_GAP = 6

export default class extends Controller {
  static values = {
    blockId: String,
    pageTitle: String,
    blockText: String
  }

  connect() {
    this.repositionOpenMenuHandler = (event) => this.repositionOpenMenu(event)
    this.windowPointerDownHandler = (event) => this.handleWindowPointerDown(event)
    this.documentKeydownHandler = (event) => this.handleDocumentKeydown(event)
    this.viewportHandlersInstalled = false
    this.syncShellScrollLock()
  }

  disconnect() {
    const details = this.currentOpenMenu()
    if (details) {
      details.open = false
      this.setMenuOpenState(details, false)
      this.resetPanelPosition(details)
    }
    this.removeViewportHandlers({ force: true })
    this.removeDismissHandlers()
    this.syncShellScrollLock()
  }

  async copyLink(event) {
    event.preventDefault()
    const trigger = event.currentTarget
    const url = `${window.location.origin}${window.location.pathname}#block_${this.blockIdValue}`

    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(url)
    } else {
      const helper = document.createElement("input")
      helper.value = url
      document.body.appendChild(helper)
      helper.select()
      document.execCommand("copy")
      helper.remove()
    }

    this.closeMenu({ currentTarget: trigger })
  }

  askAi(event) {
    event.preventDefault()
    this.prefillAiRail({
      prompt: "",
      intent: "compose",
      targetBlockId: this.blockIdValue,
      clearPrompt: true
    })

    this.closeMenu(event)
  }

  suggestEdits(event) {
    event.preventDefault()

    const blockContext = this.blockTextValue?.trim()
    if (!blockContext) return

    const prompt = [
      "Suggest edits for this block.",
      "Return a single improved version that fixes typos, grammar, and readability while preserving meaning.",
      `Original block text:\n${blockContext}`
    ].join("\n\n")

    this.prefillAiRail({
      prompt,
      intent: "suggest_edits",
      targetBlockId: this.blockIdValue,
      autoSubmit: true
    })

    this.closeMenu(event)
  }

  async indent(event) {
    event.preventDefault()
    this.closeMenu(event)
    await this.reparentBlock("indent")
  }

  async outdent(event) {
    event.preventDefault()
    this.closeMenu(event)
    await this.reparentBlock("outdent")
  }

  togglePicker(event) {
    event.preventDefault()
    event.stopPropagation()

    const form = event.currentTarget.closest(".notae-block-menu-picker-form")
    if (!form) return

    const pickerRegion = this.pickerRegionForForm(form)
    const picker = pickerRegion?.querySelector(".notae-block-menu-picker")
    const focusTarget = picker?.querySelector("[data-document-picker-target='searchInput'], .notae-block-menu-select")
    if (!picker || !(focusTarget instanceof HTMLElement)) return

    const shouldOpen = picker.hasAttribute("hidden")
    this.closeInlinePickers(form)

    if (!shouldOpen) return

    form.classList.add("is-picker-open")
    picker.hidden = false
    focusTarget.focus()
  }

  closeMenu(event) {
    const details = event.currentTarget.closest("details")
    if (details) this.closeDetails(details)
  }

  positionMenu(event) {
    const details = event.currentTarget
    if (!details || !details.open) {
      if (details) this.closeDetails(details)
      return
    }

    this.setMenuOpenState(details, true)
    this.installViewportHandlers()
    this.installDismissHandlers()
    this.applyPanelPosition(details)
  }

  repositionOpenMenu(event) {
    const details = this.currentOpenMenu()
    if (!details) return

    const panel = details.querySelector(".notae-block-menu-panel")
    const scrollTarget = event?.target
    if (panel && scrollTarget instanceof Node && panel.contains(scrollTarget)) return

    this.applyPanelPosition(details)
  }

  currentOpenMenu() {
    return this.element.querySelector(".notae-block-menu[open]")
  }

  installDismissHandlers() {
    if (this.dismissHandlersInstalled) return

    document.addEventListener("pointerdown", this.windowPointerDownHandler, true)
    document.addEventListener("keydown", this.documentKeydownHandler)
    this.dismissHandlersInstalled = true
  }

  removeDismissHandlers() {
    if (!this.dismissHandlersInstalled) return

    document.removeEventListener("pointerdown", this.windowPointerDownHandler, true)
    document.removeEventListener("keydown", this.documentKeydownHandler)
    this.dismissHandlersInstalled = false
  }

  handleWindowPointerDown(event) {
    const details = this.currentOpenMenu()
    if (!details) return

    const panel = details.querySelector(".notae-block-menu-panel")
    const trigger = details.querySelector(".notae-block-menu-trigger")
    const target = event.target
    if (!(target instanceof Node)) return
    if (panel && panel.contains(target)) return
    if (trigger && trigger.contains(target)) return

    this.closeDetails(details)
  }

  handleDocumentKeydown(event) {
    if (event.key !== "Escape") return

    const details = this.currentOpenMenu()
    if (!details) return

    this.closeDetails(details)
  }

  async handleReparentRequest(event) {
    if (String(event.detail?.blockId || "") !== String(this.blockIdValue || "")) return

    await this.reparentBlock(event.detail?.direction, { focusEditor: Boolean(event.detail?.focusEditor) })
  }

  closeDetails(details) {
    details.open = false
    this.closeInlinePickers()
    this.setMenuOpenState(details, false)
    this.resetPanelPosition(details)
    this.removeDismissHandlers()
    this.removeViewportHandlers()
  }

  installViewportHandlers() {
    if (this.viewportHandlersInstalled) return

    window.addEventListener("resize", this.repositionOpenMenuHandler)
    window.addEventListener("scroll", this.repositionOpenMenuHandler, true)
    this.viewportHandlersInstalled = true
  }

  removeViewportHandlers({ force = false } = {}) {
    if (!this.viewportHandlersInstalled) return
    if (!force && this.currentOpenMenu()) return

    window.removeEventListener("resize", this.repositionOpenMenuHandler)
    window.removeEventListener("scroll", this.repositionOpenMenuHandler, true)
    this.viewportHandlersInstalled = false
  }

  closeInlinePickers(exceptForm = null) {
    this.element.querySelectorAll(".notae-block-menu-picker-form").forEach((form) => {
      if (exceptForm && form === exceptForm) return

      form.classList.remove("is-picker-open")
      this.pickerRegionForForm(form)?.querySelectorAll(".notae-block-menu-picker").forEach((picker) => {
        picker.hidden = true
      })
    })
  }

  pickerRegionForForm(form) {
    return form.closest(".notae-block-menu-picker-row") || form
  }

  setMenuOpenState(details, isOpen) {
    const blockRow = details?.closest(".notae-doc-block-row")
    if (blockRow) blockRow.classList.toggle("is-menu-open", isOpen)
    this.syncShellScrollLock(isOpen)
  }

  syncShellScrollLock(forceOpen = null) {
    const shell = this.element.closest(".notae-shell")
    if (!shell) return

    const shouldLock = shell.classList.contains("is-mobile-viewport") &&
      (forceOpen === true || this.anyOpenBlockMenu(shell))
    shell.classList.toggle("is-block-menu-open", shouldLock)
  }

  anyOpenBlockMenu(scope) {
    return Boolean(scope?.querySelector(".notae-block-menu[open]"))
  }

  applyPanelPosition(details) {
    const panel = details.querySelector(".notae-block-menu-panel")
    const trigger = details.querySelector(".notae-block-menu-trigger")
    if (!panel || !trigger) return

    const bounds = this.visibleViewportBounds()
    panel.classList.add("is-viewport-positioned")
    panel.style.setProperty("--notae-menu-left", `${bounds.left}px`)
    panel.style.setProperty("--notae-menu-top", `${bounds.top}px`)
    panel.style.setProperty("--notae-menu-max-height", `${Math.max(160, bounds.bottom - bounds.top)}px`)
    panel.style.visibility = "hidden"

    const placement = this.computeViewportPlacement(trigger.getBoundingClientRect(), panel.getBoundingClientRect())
    panel.style.setProperty("--notae-menu-left", `${Math.round(placement.left)}px`)
    panel.style.setProperty("--notae-menu-top", `${Math.round(placement.top)}px`)
    panel.style.setProperty("--notae-menu-max-height", `${Math.round(placement.maxHeight)}px`)
    panel.style.visibility = ""
  }

  computeViewportPlacement(triggerRect, panelRect) {
    const bounds = this.visibleViewportBounds()
    const viewportWidth = Math.max(bounds.right - bounds.left, 0)
    const viewportHeight = Math.max(bounds.bottom - bounds.top, 0)
    const maxHeight = Math.max(160, viewportHeight)
    const panelWidth = Math.min(Math.max(panelRect.width || 0, 0), viewportWidth)
    const panelHeight = Math.min(Math.max(panelRect.height || 0, 0), maxHeight)

    let left = triggerRect.right - panelWidth
    left = Math.min(left, bounds.right - panelWidth)
    left = Math.max(bounds.left, left)

    let top = triggerRect.bottom + MENU_TRIGGER_GAP
    if (top + panelHeight > bounds.bottom) {
      top = triggerRect.top - MENU_TRIGGER_GAP - panelHeight
    }
    top = Math.min(top, bounds.bottom - panelHeight)
    top = Math.max(bounds.top, top)

    return { left, top, maxHeight }
  }

  visibleViewportBounds() {
    const visualViewport = window.visualViewport
    const viewportLeft = Math.max(visualViewport?.offsetLeft || 0, 0)
    const viewportTop = Math.max(visualViewport?.offsetTop || 0, 0)
    const viewportWidth = Math.max(visualViewport?.width || window.innerWidth || 0, 0)
    const viewportHeight = Math.max(visualViewport?.height || window.innerHeight || 0, 0)
    const shellScrollTop = this.element.closest(".notae-shell")?.querySelector(".notae-content-scroll")?.getBoundingClientRect()?.top
    const safeTop = Number.isFinite(shellScrollTop) ? Math.max(viewportTop, shellScrollTop) : viewportTop

    return {
      left: viewportLeft + MENU_VIEWPORT_MARGIN,
      top: safeTop + MENU_VIEWPORT_MARGIN,
      right: viewportLeft + viewportWidth - MENU_VIEWPORT_MARGIN,
      bottom: viewportTop + viewportHeight - MENU_VIEWPORT_MARGIN
    }
  }

  resetPanelPosition(details) {
    const panel = details.querySelector(".notae-block-menu-panel")
    if (!panel) return

    panel.classList.remove("is-viewport-positioned")
    panel.style.removeProperty("--notae-menu-left")
    panel.style.removeProperty("--notae-menu-top")
    panel.style.removeProperty("--notae-menu-max-height")
    panel.style.visibility = ""
  }

  prefillAiRail({ prompt, intent, targetBlockId, autoSubmit = false, clearPrompt = false }) {
    const detail = {
      prompt: String(prompt || ""),
      intent: String(intent || ""),
      targetBlockId: String(targetBlockId || ""),
      autoSubmit: Boolean(autoSubmit),
      clearPrompt: Boolean(clearPrompt)
    }

    window.dispatchEvent(new CustomEvent("notae:ai-prefill", { detail }))

    const promptInput = document.querySelector("#ai_prompt")
    if (!promptInput) return

    promptInput.value = detail.prompt
    promptInput.dispatchEvent(new Event("input", { bubbles: true }))

    const intentInput = document.querySelector("#ai_intent")
    if (intentInput) intentInput.value = detail.intent

    const targetBlockInput = document.querySelector("#ai_target_block_id")
    if (targetBlockInput) targetBlockInput.value = detail.targetBlockId

    promptInput.focus()
    if (!detail.autoSubmit) return

    const form = promptInput.form
    if (!form) return
    form.requestSubmit()
  }

  async reparentBlock(direction, { focusEditor = false } = {}) {
    const plan = direction === "outdent" ? this.outdentPlan() : this.indentPlan()
    if (!plan) return

    try {
      await this.flushBlockSave()
      await this.persistReparent(plan)
      if (focusEditor) this.focusEditor()
    } catch (_error) {}
  }

  indentPlan() {
    const currentBlock = this.currentBlock()
    const currentTree = this.currentTree()
    if (!currentBlock || !currentTree) return null

    const siblings = this.directChildBlocks(currentTree)
    const currentIndex = siblings.indexOf(currentBlock)
    if (currentIndex <= 0) return null

    const previousSibling = siblings[currentIndex - 1]
    const targetTree = this.childTreeForBlock(previousSibling)
    if (!targetTree) return null

    return {
      targetParentId: previousSibling.dataset.blockId,
      targetIndex: this.directChildBlocks(targetTree).length
    }
  }

  outdentPlan() {
    const currentBlock = this.currentBlock()
    const currentTree = this.currentTree()
    const parentBlock = this.parentBlockForTree(currentTree)
    const targetTree = this.parentTreeForBlock(parentBlock)
    if (!currentBlock || !currentTree || !parentBlock || !targetTree) return null

    const targetSiblings = this.directChildBlocks(targetTree)
    const parentIndex = targetSiblings.indexOf(parentBlock)
    if (parentIndex < 0) return null

    return {
      targetParentId: targetTree.dataset.blockListParentIdValue || null,
      targetIndex: parentIndex + 1
    }
  }

  async persistReparent(plan) {
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    const response = await fetch(this.reorderUrl(), {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "text/vnd.turbo-stream.html",
        ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {})
      },
      credentials: "same-origin",
      body: JSON.stringify({
        target_parent_id: plan.targetParentId,
        target_index: plan.targetIndex
      })
    })

    if (!response.ok) throw new Error("Block nesting update failed")

    const stream = await response.text()
    if (stream && window.Turbo?.renderStreamMessage) {
      window.Turbo.renderStreamMessage(stream)
      return
    }

    window.location.reload()
  }

  async flushBlockSave() {
    const detail = { blockId: this.blockIdValue }
    window.dispatchEvent(new CustomEvent("notae:block-flush-save", { detail }))

    if (!detail.promise) return

    await detail.promise
  }

  reorderUrl() {
    const tree = this.currentTree()
    const workspaceSlug = tree?.dataset.blockListWorkspaceSlugValue
    const pageId = tree?.dataset.blockListPageIdValue
    if (!workspaceSlug || !pageId || !this.blockIdValue) return window.location.pathname

    return `/w/${workspaceSlug}/pages/${pageId}/blocks/${this.blockIdValue}/reorder`
  }

  focusEditor() {
    const editorSurface = document.querySelector(`#block_${this.blockIdValue} .ProseMirror`)
    if (!(editorSurface instanceof HTMLElement)) return

    requestAnimationFrame(() => editorSurface.focus())
  }

  currentBlock() {
    return this.element
  }

  currentTree() {
    return this.element.closest(".notae-doc-tree")
  }

  directChildBlocks(tree) {
    if (!tree) return []

    return Array.from(tree.children).filter((child) => child instanceof HTMLElement && child.hasAttribute("data-block-id"))
  }

  childTreeForBlock(block) {
    const childWrapper = Array.from(block?.children || []).find((child) => child.classList?.contains("notae-doc-children"))
    if (!childWrapper) return null

    return Array.from(childWrapper.children).find((child) => child.classList?.contains("notae-doc-tree")) || null
  }

  parentBlockForTree(tree) {
    return tree?.parentElement?.closest?.("[data-block-id]") || null
  }

  parentTreeForBlock(block) {
    return block?.parentElement?.closest?.(".notae-doc-tree") || null
  }
}
