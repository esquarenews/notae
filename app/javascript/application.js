// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

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
