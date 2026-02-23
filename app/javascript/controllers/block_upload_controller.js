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

    await fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Accept": "text/html",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
      },
      body: formData,
      credentials: "same-origin"
    })

    window.location.reload()
  }

  resetDropzone() {
    this.dropzoneTarget.classList.remove("border-slate-500", "bg-slate-100")
  }
}
