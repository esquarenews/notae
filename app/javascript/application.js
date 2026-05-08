// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

let pwaRegistrationPromise
const AI_RAIL_COLLAPSED_CLASS = "is-ai-rail-collapsed"
const AI_RAIL_COLLAPSED_PREFERENCE_KEY = "notae-ai-rail-collapsed-v2"
const PRESERVED_SAVE_SCROLL_KEY = "notae-preserved-save-scroll"
const PRESERVED_SAVE_SCROLL_MAX_AGE_MS = 30_000
const PRESERVED_SAVE_SCROLL_RESTORE_DELAYS_MS = [ 60, 180, 360, 720, 1200, 1800 ]
const SIDEBAR_SECTIONS_FRAME_ID = "notae_sidebar_sections"
const SIDEBAR_SECTIONS_REFRESH_DELAY_MS = 250
const SIDEBAR_ACTIVE_LINK_SELECTOR = ".notae-sidebar a[href], .notae-sidebar-dock-icons a[href]"
const PERSISTED_SHELL_STATE_CLASSES = [
  "is-sidebar-collapsed",
  "is-mobile-viewport",
  "is-ai-compact-viewport",
  "is-ai-rail-collapsed"
]

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

  const keyedAncestor = sourceElement.closest("[data-scroll-preserve-key]")
  if (keyedAncestor instanceof Element) return keyedAncestor

  let current = sourceElement
  while (current instanceof Element) {
    if (uniqueIdSelectorFor(current)) return current
    current = current.parentElement
  }

  return null
}

function selectorForTrackedElement(element) {
  if (!(element instanceof Element)) return null

  const customKey = element.getAttribute("data-scroll-preserve-key")
  if (customKey) {
    return `[data-scroll-preserve-key="${escapeSelectorValue(customKey)}"]`
  }

  return uniqueIdSelectorFor(element)
}

function uniqueIdSelectorFor(element) {
  if (!(element instanceof Element) || !element.id) return null

  const selector = `#${escapeSelectorValue(element.id)}`
  if (document.querySelectorAll(selector).length !== 1) return null

  return selector
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

function preserveScrollRequested(element) {
  if (!(element instanceof HTMLElement)) return false
  if (element.dataset.preserveScroll === "false") return false

  return element.dataset.preserveScroll === "true" || element.dataset.preserveDatabaseScroll === "true"
}

function shouldPreserveSaveScroll(form) {
  if (!saveLikeForm(form)) return false

  return preserveScrollRequested(form)
}

function responseForEvent(event) {
  const response = event.detail?.fetchResponse?.response
  return response instanceof Response ? response : null
}

function responseContentType(event) {
  const response = responseForEvent(event)
  if (!response) return ""

  return response.headers.get("content-type") || ""
}

function shouldDeferPreservedSaveScrollRestore(event) {
  const response = responseForEvent(event)
  if (!response) return false
  if (response.redirected) return true

  const contentType = responseContentType(event)
  return contentType.length > 0 && !contentType.includes("turbo-stream")
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
  apply()
  window.requestAnimationFrame(() => apply())
  PRESERVED_SAVE_SCROLL_RESTORE_DELAYS_MS.forEach((delay) => {
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

function aiRailContextDataset(root = document) {
  if (root instanceof HTMLBodyElement) return root.dataset
  if (root instanceof Document) return root.body?.dataset || {}
  if (root instanceof HTMLElement) return root.ownerDocument?.body?.dataset || {}

  return document.body?.dataset || {}
}

function syncPreservedAiRailContext(root = document) {
  const dataset = aiRailContextDataset(root)
  const currentPageId = dataset.aiRailCurrentPageIdValue || ""
  const panelSrc = dataset.aiRailPanelSrcValue || ""
  const currentPageInput = document.querySelector('input[name="ai_assistant[current_page_id]"]')

  if (currentPageInput instanceof HTMLInputElement) {
    currentPageInput.value = currentPageId
  }

  const loaderFrame = document.querySelector('turbo-frame#ai_rail_panel[data-controller~="ai-rail-loader"]')
  if (!(loaderFrame instanceof HTMLElement)) return
  const railAlreadyLoaded = loaderFrame.querySelector(".notae-ai-rail-shell") instanceof HTMLElement

  if (panelSrc.length > 0) {
    loaderFrame.dataset.aiRailLoaderSrcValue = panelSrc

    if (!railAlreadyLoaded && loaderFrame.hasAttribute("src") && loaderFrame.getAttribute("src") !== panelSrc) {
      loaderFrame.setAttribute("src", panelSrc)
    }
  } else {
    loaderFrame.removeAttribute("src")
    delete loaderFrame.dataset.aiRailLoaderSrcValue
  }
}

function syncPersistedShellState(root = document) {
  const sourceShell = document.querySelector(".notae-shell")
  if (!(sourceShell instanceof HTMLElement)) return

  const scope = root instanceof Document || root instanceof HTMLElement ? root : document

  scope.querySelectorAll?.(".notae-shell").forEach((shell) => {
    if (!(shell instanceof HTMLElement)) return

    PERSISTED_SHELL_STATE_CLASSES.forEach((className) => {
      shell.classList.toggle(className, sourceShell.classList.contains(className))
    })

    if (scope !== document) {
      shell.classList.remove("is-layout-hydrating")
    }
  })
}

function sidebarSectionsFrame() {
  return document.getElementById(SIDEBAR_SECTIONS_FRAME_ID)
}

function refreshSidebarSectionsFrame() {
  const frame = sidebarSectionsFrame()
  if (!(frame instanceof HTMLElement)) return

  if (typeof frame.reload === "function") {
    frame.reload()
    return
  }

  const src = frame.getAttribute("src")
  if (src) frame.setAttribute("src", src)
}

function shouldRefreshSidebarSectionsAfterSubmit(event) {
  const form = event.target
  if (!(form instanceof HTMLFormElement)) return false
  if (!event.detail?.success) return false
  if (!form.closest(".notae-sidebar")) return false

  const action = form.getAttribute("action") || ""
  return action.includes("/pages") || action.includes("/databases")
}

function syncSidebarActiveLinks() {
  const currentPath = window.location.pathname

  document.querySelectorAll(SIDEBAR_ACTIVE_LINK_SELECTOR).forEach((link) => {
    if (!(link instanceof HTMLAnchorElement)) return

    let linkPath
    try {
      linkPath = new URL(link.href, window.location.origin).pathname
    } catch (_error) {
      return
    }

    const active = linkPath === currentPath
    link.classList.toggle("active", active)
    if (active) {
      link.setAttribute("aria-current", "page")
    } else {
      link.removeAttribute("aria-current")
    }
  })
}

syncAiRailCollapsedState(document)
syncPreservedAiRailContext(document)
syncPersistedShellState(document)
syncSidebarActiveLinks()
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
  if (shouldDeferPreservedSaveScrollRestore(event)) return

  restoreStoredSaveScroll()
}, true)

document.addEventListener("turbo:submit-end", (event) => {
  if (!shouldRefreshSidebarSectionsAfterSubmit(event)) return

  window.setTimeout(refreshSidebarSectionsFrame, SIDEBAR_SECTIONS_REFRESH_DELAY_MS)
}, true)

window.addEventListener("notae:sidebar-sections-refresh", () => {
  refreshSidebarSectionsFrame()
})

document.addEventListener("turbo:load", () => {
  restoreStoredSaveScroll()
  syncAiRailCollapsedState(document)
  syncPreservedAiRailContext(document)
  syncPersistedShellState(document)
  syncSidebarActiveLinks()
  registerPwaServiceWorker()
})

document.addEventListener("turbo:before-render", (event) => {
  const newBody = event.detail?.newBody
  if (!(newBody instanceof HTMLBodyElement)) return

  syncAiRailCollapsedState(newBody)
  syncPreservedAiRailContext(newBody)
  syncPersistedShellState(newBody)
})

document.addEventListener("turbo:render", () => {
  restoreStoredSaveScroll()
  syncSidebarActiveLinks()
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
