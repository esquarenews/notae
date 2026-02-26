import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "promptInput",
    "thread",
    "loading",
    "submitButton",
    "usageToggle",
    "usageDrawer",
    "intentInput",
    "targetBlockInput",
    "insertPayload"
  ]

  connect() {
    this.shellElement = this.element.closest(".notae-shell")
    this.prefillEventHandler = (event) => this.applyPrefill(event.detail || {})
    window.addEventListener("notae:ai-prefill", this.prefillEventHandler)
    this.restoreRailState()
    this.restoreUsageState()
    this.queueThreadScroll()
    this.applyInsertPayload()
  }

  disconnect() {
    window.removeEventListener("notae:ai-prefill", this.prefillEventHandler)
  }

  async copyResult(event) {
    event.preventDefault()

    const messageElement = event.currentTarget.closest(".notae-ai-message")
    const textElement = messageElement?.querySelector(".notae-ai-result-text")
    const text = textElement?.textContent?.trim()
    if (!text) return

    try {
      await navigator.clipboard.writeText(text)
      event.currentTarget.textContent = "Copied"
      setTimeout(() => {
        event.currentTarget.textContent = "Copy result"
      }, 1200)
    } catch (_error) {
      this.copyFallback(text)
      event.currentTarget.textContent = "Copied"
      setTimeout(() => {
        event.currentTarget.textContent = "Copy result"
      }, 1200)
    }
  }

  copyFallback(text) {
    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.setAttribute("readonly", "readonly")
    textarea.style.position = "absolute"
    textarea.style.left = "-9999px"
    document.body.appendChild(textarea)
    textarea.select()
    document.execCommand("copy")
    document.body.removeChild(textarea)
  }

  submitStart(event) {
    const form = event.target
    if (!(form instanceof HTMLFormElement)) return

    this.capturePendingInsertion()

    const prompt = this.hasPromptInputTarget ? this.promptInputTarget.value.trim() : ""
    if (prompt.length > 0) {
      this.appendPendingUserMessage(prompt)
      this.promptInputTarget.value = ""
    }
    this.resetAssistantInputs()

    if (this.hasPromptInputTarget) this.promptInputTarget.setAttribute("disabled", "disabled")
    if (this.hasSubmitButtonTarget) this.submitButtonTarget.setAttribute("disabled", "disabled")

    form.classList.add("is-loading")
    if (this.hasLoadingTarget) this.loadingTarget.classList.remove("is-fading")
  }

  submitOnShortcut(event) {
    if (event.isComposing) return
    if (event.key !== "Enter") return
    if (!(event.metaKey || event.ctrlKey)) return

    event.preventDefault()

    const form = event.target?.form
    if (!(form instanceof HTMLFormElement)) return

    if (this.hasSubmitButtonTarget) {
      form.requestSubmit(this.submitButtonTarget)
    } else {
      form.requestSubmit()
    }
  }

  submitEnd(event) {
    const form = event.target
    if (!(form instanceof HTMLFormElement)) return

    if (this.hasPromptInputTarget) this.promptInputTarget.removeAttribute("disabled")
    if (this.hasSubmitButtonTarget) this.submitButtonTarget.removeAttribute("disabled")

    if (this.hasLoadingTarget) this.loadingTarget.classList.add("is-fading")
    window.setTimeout(() => {
      form.classList.remove("is-loading")
      this.queueThreadScroll()
    }, 220)
  }

  toggleUsage(event) {
    event.preventDefault()
    this.setUsageExpanded(!this.usageExpanded())
  }

  closeUsage(event) {
    event.preventDefault()
    this.setUsageExpanded(false)
  }

  toggleRail(event) {
    event.preventDefault()
    this.setRailCollapsed(!this.railCollapsed())
  }

  appendPendingUserMessage(text) {
    if (!this.hasThreadTarget) return

    const wrapper = document.createElement("article")
    wrapper.className = "notae-ai-message is-user is-pending is-compact"
    wrapper.innerHTML = `
      <p class="notae-ai-message-body"></p>
    `
    wrapper.querySelector(".notae-ai-message-body").textContent = text
    this.threadTarget.appendChild(wrapper)
    this.scrollThreadToBottom()
  }

  queueThreadScroll() {
    if (!this.hasThreadTarget) return

    window.requestAnimationFrame(() => {
      this.scrollThreadToBottom()
      window.requestAnimationFrame(() => this.scrollThreadToBottom())
    })
  }

  scrollThreadToBottom() {
    if (!this.hasThreadTarget) return

    this.threadTarget.scrollTop = this.threadTarget.scrollHeight
  }

  usageExpanded() {
    if (!this.hasUsageToggleTarget) return false

    return this.usageToggleTarget.getAttribute("aria-expanded") === "true"
  }

  railCollapsed() {
    if (!this.shellElement) return false

    return this.shellElement.classList.contains("is-ai-rail-collapsed")
  }

  setUsageExpanded(expanded) {
    if (!this.hasUsageToggleTarget || !this.hasUsageDrawerTarget) return

    this.usageToggleTarget.setAttribute("aria-expanded", expanded ? "true" : "false")
    this.usageDrawerTarget.hidden = !expanded
    this.setPreference("notae-ai-usage-expanded", expanded)
  }

  setRailCollapsed(collapsed) {
    if (!this.shellElement) return

    this.shellElement.classList.toggle("is-ai-rail-collapsed", collapsed)
    this.setPreference("notae-ai-rail-collapsed", collapsed)
  }

  restoreRailState() {
    this.setRailCollapsed(this.preference("notae-ai-rail-collapsed"))
  }

  restoreUsageState() {
    this.setUsageExpanded(this.preference("notae-ai-usage-expanded"))
  }

  preference(key) {
    try {
      return window.localStorage.getItem(key) === "true"
    } catch (_error) {
      return false
    }
  }

  setPreference(key, value) {
    try {
      window.localStorage.setItem(key, value ? "true" : "false")
    } catch (_error) {
      // no-op if storage is unavailable
    }
  }

  applyPrefill(detail) {
    if (!this.hasPromptInputTarget) return

    const prompt = String(detail.prompt || "").trim()
    if (prompt.length > 0) {
      this.promptInputTarget.value = prompt
      this.promptInputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    }

    if (this.hasIntentInputTarget) this.intentInputTarget.value = String(detail.intent || "")
    if (this.hasTargetBlockInputTarget) this.targetBlockInputTarget.value = String(detail.targetBlockId || "")

    this.setRailCollapsed(false)
    this.promptInputTarget.focus()

    if (detail.autoSubmit) {
      const form = this.promptInputTarget.form
      if (form instanceof HTMLFormElement) {
        if (this.hasSubmitButtonTarget) {
          form.requestSubmit(this.submitButtonTarget)
        } else {
          form.requestSubmit()
        }
      }
    }
  }

  capturePendingInsertion() {
    const sourceInsertion = window.notaeAiInsertionPoint
    const insertionPoint = sourceInsertion ? { ...sourceInsertion } : null
    const targetBlockId = this.hasTargetBlockInputTarget ? this.targetBlockInputTarget.value : ""

    window.notaeAiPendingInsertion = {
      insertionPoint,
      targetBlockId: String(targetBlockId || ""),
      requestedAt: Date.now()
    }
  }

  resetAssistantInputs() {
    if (this.hasIntentInputTarget) this.intentInputTarget.value = ""
    if (this.hasTargetBlockInputTarget) this.targetBlockInputTarget.value = ""
  }

  applyInsertPayload() {
    if (!this.hasInsertPayloadTarget) return

    const text = this.insertPayloadTarget.dataset.aiInsertText?.trim()
    if (!text) return

    const pending = window.notaeAiPendingInsertion || {}
    const payloadTargetBlockId = this.insertPayloadTarget.dataset.aiInsertTargetBlockId || ""
    const targetBlockId = payloadTargetBlockId || pending.targetBlockId || ""
    const insertionPoint = pending.insertionPoint || window.notaeAiInsertionPoint || null

    const detail = {
      text,
      targetBlockId: targetBlockId || null,
      insertionPoint: insertionPoint ? { ...insertionPoint } : null,
      inserted: false
    }
    window.dispatchEvent(new CustomEvent("notae:ai-insert", { detail }))

    delete window.notaeAiPendingInsertion
    this.insertPayloadTarget.remove()
  }
}
