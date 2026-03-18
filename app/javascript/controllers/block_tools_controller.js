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
    this.repositionOpenMenuHandler = () => this.repositionOpenMenu()
    window.addEventListener("resize", this.repositionOpenMenuHandler)
    window.addEventListener("scroll", this.repositionOpenMenuHandler, true)
  }

  disconnect() {
    window.removeEventListener("resize", this.repositionOpenMenuHandler)
    window.removeEventListener("scroll", this.repositionOpenMenuHandler, true)
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

  closeMenu(event) {
    const details = event.currentTarget.closest("details")
    if (details) {
      details.open = false
      this.resetPanelPosition(details)
    }
  }

  positionMenu(event) {
    const details = event.currentTarget
    if (!details || !details.open) {
      if (details) this.resetPanelPosition(details)
      return
    }

    this.applyPanelPosition(details)
  }

  repositionOpenMenu() {
    const details = this.element.querySelector(".notae-block-menu[open]")
    if (!details) return

    this.applyPanelPosition(details)
  }

  applyPanelPosition(details) {
    const panel = details.querySelector(".notae-block-menu-panel")
    const trigger = details.querySelector(".notae-block-menu-trigger")
    if (!panel || !trigger) return

    panel.classList.add("is-viewport-positioned")
    panel.style.setProperty("--notae-menu-left", `${MENU_VIEWPORT_MARGIN}px`)
    panel.style.setProperty("--notae-menu-top", `${MENU_VIEWPORT_MARGIN}px`)
    panel.style.setProperty("--notae-menu-max-height", `${Math.max(160, window.innerHeight - MENU_VIEWPORT_MARGIN * 2)}px`)
    panel.style.visibility = "hidden"
    panel.style.pointerEvents = "none"

    const placement = this.computeViewportPlacement(trigger.getBoundingClientRect(), panel.getBoundingClientRect())
    panel.style.setProperty("--notae-menu-left", `${Math.round(placement.left)}px`)
    panel.style.setProperty("--notae-menu-top", `${Math.round(placement.top)}px`)
    panel.style.setProperty("--notae-menu-max-height", `${Math.round(placement.maxHeight)}px`)
    panel.style.visibility = ""
    panel.style.pointerEvents = ""
  }

  computeViewportPlacement(triggerRect, panelRect) {
    const viewportWidth = Math.max(window.innerWidth || 0, 0)
    const viewportHeight = Math.max(window.innerHeight || 0, 0)
    const maxHeight = Math.max(160, viewportHeight - MENU_VIEWPORT_MARGIN * 2)
    const panelWidth = Math.min(Math.max(panelRect.width || 0, 0), Math.max(0, viewportWidth - MENU_VIEWPORT_MARGIN * 2))
    const panelHeight = Math.min(Math.max(panelRect.height || 0, 0), maxHeight)

    let left = triggerRect.right - panelWidth
    left = Math.min(left, viewportWidth - MENU_VIEWPORT_MARGIN - panelWidth)
    left = Math.max(MENU_VIEWPORT_MARGIN, left)

    let top = triggerRect.bottom + MENU_TRIGGER_GAP
    if (top + panelHeight > viewportHeight - MENU_VIEWPORT_MARGIN) {
      top = triggerRect.top - MENU_TRIGGER_GAP - panelHeight
    }
    top = Math.min(top, viewportHeight - MENU_VIEWPORT_MARGIN - panelHeight)
    top = Math.max(MENU_VIEWPORT_MARGIN, top)

    return { left, top, maxHeight }
  }

  resetPanelPosition(details) {
    const panel = details.querySelector(".notae-block-menu-panel")
    if (!panel) return

    panel.classList.remove("is-viewport-positioned")
    panel.style.removeProperty("--notae-menu-left")
    panel.style.removeProperty("--notae-menu-top")
    panel.style.removeProperty("--notae-menu-max-height")
    panel.style.visibility = ""
    panel.style.pointerEvents = ""
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
}
