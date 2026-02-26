import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["resultText"]

  async copyResult(event) {
    event.preventDefault()

    if (!this.hasResultTextTarget) return

    const text = this.resultTextTarget.textContent?.trim()
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
}
