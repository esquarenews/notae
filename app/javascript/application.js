// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

const GOOGLE_OAUTH_AUTHORIZE_PATH = "/kalendarium/connections/google_authorize"

function googleOauthActionUrl(form) {
  if (!(form instanceof HTMLFormElement)) return null
  if ((form.method || "").toLowerCase() !== "get") return null

  const action = form.getAttribute("action")
  if (!action) return null

  try {
    const url = new URL(action, window.location.origin)
    if (!url.pathname.endsWith(GOOGLE_OAUTH_AUTHORIZE_PATH)) return null
    return url
  } catch (_error) {
    return null
  }
}

document.addEventListener("turbo:submit-start", (event) => {
  const form = event.target
  const actionUrl = googleOauthActionUrl(form)
  if (!actionUrl) return

  const formSubmission = event.detail?.formSubmission
  if (formSubmission && typeof formSubmission.stop === "function") {
    formSubmission.stop()
  }

  const redirectUrl = new URL(actionUrl.toString())
  const params = new URLSearchParams(new FormData(form))
  params.forEach((value, key) => {
    redirectUrl.searchParams.set(key, value)
  })

  window.location.assign(redirectUrl.toString())
})
