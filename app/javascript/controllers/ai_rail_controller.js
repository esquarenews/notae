import { Controller } from "@hotwired/stimulus"

const AGENT_UPDATE_POLL_INTERVAL_MS = 15000
const AGENT_UPDATE_TOAST_DURATION_MS = 10000
const AGENT_UPDATE_FOCUS_CLASS = "is-recently-focused"
const AGENT_UPDATE_FOCUS_DURATION_MS = 2200
const AI_RAIL_COLLAPSED_PREFERENCE_KEY = "notae-ai-rail-collapsed-v2"

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
    "insertPayload",
    "floatingToggle",
    "overlay",
    "agentUpdate",
    "agentToast",
    "agentToastBody"
  ]

  static values = {
    agentUpdatesPath: String,
    workspaceKey: String
  }

  connect() {
    this.shellElement = this.element.closest(".notae-shell")
    this.railViewportQuery = window.matchMedia("(max-width: 1180px)")
    this.visualViewport = window.visualViewport || null
    this.onRailViewportChange = () => this.handleRailViewportChange()
    this.prefillEventHandler = (event) => this.applyPrefill(event.detail || {})
    this.visibilityChangeHandler = () => {
      this.refreshAgentToastState()
      this.syncAgentUpdatePolling({ immediate: this.railActive() })
    }
    this.agentUpdateIds = new Set()
    this.agentToastTimer = null
    this.agentUpdatePollTimer = null
    this.agentUpdateFocusTimer = null
    this.agentUpdatePollRequest = null
    this.agentUpdateBooting = true

    if (typeof this.railViewportQuery.addEventListener === "function") {
      this.railViewportQuery.addEventListener("change", this.onRailViewportChange)
    } else {
      this.railViewportQuery.addListener(this.onRailViewportChange)
    }
    if (this.visualViewport && typeof this.visualViewport.addEventListener === "function") {
      this.visualViewport.addEventListener("resize", this.onRailViewportChange)
    }

    window.addEventListener("notae:ai-prefill", this.prefillEventHandler)
    document.addEventListener("visibilitychange", this.visibilityChangeHandler)

    this.restoreRailState()
    this.handleRailViewportChange()
    this.restoreUsageState()
    this.syncFloatingControls()
    this.applyPendingPrefill()
    this.applyPendingRailOpen()
    this.queueThreadScroll()
    this.applyInsertPayload()
    this.captureExistingAgentUpdates()
    this.refreshAgentToastState()
    this.startAgentUpdatePolling()
    this.agentUpdateBooting = false
    this.finishHydration()
  }

  disconnect() {
    if (this.railViewportQuery) {
      if (typeof this.railViewportQuery.removeEventListener === "function") {
        this.railViewportQuery.removeEventListener("change", this.onRailViewportChange)
      } else {
        this.railViewportQuery.removeListener(this.onRailViewportChange)
      }
    }
    if (this.visualViewport && typeof this.visualViewport.removeEventListener === "function") {
      this.visualViewport.removeEventListener("resize", this.onRailViewportChange)
    }

    window.removeEventListener("notae:ai-prefill", this.prefillEventHandler)
    document.removeEventListener("visibilitychange", this.visibilityChangeHandler)

    if (this.agentToastTimer) window.clearTimeout(this.agentToastTimer)
    if (this.agentUpdateFocusTimer) window.clearTimeout(this.agentUpdateFocusTimer)
    this.stopAgentUpdatePolling()
    if (this.shellElement) {
      this.shellElement.classList.remove("is-ai-compact-viewport")
      this.shellElement.classList.remove("is-layout-hydrating")
    }
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

    if (this.compactViewport()) {
      this.setOverlayOpen(!this.overlayOpen())
      return
    }

    this.setRailCollapsed(!this.railCollapsed())
  }

  toggleFloatingRail(event) {
    event.preventDefault()
    this.setOverlayOpen(!this.overlayOpen())
  }

  closeFloatingRail(event) {
    event.preventDefault()
    this.setOverlayOpen(false)
  }

  openAgentToast(event) {
    event.preventDefault()
    const targetUpdateId = this.latestUnseenAgentUpdateElement()?.dataset.aiAgentUpdateId || ""

    if (this.compactViewport()) {
      this.setOverlayOpen(true)
    } else {
      this.setRailCollapsed(false)
    }

    this.markAgentUpdatesSeen()
    this.clearDismissedAgentUpdateCursor()
    this.hideAgentToast()
    this.queueAgentUpdateFocus(targetUpdateId)
  }

  dismissAgentToast(event) {
    event.preventDefault()
    this.dismissCurrentAgentToast()
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

  overlayOpen() {
    if (!this.shellElement) return false

    return this.shellElement.classList.contains("is-ai-rail-overlay-open")
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
    this.setPreference(AI_RAIL_COLLAPSED_PREFERENCE_KEY, collapsed)
    this.notifyLayoutChange()
    this.refreshAgentToastState()
    this.syncAgentUpdatePolling({ immediate: !collapsed && !this.compactViewport() })
  }

  setOverlayOpen(open) {
    if (!this.shellElement) return

    this.shellElement.classList.toggle("is-ai-rail-overlay-open", open)
    this.syncFloatingControls()
    this.notifyLayoutChange()
    this.refreshAgentToastState()
    this.syncAgentUpdatePolling({ immediate: open })
  }

  restoreRailState() {
    this.setRailCollapsed(this.preference(AI_RAIL_COLLAPSED_PREFERENCE_KEY, false))
  }

  restoreUsageState() {
    this.setUsageExpanded(this.preference("notae-ai-usage-expanded"))
  }

  preference(key, fallback = false) {
    try {
      const value = window.localStorage.getItem(key)
      if (value === null) return fallback
      return value === "true"
    } catch (_error) {
      return fallback
    }
  }

  stringPreference(key, fallback = "") {
    try {
      const value = window.localStorage.getItem(key)
      return value === null ? fallback : value
    } catch (_error) {
      return fallback
    }
  }

  setPreference(key, value) {
    this.setStringPreference(key, value ? "true" : "false")
  }

  setStringPreference(key, value) {
    try {
      if (value === null || value === undefined || value === "") {
        window.localStorage.removeItem(key)
      } else {
        window.localStorage.setItem(key, String(value))
      }
    } catch (_error) {
      // no-op if storage is unavailable
    }
  }

  applyPrefill(detail) {
    if (!this.hasPromptInputTarget) return

    if (detail.clearPrompt) {
      this.promptInputTarget.value = ""
      this.promptInputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    }

    const prompt = String(detail.prompt || "").trim()
    if (prompt.length > 0) {
      this.promptInputTarget.value = prompt
      this.promptInputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    }

    if (this.hasIntentInputTarget) this.intentInputTarget.value = String(detail.intent || "")
    if (this.hasTargetBlockInputTarget) this.targetBlockInputTarget.value = String(detail.targetBlockId || "")

    if (this.compactViewport()) {
      this.setOverlayOpen(true)
    } else {
      this.setRailCollapsed(false)
    }
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

  applyPendingPrefill() {
    const detail = window.notaeAiRailPendingPrefill
    if (!detail) return

    delete window.notaeAiRailPendingPrefill
    this.applyPrefill(detail)
  }

  applyPendingRailOpen() {
    if (window.notaeAiRailPendingPrefill) return

    const pendingMode = window.notaeAiRailPendingOpen
    if (!pendingMode) return

    delete window.notaeAiRailPendingOpen

    if (this.compactViewport() || pendingMode === "overlay") {
      this.setOverlayOpen(true)
      return
    }

    this.setRailCollapsed(false)
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

  handleRailViewportChange() {
    const compact = this.compactViewport()
    if (this.shellElement) this.shellElement.classList.toggle("is-ai-compact-viewport", compact)

    if (!compact) {
      this.setOverlayOpen(false)
      this.restoreRailState()
      return
    }

    this.syncFloatingControls()
    this.refreshAgentToastState()
    this.syncAgentUpdatePolling({ immediate: this.railActive() })
  }

  compactViewport() {
    const width = this.viewportWidth()
    if (typeof width === "number") return width <= 1180
    if (this.railViewportQuery) return this.railViewportQuery.matches

    return window.innerWidth <= 1180
  }

  viewportWidth() {
    const visualWidth = this.visualViewport?.width
    if (typeof visualWidth === "number" && visualWidth > 0) return visualWidth
    if (typeof window.innerWidth === "number" && window.innerWidth > 0) return window.innerWidth

    return null
  }

  syncFloatingControls() {
    const expanded = this.overlayOpen()
    if (this.hasFloatingToggleTarget) {
      this.floatingToggleTarget.setAttribute("aria-expanded", expanded ? "true" : "false")
    }
    if (this.hasOverlayTarget) {
      this.overlayTarget.hidden = !expanded
    }
  }

  finishHydration() {
    if (!this.shellElement) return

    window.requestAnimationFrame(() => {
      window.requestAnimationFrame(() => {
        this.shellElement.classList.remove("is-layout-hydrating")
      })
    })
  }

  captureExistingAgentUpdates() {
    this.agentUpdateElements().forEach((element) => {
      const updateId = element.dataset.aiAgentUpdateId
      if (updateId) this.agentUpdateIds.add(updateId)
    })
  }

  agentUpdateElements() {
    return this.agentUpdateTargets || []
  }

  railVisible() {
    if (this.compactViewport()) return this.overlayOpen()

    return !this.railCollapsed()
  }

  railActive() {
    return document.visibilityState === "visible" && this.railVisible()
  }

  refreshAgentToastState() {
    if (!this.hasAgentToastTarget) return

    if (this.statusBarAvailable()) {
      this.hideAgentToast()
      return
    }

    if (this.railActive()) {
      this.markAgentUpdatesSeen()
      this.hideAgentToast()
      return
    }

    const unseenCount = this.unseenAgentUpdateCount()
    const latestCursor = this.latestAgentUpdateCursor()
    if (unseenCount < 1 || !latestCursor || latestCursor <= this.dismissedAgentUpdateCursor()) {
      this.hideAgentToast()
      return
    }

    this.showAgentToast(unseenCount)
  }

  latestAgentUpdateCursor() {
    let latest = this.lastSeenAgentUpdateCursor()

    this.agentUpdateElements().forEach((element) => {
      const updatedAt = element.dataset.aiAgentUpdateUpdatedAt || ""
      if (updatedAt > latest) latest = updatedAt
    })

    return latest
  }

  latestUnseenAgentUpdateElement() {
    const lastSeen = this.lastSeenAgentUpdateCursor()
    let newestElement = null

    this.agentUpdateElements().forEach((element) => {
      const updatedAt = element.dataset.aiAgentUpdateUpdatedAt || ""
      if (!updatedAt || updatedAt <= lastSeen) return

      if (!newestElement) {
        newestElement = element
        return
      }

      const newestUpdatedAt = newestElement.dataset.aiAgentUpdateUpdatedAt || ""
      if (updatedAt >= newestUpdatedAt) newestElement = element
    })

    return newestElement
  }

  unseenAgentUpdateCount() {
    const lastSeen = this.lastSeenAgentUpdateCursor()

    return this.agentUpdateElements().filter((element) => {
      const updatedAt = element.dataset.aiAgentUpdateUpdatedAt || ""
      return updatedAt && updatedAt > lastSeen
    }).length
  }

  markAgentUpdatesSeen() {
    const latestCursor = this.latestAgentUpdateCursor()
    if (!latestCursor) return

    if (latestCursor > this.lastSeenAgentUpdateCursor()) {
      this.setStringPreference(this.agentLastSeenPreferenceKey(), latestCursor)
    }
    this.clearDismissedAgentUpdateCursor()
  }

  showAgentToast(count) {
    if (!this.hasAgentToastTarget || !this.hasAgentToastBodyTarget) return

    const pluralized = count === 1 ? "message" : "messages"
    this.agentToastBodyTarget.textContent = `you have ${count} new ${pluralized} from the AI Agent`
    this.agentToastTarget.hidden = false

    if (this.agentToastTimer) window.clearTimeout(this.agentToastTimer)
    this.agentToastTimer = window.setTimeout(() => {
      this.dismissCurrentAgentToast()
    }, AGENT_UPDATE_TOAST_DURATION_MS)
  }

  hideAgentToast() {
    if (!this.hasAgentToastTarget) return

    this.agentToastTarget.hidden = true
    if (this.agentToastTimer) {
      window.clearTimeout(this.agentToastTimer)
      this.agentToastTimer = null
    }
  }

  dismissCurrentAgentToast() {
    const latestCursor = this.latestAgentUpdateCursor()
    if (latestCursor) {
      this.setStringPreference(this.agentDismissedPreferenceKey(), latestCursor)
    }
    this.hideAgentToast()
  }

  clearDismissedAgentUpdateCursor() {
    this.setStringPreference(this.agentDismissedPreferenceKey(), "")
  }

  lastSeenAgentUpdateCursor() {
    return this.stringPreference(this.agentLastSeenPreferenceKey(), "")
  }

  dismissedAgentUpdateCursor() {
    return this.stringPreference(this.agentDismissedPreferenceKey(), "")
  }

  agentLastSeenPreferenceKey() {
    return `notae-ai-agent-last-seen:${this.workspaceScopeKey()}`
  }

  agentDismissedPreferenceKey() {
    return `notae-ai-agent-dismissed:${this.workspaceScopeKey()}`
  }

  workspaceScopeKey() {
    return this.hasWorkspaceKeyValue && this.workspaceKeyValue ? this.workspaceKeyValue : "global"
  }

  statusBarAvailable() {
    return document.querySelector(".notae-shell-status-bar") !== null
  }

  startAgentUpdatePolling() {
    if (!this.hasAgentUpdatesPathValue || !this.agentUpdatesPathValue) return
    this.syncAgentUpdatePolling()
  }

  async pollAgentUpdates({ force = false } = {}) {
    if (!this.hasAgentUpdatesPathValue || !this.agentUpdatesPathValue) return
    if (!this.railActive()) return
    if (!force && this.agentUpdatePollRequest) return this.agentUpdatePollRequest

    this.agentUpdatePollRequest = (async () => {
      try {
        const requestUrl = new URL(this.agentUpdatesPathValue, window.location.origin)
        const cursor = this.latestAgentUpdateCursor()
        if (cursor) requestUrl.searchParams.set("since", cursor)

        const response = await fetch(requestUrl.toString(), {
          headers: {
            Accept: "application/json",
            "X-Requested-With": "XMLHttpRequest"
          },
          credentials: "same-origin"
        })
        if (!response.ok) return

        const payload = await response.json()
        const html = payload?.data?.html?.toString() || ""
        if (!html.trim()) return

        const mutationCount = this.insertAgentUpdateHtml(html)
        if (mutationCount > 0) {
          this.queueThreadScroll()
          this.refreshAgentToastState()
        }
      } catch (_error) {
        // silent polling failure
      } finally {
        this.agentUpdatePollRequest = null
      }
    })()

    return this.agentUpdatePollRequest
  }

  syncAgentUpdatePolling({ immediate = false } = {}) {
    if (!this.hasAgentUpdatesPathValue || !this.agentUpdatesPathValue) {
      this.stopAgentUpdatePolling()
      return
    }

    if (!this.railActive()) {
      this.stopAgentUpdatePolling()
      return
    }

    if (!this.agentUpdatePollTimer) {
      this.agentUpdatePollTimer = window.setInterval(() => {
        this.pollAgentUpdates()
      }, AGENT_UPDATE_POLL_INTERVAL_MS)
    }

    const shouldPollImmediately = immediate && !this.agentUpdateBooting
    if (shouldPollImmediately) this.pollAgentUpdates()
  }

  stopAgentUpdatePolling() {
    if (!this.agentUpdatePollTimer) return

    window.clearInterval(this.agentUpdatePollTimer)
    this.agentUpdatePollTimer = null
  }

  insertAgentUpdateHtml(html) {
    if (!this.hasThreadTarget) return 0

    const template = document.createElement("template")
    template.innerHTML = html.trim()
    const elements = Array.from(template.content.children)
    let mutationCount = 0

    elements.forEach((element) => {
      const updateId = element.dataset.aiAgentUpdateId
      if (!updateId) return

      const existing = this.findAgentUpdateElement(updateId)
      if (existing) {
        existing.remove()
        this.insertTimelineElement(element)
      } else {
        this.insertTimelineElement(element)
        this.agentUpdateIds.add(updateId)
      }
      mutationCount += 1
    })

    return mutationCount
  }

  findAgentUpdateElement(updateId) {
    return this.agentUpdateElements().find((element) => element.dataset.aiAgentUpdateId === updateId) || null
  }

  insertTimelineElement(element) {
    if (!this.hasThreadTarget) return

    const newTimestamp = element.dataset.aiTimelineAt || ""
    const insertionPoint = this.timelineEntryElements().find((entry) => {
      const existingTimestamp = entry.dataset.aiTimelineAt || ""
      return existingTimestamp && newTimestamp && existingTimestamp > newTimestamp
    })

    if (insertionPoint) {
      this.threadTarget.insertBefore(element, insertionPoint)
    } else {
      this.threadTarget.appendChild(element)
    }
  }

  timelineEntryElements() {
    if (!this.hasThreadTarget) return []

    return Array.from(this.threadTarget.querySelectorAll(".notae-ai-thread-entry"))
  }

  queueAgentUpdateFocus(updateId) {
    if (!updateId) return

    window.requestAnimationFrame(() => {
      this.scrollAgentUpdateIntoView(updateId)
      window.requestAnimationFrame(() => this.scrollAgentUpdateIntoView(updateId))
    })
  }

  scrollAgentUpdateIntoView(updateId) {
    if (!updateId) return

    const target = this.findAgentUpdateElement(updateId)
    if (!target) return

    target.scrollIntoView({ behavior: "smooth", block: "center", inline: "nearest" })
    this.highlightAgentUpdate(target)
  }

  highlightAgentUpdate(element) {
    this.agentUpdateElements().forEach((entry) => entry.classList.remove(AGENT_UPDATE_FOCUS_CLASS))
    element.classList.add(AGENT_UPDATE_FOCUS_CLASS)

    if (this.agentUpdateFocusTimer) window.clearTimeout(this.agentUpdateFocusTimer)
    this.agentUpdateFocusTimer = window.setTimeout(() => {
      element.classList.remove(AGENT_UPDATE_FOCUS_CLASS)
      this.agentUpdateFocusTimer = null
    }, AGENT_UPDATE_FOCUS_DURATION_MS)
  }

  notifyLayoutChange() {
    window.requestAnimationFrame(() => {
      window.dispatchEvent(new Event("notae:layout-changed"))
    })
  }
}
