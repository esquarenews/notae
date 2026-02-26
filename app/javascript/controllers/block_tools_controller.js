import { Controller } from "@hotwired/stimulus"

const MENU_VIEWPORT_MARGIN = 12

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
    if (!panel) return

    panel.style.setProperty("--notae-menu-shift-x", "0px")
    panel.style.setProperty("--notae-menu-shift-y", "0px")
    panel.style.visibility = "hidden"
    panel.style.pointerEvents = "none"

    const rect = panel.getBoundingClientRect()
    const maxX = window.innerWidth - MENU_VIEWPORT_MARGIN
    const maxY = window.innerHeight - MENU_VIEWPORT_MARGIN
    let shiftX = 0
    let shiftY = 0

    if (rect.right > maxX) {
      shiftX -= rect.right - maxX
    }
    if (rect.left + shiftX < MENU_VIEWPORT_MARGIN) {
      shiftX += MENU_VIEWPORT_MARGIN - (rect.left + shiftX)
    }

    if (rect.bottom > maxY) {
      shiftY -= rect.bottom - maxY
    }
    if (rect.top + shiftY < MENU_VIEWPORT_MARGIN) {
      shiftY += MENU_VIEWPORT_MARGIN - (rect.top + shiftY)
    }

    panel.style.setProperty("--notae-menu-shift-x", `${Math.round(shiftX)}px`)
    panel.style.setProperty("--notae-menu-shift-y", `${Math.round(shiftY)}px`)
    panel.style.visibility = ""
    panel.style.pointerEvents = ""
  }

  resetPanelPosition(details) {
    const panel = details.querySelector(".notae-block-menu-panel")
    if (!panel) return

    panel.style.setProperty("--notae-menu-shift-x", "0px")
    panel.style.setProperty("--notae-menu-shift-y", "0px")
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
