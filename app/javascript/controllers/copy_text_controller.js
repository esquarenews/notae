import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async copy(event) {
    event.preventDefault()

    const text = event.currentTarget?.dataset?.copyTextValue?.toString().trim()
    if (!text) return

    try {
      await navigator.clipboard.writeText(text)
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
    const original = button.textContent
    button.textContent = "Copied"
    window.setTimeout(() => {
      button.textContent = original
    }, 1200)
  }
}
