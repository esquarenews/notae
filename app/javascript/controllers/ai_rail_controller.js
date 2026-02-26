import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["promptInput", "thread", "loading", "submitButton", "usageToggle", "usageDrawer"]

  connect() {
    this.shellElement = this.element.closest(".notae-shell")
    this.restoreRailState()
    this.restoreUsageState()
    this.queueThreadScroll()
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

    const prompt = this.hasPromptInputTarget ? this.promptInputTarget.value.trim() : ""
    if (prompt.length > 0) {
      this.appendPendingUserMessage(prompt)
      this.promptInputTarget.value = ""
    }

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
}
