const SETTINGS_KEY = "notaeMeetSettings"
const CAPTURES_KEY = "notaeMeetCaptures"
const EXTENSION_VERSION = "0.1.0"
const SESSION_CREATE_RETRY_MS = 10_000

function meetTabUrl(url) {
  return typeof url === "string" && url.startsWith("https://meet.google.com/")
}

function workspaceContextFromUrl(urlString) {
  if (typeof urlString !== "string" || urlString.trim().length === 0) return null

  try {
    const url = new URL(urlString)
    const match = url.pathname.match(/^\/w\/([^/]+)(?:\/|$)/)
    if (!match) return null

    return {
      baseUrl: url.origin.replace(/\/+$/, ""),
      workspaceSlug: decodeURIComponent(match[1]),
      workspaceUrl: `${url.origin}/w/${match[1]}`
    }
  } catch (_error) {
    return null
  }
}

function normalizedSettings(settings = {}) {
  return {
    baseUrl: String(settings.baseUrl || "").trim().replace(/\/+$/, ""),
    workspaceSlug: String(settings.workspaceSlug || "").trim(),
    apiToken: String(settings.apiToken || "").trim()
  }
}

async function getSettings() {
  const stored = await chrome.storage.local.get(SETTINGS_KEY)
  return normalizedSettings(stored[SETTINGS_KEY] || {})
}

async function saveSettings(settings) {
  await chrome.storage.local.set({ [SETTINGS_KEY]: normalizedSettings(settings) })
}

async function getCaptures() {
  const stored = await chrome.storage.session.get(CAPTURES_KEY)
  return stored[CAPTURES_KEY] || {}
}

async function getCapture(tabId) {
  const captures = await getCaptures()
  return captures[String(tabId)] || null
}

async function setCapture(tabId, capture) {
  const captures = await getCaptures()
  captures[String(tabId)] = capture
  await chrome.storage.session.set({ [CAPTURES_KEY]: captures })
  return capture
}

async function removeCapture(tabId) {
  const captures = await getCaptures()
  delete captures[String(tabId)]
  await chrome.storage.session.set({ [CAPTURES_KEY]: captures })
}

async function activeTab() {
  const tabs = await chrome.tabs.query({ active: true, currentWindow: true })
  return tabs[0] || null
}

async function detectedWorkspaceContext() {
  const tabs = await chrome.tabs.query({ currentWindow: true })
  const candidates = tabs
    .map((tab) => ({
      tab,
      context: workspaceContextFromUrl(tab.url)
    }))
    .filter((entry) => entry.context)
    .sort((left, right) => Number(right.tab.lastAccessed || 0) - Number(left.tab.lastAccessed || 0))

  return candidates[0]?.context || null
}

function jsonError(error) {
  if (error instanceof Error) return error.message
  return String(error || "Unknown error")
}

async function fetchJson(settings, path, { method = "GET", body } = {}) {
  const url = new URL(path, settings.baseUrl).toString()
  const headers = {
    "Accept": "application/json",
    "Authorization": `Bearer ${settings.apiToken}`
  }

  const options = { method, headers }
  if (body !== undefined) {
    headers["Content-Type"] = "application/json"
    options.body = JSON.stringify(body)
  }

  const response = await fetch(url, options)
  const text = await response.text()
  const payload = text ? JSON.parse(text) : {}

  if (!response.ok) {
    const message = payload?.error?.message || `Request failed with status ${response.status}`
    throw new Error(message)
  }

  return payload
}

function pageUrlFor(settings, pagePath) {
  if (!pagePath) return null
  return new URL(pagePath, settings.baseUrl).toString()
}

function fallbackTitle(tab) {
  const rawTitle = String(tab?.title || "").trim()
  if (rawTitle.length === 0) return "Google Meet transcript"
  return rawTitle.replace(/\s*-\s*Google Meet\s*$/i, "").trim() || rawTitle
}

function transcriptTextFor(utterances) {
  return Array.isArray(utterances) ? utterances.map((utterance) => {
    const seconds = Math.max(Math.floor(Number(utterance.started_ms || 0) / 1000), 0)
    const minutesPart = String(Math.floor(seconds / 60)).padStart(2, "0")
    const secondsPart = String(seconds % 60).padStart(2, "0")
    const speaker = String(utterance.speaker_name || utterance.speaker_key || "Speaker").trim()
    const text = String(utterance.text || "").trim()
    return `[${minutesPart}:${secondsPart}] ${speaker}: ${text}`
  }).join("\n") : ""
}

function mergedCaptureSnapshot(capture, snapshot, tab) {
  return {
    ...capture,
    title: String(snapshot?.title || capture.title || fallbackTitle(tab)).trim(),
    joinUrl: String(snapshot?.joinUrl || capture.joinUrl || tab?.url || "").trim(),
    utterances: Array.isArray(snapshot?.utterances) ? snapshot.utterances : (capture.utterances || []),
    transcriptText: String(snapshot?.transcriptText || transcriptTextFor(snapshot?.utterances || capture.utterances || [])).trim(),
    updatedAt: Date.now()
  }
}

async function ensureSession(tabId, capture, tab) {
  if (capture.sessionId) return capture

  if (capture.lastCreateAttemptAt && capture.lastCreateAttemptAt > Date.now() - SESSION_CREATE_RETRY_MS) {
    return capture
  }

  const updatedCapture = { ...capture, lastCreateAttemptAt: Date.now() }
  await setCapture(tabId, updatedCapture)

  const payload = await fetchJson(updatedCapture.settings, `/api/v1/workspaces/${encodeURIComponent(updatedCapture.settings.workspaceSlug)}/meetings/sessions`, {
    method: "POST",
    body: {
      meeting_session: {
        title: updatedCapture.title || fallbackTitle(tab),
        join_url: updatedCapture.joinUrl || tab?.url || "",
        force_new: false
      }
    }
  })
  const session = payload.data || {}

  return {
    ...updatedCapture,
    sessionId: session.id || null,
    pageUrl: pageUrlFor(updatedCapture.settings, session.page_path),
    lastError: ""
  }
}

async function uploadTranscript(capture) {
  await fetchJson(capture.settings, `/api/v1/workspaces/${encodeURIComponent(capture.settings.workspaceSlug)}/meetings/sessions/${encodeURIComponent(capture.sessionId)}/ingest_transcript`, {
    method: "POST",
    body: {
      meeting_session: {
        transcript_text: capture.transcriptText,
        utterances: capture.utterances,
        metadata: {
          extension_version: EXTENSION_VERSION,
          join_url: capture.joinUrl,
          captured_at: new Date().toISOString()
        }
      }
    }
  })
}

async function cancelSession(capture) {
  if (!capture.sessionId) return

  await fetchJson(capture.settings, `/api/v1/workspaces/${encodeURIComponent(capture.settings.workspaceSlug)}/meetings/sessions/${encodeURIComponent(capture.sessionId)}/cancel`, {
    method: "POST"
  })
}

async function finalizeCapture(tabId, { snapshot = null, tabRemoved = false } = {}) {
  const tab = tabRemoved ? null : await chrome.tabs.get(tabId).catch(() => null)
  let capture = await getCapture(tabId)
  if (!capture) return { ok: true }

  if (snapshot) {
    capture = mergedCaptureSnapshot(capture, snapshot, tab)
  }

  capture = {
    ...capture,
    capturing: false,
    uploading: true,
    lastError: ""
  }
  await setCapture(tabId, capture)

  try {
    if (!capture.sessionId && Array.isArray(capture.utterances) && capture.utterances.length > 0) {
      capture = await ensureSession(tabId, capture, tab)
      await setCapture(tabId, capture)
    }

    if (capture.sessionId && Array.isArray(capture.utterances) && capture.utterances.length > 0) {
      await uploadTranscript(capture)
      const completedCapture = {
        ...capture,
        capturing: false,
        uploading: false,
        syncComplete: true,
        lastError: ""
      }

      if (tabRemoved) {
        await removeCapture(tabId)
      } else {
        await setCapture(tabId, completedCapture)
      }

      return { ok: true, pageUrl: completedCapture.pageUrl || null }
    }

    if (capture.sessionId) {
      await cancelSession(capture)
    }

    await removeCapture(tabId)
    return { ok: true }
  } catch (error) {
    await setCapture(tabId, {
      ...capture,
      uploading: false,
      lastError: jsonError(error)
    })
    return { ok: false, error: jsonError(error) }
  }
}

async function popupState() {
  const tab = await activeTab()
  const settings = await getSettings()
  const capture = tab ? await getCapture(tab.id) : null
  const detectedWorkspace = await detectedWorkspaceContext()

  return {
    tabId: tab?.id || null,
    isMeetTab: meetTabUrl(tab?.url),
    settings,
    capture,
    detectedWorkspace
  }
}

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  ;(async () => {
    switch (message?.type) {
      case "notae-meet-popup-state":
        sendResponse(await popupState())
        return
      case "notae-meet-save-settings":
        await saveSettings(message.settings || {})
        sendResponse({ ok: true })
        return
      case "notae-meet-detected-workspace":
        sendResponse({ ok: true, detectedWorkspace: await detectedWorkspaceContext() })
        return
      case "notae-meet-start-capture": {
        const tabId = Number(message.tabId)
        const tab = await chrome.tabs.get(tabId)
        if (!meetTabUrl(tab.url)) {
          sendResponse({ ok: false, error: "Open a Google Meet tab before starting capture." })
          return
        }

        const settings = normalizedSettings(message.settings || {})
        if (!settings.baseUrl || !settings.workspaceSlug || !settings.apiToken) {
          sendResponse({ ok: false, error: "Save the Notae base URL, workspace slug, and extension token first." })
          return
        }

        await saveSettings(settings)
        await setCapture(tabId, {
          settings,
          tabId,
          capturing: true,
          uploading: false,
          syncComplete: false,
          lastError: "",
          sessionId: null,
          pageUrl: null,
          title: fallbackTitle(tab),
          joinUrl: tab.url,
          utterances: [],
          transcriptText: "",
          createdAt: Date.now(),
          updatedAt: Date.now(),
          lastCreateAttemptAt: null
        })

        await chrome.tabs.sendMessage(tabId, { type: "notae-meet-start" })
        sendResponse({ ok: true })
        return
      }
      case "notae-meet-stop-capture": {
        const tabId = Number(message.tabId)
        const snapshotResponse = await chrome.tabs.sendMessage(tabId, { type: "notae-meet-stop" }).catch(() => null)
        sendResponse(await finalizeCapture(tabId, { snapshot: snapshotResponse?.snapshot || null }))
        return
      }
      case "notae-meet-open-page":
        if (message.url) await chrome.tabs.create({ url: message.url })
        sendResponse({ ok: true })
        return
      case "notae-meet-transcript-snapshot": {
        const tabId = sender.tab?.id
        if (!tabId) {
          sendResponse({ ok: false })
          return
        }

        const tab = sender.tab
        let capture = await getCapture(tabId)
        if (!capture) {
          sendResponse({ ok: false })
          return
        }

        capture = mergedCaptureSnapshot(capture, message.snapshot || {}, tab)
        if (!capture.sessionId && Array.isArray(capture.utterances) && capture.utterances.length > 0) {
          capture = await ensureSession(tabId, capture, tab)
        }

        await setCapture(tabId, capture)
        sendResponse({ ok: true })
        return
      }
      default:
        sendResponse({ ok: false, error: "Unknown message type." })
    }
  })().catch((error) => {
    sendResponse({ ok: false, error: jsonError(error) })
  })

  return true
})

chrome.tabs.onRemoved.addListener((tabId) => {
  finalizeCapture(tabId, { tabRemoved: true }).catch(() => {})
})

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (!changeInfo.url || meetTabUrl(changeInfo.url)) return

  finalizeCapture(tabId, { tabRemoved: false }).catch(() => {})
})
