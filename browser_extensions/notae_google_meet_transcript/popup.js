(async () => {
  const baseUrlInput = document.getElementById("baseUrl")
  const workspaceSlugInput = document.getElementById("workspaceSlug")
  const apiTokenInput = document.getElementById("apiToken")
  const pasteTokenButton = document.getElementById("pasteTokenButton")
  const detectedWorkspaceButton = document.getElementById("detectedWorkspaceButton")
  const detectedWorkspaceHint = document.getElementById("detectedWorkspaceHint")
  const saveButton = document.getElementById("saveButton")
  const startButton = document.getElementById("startButton")
  const stopButton = document.getElementById("stopButton")
  const openNotaButton = document.getElementById("openNotaButton")
  const statusMessage = document.getElementById("statusMessage")
  const tabState = document.getElementById("tabState")

  let activeTabId = null
  let currentState = null
  let appliedDetectedWorkspace = false

  function setStatus(message, tone = "") {
    statusMessage.textContent = message
    statusMessage.className = tone ? `status ${tone}` : "status"
  }

  function normalizedSettings() {
    return {
      baseUrl: baseUrlInput.value.trim().replace(/\/+$/, ""),
      workspaceSlug: workspaceSlugInput.value.trim(),
      apiToken: apiTokenInput.value.trim()
    }
  }

  function hasRequiredSettings() {
    const settings = normalizedSettings()
    return settings.baseUrl.length > 0 && settings.workspaceSlug.length > 0 && settings.apiToken.length > 0
  }

  function localhostUrl(value) {
    try {
      const url = new URL(value)
      return ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname)
    } catch (_error) {
      return false
    }
  }

  function applyDetectedWorkspace(workspace, { preserveToken = true } = {}) {
    if (!workspace) return

    baseUrlInput.value = workspace.baseUrl || ""
    workspaceSlugInput.value = workspace.workspaceSlug || ""
    if (!preserveToken) apiTokenInput.value = ""
  }

  function renderDetectedWorkspace(workspace) {
    const hasWorkspace = Boolean(workspace?.baseUrl && workspace?.workspaceSlug)
    detectedWorkspaceButton.classList.toggle("hidden", !hasWorkspace)
    detectedWorkspaceHint.classList.toggle("hidden", !hasWorkspace)

    if (!hasWorkspace) {
      detectedWorkspaceHint.textContent = ""
      return
    }

    detectedWorkspaceButton.textContent = `Use ${workspace.workspaceSlug}`
    detectedWorkspaceHint.textContent = `Detected Notae workspace: ${workspace.workspaceSlug} @ ${workspace.baseUrl}`
  }

  function shouldAutoApplyDetectedWorkspace(savedSettings, detectedWorkspace) {
    if (!detectedWorkspace?.baseUrl || !detectedWorkspace?.workspaceSlug) return false
    if (appliedDetectedWorkspace) return false

    if (!savedSettings.baseUrl || !savedSettings.workspaceSlug) return true
    if (localhostUrl(savedSettings.baseUrl) && !localhostUrl(detectedWorkspace.baseUrl)) return true

    return false
  }

  function renderState(payload) {
    currentState = payload
    activeTabId = payload.tabId

    baseUrlInput.value = payload.settings.baseUrl || ""
    workspaceSlugInput.value = payload.settings.workspaceSlug || ""
    apiTokenInput.value = payload.settings.apiToken || ""
    renderDetectedWorkspace(payload.detectedWorkspace)

    if (shouldAutoApplyDetectedWorkspace(payload.settings, payload.detectedWorkspace)) {
      applyDetectedWorkspace(payload.detectedWorkspace)
      appliedDetectedWorkspace = true
    }

    tabState.classList.toggle("hidden", false)
    tabState.textContent = payload.isMeetTab ? "Google Meet tab detected" : "Open a Google Meet tab to capture"

    const capture = payload.capture
    const hasActiveCapture = Boolean(capture)
    const hasStopAction = Boolean(capture && (capture.capturing || capture.uploading || capture.lastError))
    const canStart = payload.isMeetTab && hasRequiredSettings() && (!hasActiveCapture || !capture.capturing)
    const canStop = hasStopAction

    startButton.disabled = !canStart
    stopButton.disabled = !canStop
    stopButton.classList.toggle("hidden", !hasStopAction)
    openNotaButton.classList.toggle("hidden", !capture || !capture.pageUrl)

    if (capture?.lastError) {
      setStatus(capture.lastError, "is-error")
      return
    }

    if (capture?.uploading) {
      setStatus("Uploading transcript to Notae...")
      return
    }

    if (capture?.capturing) {
      const utteranceCount = Array.isArray(capture.utterances) ? capture.utterances.length : 0
      setStatus(`Capturing transcript${utteranceCount > 0 ? ` (${utteranceCount} lines)` : ""}...`)
      return
    }

    if (capture?.pageUrl) {
      setStatus("Transcript synced to Notae.", "is-success")
      return
    }

    if (!payload.isMeetTab) {
      setStatus("Open Google Meet in this browser tab to use the extension.")
      return
    }

    if (!hasRequiredSettings()) {
      setStatus("Save your Notae base URL, workspace slug, and extension token first.")
      return
    }

    setStatus("Ready.")
  }

  async function refreshState() {
    const payload = await chrome.runtime.sendMessage({ type: "notae-meet-popup-state" })
    renderState(payload)
  }

  saveButton.addEventListener("click", async () => {
    const settings = normalizedSettings()
    if (!settings.baseUrl || !settings.workspaceSlug || !settings.apiToken) {
      setStatus("All settings are required before you can capture.", "is-error")
      return
    }

    await chrome.runtime.sendMessage({ type: "notae-meet-save-settings", settings })
    setStatus("Settings saved.", "is-success")
    await refreshState()
  })

  detectedWorkspaceButton.addEventListener("click", async () => {
    const response = await chrome.runtime.sendMessage({ type: "notae-meet-detected-workspace" })
    const workspace = response?.detectedWorkspace

    if (!workspace?.baseUrl || !workspace?.workspaceSlug) {
      setStatus("No Notae workspace tab was detected in this browser window.", "is-error")
      renderDetectedWorkspace(null)
      return
    }

    applyDetectedWorkspace(workspace)
    renderDetectedWorkspace(workspace)
    setStatus("Filled base URL and workspace from the detected Notae tab.", "is-success")
  })

  pasteTokenButton.addEventListener("click", async () => {
    if (!navigator.clipboard?.readText) {
      setStatus("Clipboard paste is not available here. Paste the token manually into the field.", "is-error")
      apiTokenInput.focus()
      return
    }

    try {
      const clipboardText = (await navigator.clipboard.readText()).trim()
      if (!clipboardText) {
        setStatus("Clipboard is empty.", "is-error")
        return
      }

      apiTokenInput.value = clipboardText
      apiTokenInput.focus()
      apiTokenInput.select()
      setStatus("Token pasted from clipboard.", "is-success")
    } catch (_error) {
      setStatus("Clipboard access was blocked. Paste the token manually into the field.", "is-error")
      apiTokenInput.focus()
    }
  })

  startButton.addEventListener("click", async () => {
    if (!activeTabId) {
      setStatus("No active tab available.", "is-error")
      return
    }

    const settings = normalizedSettings()
    if (!settings.baseUrl || !settings.workspaceSlug || !settings.apiToken) {
      setStatus("All settings are required before you can capture.", "is-error")
      return
    }

    const response = await chrome.runtime.sendMessage({
      type: "notae-meet-start-capture",
      tabId: activeTabId,
      settings
    })

    if (!response.ok) {
      setStatus(response.error || "Failed to start capture.", "is-error")
      return
    }

    setStatus("Capture started. Keep captions enabled in Google Meet.")
    await refreshState()
  })

  stopButton.addEventListener("click", async () => {
    if (!activeTabId) {
      setStatus("No active tab available.", "is-error")
      return
    }

    setStatus("Stopping capture and syncing transcript...")
    const response = await chrome.runtime.sendMessage({
      type: "notae-meet-stop-capture",
      tabId: activeTabId
    })

    if (!response.ok) {
      setStatus(response.error || "Failed to sync transcript.", "is-error")
      await refreshState()
      return
    }

    await refreshState()
  })

  openNotaButton.addEventListener("click", async () => {
    const pageUrl = currentState?.capture?.pageUrl
    if (!pageUrl) return

    await chrome.runtime.sendMessage({ type: "notae-meet-open-page", url: pageUrl })
  })

  await refreshState()
})()
