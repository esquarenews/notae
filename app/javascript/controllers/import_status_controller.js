import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["statusCard", "statusTitle", "statusBody", "submitButton", "fileInput"]

  browseFiles(event) {
    if (event) event.preventDefault()
    if (!this.hasFileInputTarget) return

    this.fileInputTarget.click()
  }

  validateSelection(event) {
    if (this.hasSelectedFiles()) return

    if (event) event.preventDefault()
    this.showError("Import needs attention", "Select at least one file to import.")
  }

  submitStart() {
    this.element.setAttribute("aria-busy", "true")
    if (this.hasStatusCardTarget) {
      this.statusCardTarget.hidden = false
      this.statusCardTarget.classList.remove("is-success", "is-error")
      this.statusCardTarget.classList.add("is-working")
    }
    if (this.hasStatusTitleTarget) this.statusTitleTarget.textContent = "Import in progress"
    if (this.hasStatusBodyTarget) {
      this.statusBodyTarget.textContent = "Your files are uploading and importing now. This page will update when the import finishes."
    }

    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.dataset.originalText = this.submitButtonTarget.value
      this.submitButtonTarget.value = "Importing..."
      this.submitButtonTarget.disabled = true
    }
    if (this.hasFileInputTarget) this.fileInputTarget.disabled = true
  }

  submitEnd(event) {
    if (event.detail?.success) return

    this.element.removeAttribute("aria-busy")
    this.showError("Import failed", "The import could not finish. Fix the issue and try again.")

    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.value = this.submitButtonTarget.dataset.originalText || "Import into Nota"
      this.submitButtonTarget.disabled = false
    }
    if (this.hasFileInputTarget) this.fileInputTarget.disabled = false
  }

  hasSelectedFiles() {
    return this.hasFileInputTarget && this.fileInputTarget.files && this.fileInputTarget.files.length > 0
  }

  showError(title, body) {
    this.element.removeAttribute("aria-busy")
    if (this.hasStatusCardTarget) {
      this.statusCardTarget.hidden = false
      this.statusCardTarget.classList.remove("is-working", "is-success")
      this.statusCardTarget.classList.add("is-error")
    }
    if (this.hasStatusTitleTarget) this.statusTitleTarget.textContent = title
    if (this.hasStatusBodyTarget) this.statusBodyTarget.textContent = body
  }
}
