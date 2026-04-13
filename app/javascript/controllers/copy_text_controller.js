import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async copy(event) {
    event.preventDefault()

    const text = event.currentTarget?.dataset?.copyTextValue?.toString().trim()
    const html = event.currentTarget?.dataset?.copyTextHtmlValue?.toString().trim()
    if (!text) return

    try {
      if (html && navigator.clipboard?.write && typeof window.ClipboardItem !== "undefined") {
        await navigator.clipboard.write([
          new window.ClipboardItem({
            "text/plain": new Blob([ text ], { type: "text/plain" }),
            "text/html": new Blob([ html ], { type: "text/html" })
          })
        ])
      } else {
        await navigator.clipboard.writeText(text)
      }
      this.flashCopied(event.currentTarget)
    } catch (_error) {
      this.copyFallback(text)
      this.flashCopied(event.currentTarget)
    }
  }

  copyFallback(text) {
    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.setAttribute("readonly", "readonly")
    textarea.style.position = "fixed"
    textarea.style.opacity = "0"
    document.body.appendChild(textarea)
    textarea.select()
    document.execCommand("copy")
    textarea.remove()
  }

  flashCopied(button) {
    const feedback = button.querySelector("[data-copy-text-feedback]")
    if (feedback) {
      const original = feedback.textContent
      feedback.textContent = "Copied"
      window.setTimeout(() => {
        feedback.textContent = original
      }, 1200)
      return
    }

    const original = button.textContent
    button.textContent = "Copied"
    window.setTimeout(() => {
      button.textContent = original
    }, 1200)
  }
}
