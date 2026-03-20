import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropzone", "input"]
  static values = {
    url: String
  }

  openPicker() {
    if (!this.hasInputTarget) return
    this.inputTarget.click()
  }

  dragover(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.add("border-slate-500", "bg-slate-100")
  }

  dragleave(_event) {
    this.resetDropzone()
  }

  drop(event) {
    event.preventDefault()
    this.resetDropzone()

    const [file] = event.dataTransfer.files
    if (!file) return

    this.submitFile(file)
  }

  upload(event) {
    const [file] = event.target.files
    if (!file) return

    this.submitFile(file)
  }

  async submitFile(file) {
    const formData = new FormData()
    formData.append("block[file]", file)

    const response = await fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
      },
      body: formData,
      credentials: "same-origin"
    })

    if (!response.ok) return

    const payload = await response.json()
    if (payload?.html) {
      this.element.outerHTML = payload.html
    }

    this.updatePageTopbarEditedAt(payload?.page_updated_at || payload?.updated_at)
  }

  resetDropzone() {
    this.dropzoneTarget.classList.remove("border-slate-500", "bg-slate-100")
  }

  updatePageTopbarEditedAt(isoTimestamp) {
    if (!isoTimestamp) return

    const updatedAtMs = Date.parse(isoTimestamp)
    if (!Number.isFinite(updatedAtMs)) return

    const topbar = document.getElementById("page_topbar_edited_at")
    if (!topbar) return

    topbar.textContent = `Edited ${this.relativeTimeLabel(updatedAtMs)} ago`
  }

  relativeTimeLabel(updatedAtMs) {
    const deltaSeconds = Math.max(1, Math.round((Date.now() - updatedAtMs) / 1000))

    if (deltaSeconds < 45) return "less than a minute"
    if (deltaSeconds < 90) return "1 minute"
    if (deltaSeconds < 45 * 60) return `${Math.round(deltaSeconds / 60)} minutes`
    if (deltaSeconds < 90 * 60) return "about 1 hour"
    if (deltaSeconds < 24 * 60 * 60) return `about ${Math.round(deltaSeconds / (60 * 60))} hours`
    if (deltaSeconds < 42 * 60 * 60) return "1 day"
    if (deltaSeconds < 30 * 24 * 60 * 60) return `${Math.round(deltaSeconds / (24 * 60 * 60))} days`
    if (deltaSeconds < 45 * 24 * 60 * 60) return "about 1 month"
    if (deltaSeconds < 365 * 24 * 60 * 60) return `${Math.round(deltaSeconds / (30 * 24 * 60 * 60))} months`
    if (deltaSeconds < 545 * 24 * 60 * 60) return "about 1 year"

    return `${Math.round(deltaSeconds / (365 * 24 * 60 * 60))} years`
  }
}
