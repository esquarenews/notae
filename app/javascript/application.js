// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

let pwaRegistrationPromise
const AI_RAIL_COLLAPSED_CLASS = "is-ai-rail-collapsed"
const AI_RAIL_COLLAPSED_PREFERENCE_KEY = "notae-ai-rail-collapsed"

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

document.addEventListener("turbo:load", () => {
  syncAiRailCollapsedState(document)
  registerPwaServiceWorker()
})

document.addEventListener("turbo:before-render", (event) => {
  const newBody = event.detail?.newBody
  if (!(newBody instanceof HTMLBodyElement)) return

  syncAiRailCollapsedState(newBody)
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
