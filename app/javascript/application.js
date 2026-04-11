// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

let pwaRegistrationPromise
const AI_RAIL_COLLAPSED_CLASS = "is-ai-rail-collapsed"
const AI_RAIL_COLLAPSED_PREFERENCE_KEY = "notae-ai-rail-collapsed"
const PRESERVED_SAVE_SCROLL_KEY = "notae-preserved-save-scroll"
const PRESERVED_SAVE_SCROLL_MAX_AGE_MS = 30_000

function primaryScrollContainer() {
  return document.querySelector(".notae-content-scroll") || document.scrollingElement || document.documentElement
}

function escapeSelectorValue(value) {
  if (typeof CSS !== "undefined" && typeof CSS.escape === "function") {
    return CSS.escape(value)
  }

  return String(value).replace(/["\\]/g, "\\$&")
}

function trackedElementFor(sourceElement) {
  if (!(sourceElement instanceof Element)) return null

  return sourceElement.closest("[data-scroll-preserve-key], [id]")
}

function selectorForTrackedElement(element) {
  if (!(element instanceof Element)) return null

  const customKey = element.getAttribute("data-scroll-preserve-key")
  if (customKey) {
    return `[data-scroll-preserve-key="${escapeSelectorValue(customKey)}"]`
  }

  if (element.id) {
    return `#${escapeSelectorValue(element.id)}`
  }

  return null
}

function currentPreservedSaveScrollState(sourceElement = null) {
  const scrollContainer = primaryScrollContainer()
  if (!scrollContainer) return null

  const trackedElement = trackedElementFor(sourceElement)

  return {
    path: window.location.pathname,
    timestamp: Date.now(),
    scrollTop: scrollContainer.scrollTop,
    scrollLeft: scrollContainer.scrollLeft,
    trackedSelector: selectorForTrackedElement(trackedElement),
    trackedViewportTop: trackedElement ? trackedElement.getBoundingClientRect().top : null
  }
}

function storePreservedSaveScroll(state) {
  if (!state) return

  try {
    window.sessionStorage.setItem(PRESERVED_SAVE_SCROLL_KEY, JSON.stringify(state))
  } catch (_error) {
    // Ignore storage failures and allow the request to continue normally.
  }
}

function readPreservedSaveScroll() {
  try {
    const rawPayload = window.sessionStorage.getItem(PRESERVED_SAVE_SCROLL_KEY)
    return rawPayload ? JSON.parse(rawPayload) : null
  } catch (_error) {
    return null
  }
}

function clearPreservedSaveScroll() {
  try {
    window.sessionStorage.removeItem(PRESERVED_SAVE_SCROLL_KEY)
  } catch (_error) {
    // Ignore storage failures and allow the request to continue normally.
  }
}

function saveLikeForm(form) {
  if (!(form instanceof HTMLFormElement)) return false

  return form.method.toLowerCase() !== "get"
}

function shouldPreserveSaveScroll(form) {
  if (!saveLikeForm(form)) return false

  return form.dataset.preserveScroll !== "false"
}

function responseContentType(event) {
  const response = event.detail?.fetchResponse?.response
  if (!(response instanceof Response)) return ""

  return response.headers.get("content-type") || ""
}

function submitterForEvent(event, fallbackForm) {
  if (event.submitter instanceof Element) return event.submitter

  const turboSubmitter = event.detail?.formSubmission?.submitter
  if (turboSubmitter instanceof Element) return turboSubmitter

  if (document.activeElement instanceof Element && fallbackForm.contains(document.activeElement)) {
    return document.activeElement
  }

  return fallbackForm
}

function restoreTrackedElementPosition(scrollContainer, state) {
  if (!state?.trackedSelector) return
  if (typeof state.trackedViewportTop !== "number") return

  const trackedElement = document.querySelector(state.trackedSelector)
  if (!(trackedElement instanceof Element)) return

  const currentViewportTop = trackedElement.getBoundingClientRect().top
  const delta = currentViewportTop - state.trackedViewportTop
  if (Math.abs(delta) < 1) return

  scrollContainer.scrollTop += delta
}

function restorePreservedSaveScroll(state, { clear = true } = {}) {
  if (!state) return false
  if (state.path !== window.location.pathname) {
    if (clear) clearPreservedSaveScroll()
    return false
  }

  if (Date.now() - Number(state.timestamp || 0) > PRESERVED_SAVE_SCROLL_MAX_AGE_MS) {
    if (clear) clearPreservedSaveScroll()
    return false
  }

  const scrollContainer = primaryScrollContainer()
  if (!scrollContainer) return false

  if (clear) clearPreservedSaveScroll()

  const apply = () => {
    scrollContainer.scrollTop = Number(state.scrollTop || 0)
    scrollContainer.scrollLeft = Number(state.scrollLeft || 0)
    restoreTrackedElementPosition(scrollContainer, state)
  }
  const restoreDelays = [ 60, 180, 360, 720 ]

  apply()
  window.requestAnimationFrame(() => apply())
  restoreDelays.forEach((delay) => {
    window.setTimeout(() => apply(), delay)
  })

  return true
}

function restoreStoredSaveScroll() {
  const storedState = readPreservedSaveScroll()
  if (!storedState) return false

  return restorePreservedSaveScroll(storedState)
}

function securePwaContext() {
  if (window.isSecureContext) return true

  return ["localhost", "127.0.0.1", "[::1]"].includes(window.location.hostname)
}

function registerPwaServiceWorker() {
  if (pwaRegistrationPromise) return pwaRegistrationPromise
  if (!("serviceWorker" in navigator)) return Promise.resolve(null)
  if (!securePwaContext()) return Promise.resolve(null)

  pwaRegistrationPromise = navigator.serviceWorker.register("/service-worker.js", {
    scope: "/",
    updateViaCache: "none"
  }).catch(() => null)
  return pwaRegistrationPromise
}

function aiRailCollapsedPreference() {
  try {
    return window.localStorage.getItem(AI_RAIL_COLLAPSED_PREFERENCE_KEY) === "true"
  } catch (_error) {
    return false
  }
}

function syncAiRailCollapsedState(root) {
  const collapsed = aiRailCollapsedPreference()
  const scope = root instanceof Document || root instanceof HTMLElement ? root : document

  scope.querySelectorAll?.(".notae-shell").forEach((shell) => {
    shell.classList.toggle(AI_RAIL_COLLAPSED_CLASS, collapsed)
  })
}

syncAiRailCollapsedState(document)
restoreStoredSaveScroll()

document.addEventListener("submit", (event) => {
  const form = event.target
  if (!shouldPreserveSaveScroll(form)) return

  storePreservedSaveScroll(currentPreservedSaveScrollState(submitterForEvent(event, form)))
}, true)

document.addEventListener("turbo:submit-start", (event) => {
  const form = event.target
  if (!shouldPreserveSaveScroll(form)) return

  storePreservedSaveScroll(currentPreservedSaveScrollState(submitterForEvent(event, form)))
}, true)

document.addEventListener("turbo:submit-end", (event) => {
  const form = event.target
  if (!shouldPreserveSaveScroll(form)) return
  if (!event.detail?.success) return

  const contentType = responseContentType(event)
  if (!contentType.includes("turbo-stream")) return

  restoreStoredSaveScroll()
}, true)

document.addEventListener("turbo:load", () => {
  restoreStoredSaveScroll()
  syncAiRailCollapsedState(document)
  registerPwaServiceWorker()
})

document.addEventListener("turbo:before-render", (event) => {
  const newBody = event.detail?.newBody
  if (!(newBody instanceof HTMLBodyElement)) return

  syncAiRailCollapsedState(newBody)
})

document.addEventListener("turbo:render", () => {
  restoreStoredSaveScroll()
})

document.addEventListener("turbo:frame-missing", async (event) => {
  const frame = event.target
  if (!(frame instanceof HTMLElement)) return
  if (frame.id !== "ai_rail_panel") return

  event.preventDefault()

  const response = event.detail?.response
  const visit = event.detail?.visit

  if (!(response instanceof Response) || typeof visit !== "function") {
    window.location.reload()
    return
  }

  const contentType = response.headers.get("content-type") || ""

  if (contentType.includes("text/vnd.turbo-stream.html") && window.Turbo?.renderStreamMessage) {
    window.Turbo.renderStreamMessage(await response.clone().text())
    return
  }

  const html = await response.clone().text()
  if (html.trim().length > 0) {
    const documentRoot = new DOMParser().parseFromString(html, "text/html")
    const replacement = documentRoot.querySelector('turbo-frame#ai_rail_panel')

    if (replacement) {
      frame.replaceWith(replacement)
      return
    }
  }

  await visit(response)
})
