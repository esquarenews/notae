import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "frame", "image", "input", "previewPanel", "saveButton", "stage", "zoom"]
  static values = {
    outputSize: Number,
    previewAlt: String
  }

  connect() {
    this.objectUrl = null
    this.previewUrl = null
    this.dragState = null
    this.offsetX = 0
    this.offsetY = 0
    this.baseScale = 1
    this.scale = 1
    this.imageLoaded = false
    this.cropCommitted = false
  }

  disconnect() {
    this.revokeObjectUrl()
    this.revokePreviewUrl()
  }

  open() {
    const file = this.inputTarget?.files?.[0]
    if (!file || !this.hasDialogTarget || !this.hasImageTarget) return

    this.cropCommitted = false
    this.imageLoaded = false
    this.offsetX = 0
    this.offsetY = 0
    this.setSaveDisabled(true)

    if (this.hasZoomTarget) this.zoomTarget.value = "1"

    if (this.dialogTarget.open) this.dialogTarget.close()
    this.dialogTarget.showModal()

    this.loadImage(file)
  }

  close(event) {
    if (event) event.preventDefault()
    if (!this.hasDialogTarget) return

    if (this.dialogTarget.open) this.dialogTarget.close()
    if (!this.cropCommitted) this.resetSelection()
  }

  cancelDialog(event) {
    if (event) event.preventDefault()
    this.close()
  }

  backdropClose(event) {
    if (event.target !== this.dialogTarget) return

    this.close()
  }

  zoom() {
    if (!this.imageLoaded) return

    this.applyTransform()
  }

  startDrag(event) {
    if (!this.imageLoaded || event.target !== this.imageTarget) return

    event.preventDefault()
    this.dragState = {
      pointerId: event.pointerId,
      x: event.clientX,
      y: event.clientY,
      offsetX: this.offsetX,
      offsetY: this.offsetY
    }

    this.stageTarget.setPointerCapture(event.pointerId)
    this.stageTarget.classList.add("is-dragging")
  }

  drag(event) {
    if (!this.dragState || event.pointerId !== this.dragState.pointerId) return

    event.preventDefault()
    this.offsetX = this.dragState.offsetX + (event.clientX - this.dragState.x)
    this.offsetY = this.dragState.offsetY + (event.clientY - this.dragState.y)
    this.applyTransform()
  }

  stopDrag(event) {
    if (!this.dragState) return
    if (event && event.pointerId && event.pointerId !== this.dragState.pointerId) return

    if (event && Number.isInteger(event.pointerId) && this.stageTarget.hasPointerCapture(event.pointerId)) {
      this.stageTarget.releasePointerCapture(event.pointerId)
    }

    this.dragState = null
    this.stageTarget.classList.remove("is-dragging")
  }

  async save(event) {
    if (event) event.preventDefault()
    if (!this.imageLoaded || !this.hasInputTarget) return

    this.setSaveDisabled(true)

    try {
      const file = await this.buildCroppedFile()
      const transfer = new DataTransfer()
      transfer.items.add(file)
      this.inputTarget.files = transfer.files
      this.renderPreview(file)
      this.cropCommitted = true
      this.close()
      this.element.requestSubmit()
    } finally {
      this.setSaveDisabled(false)
    }
  }

  loadImage(file) {
    this.revokeObjectUrl()
    this.objectUrl = URL.createObjectURL(file)

    this.imageTarget.onload = () => {
      window.requestAnimationFrame(() => this.initializeCrop())
    }
    this.imageTarget.src = this.objectUrl
  }

  initializeCrop() {
    if (!this.hasFrameTarget || !this.hasImageTarget) return

    const frameRect = this.frameTarget.getBoundingClientRect()
    const frameSize = Math.min(frameRect.width, frameRect.height)
    if (frameSize <= 0) return

    this.frameSize = frameSize
    this.baseScale = Math.max(frameSize / this.imageTarget.naturalWidth, frameSize / this.imageTarget.naturalHeight)
    this.scale = this.baseScale
    this.offsetX = 0
    this.offsetY = 0
    this.imageLoaded = true
    this.applyTransform()
    this.setSaveDisabled(false)
  }

  applyTransform() {
    const zoomFactor = this.hasZoomTarget ? Number.parseFloat(this.zoomTarget.value || "1") : 1
    this.scale = this.baseScale * (Number.isFinite(zoomFactor) ? zoomFactor : 1)

    const displayWidth = this.imageTarget.naturalWidth * this.scale
    const displayHeight = this.imageTarget.naturalHeight * this.scale
    const maxOffsetX = Math.max(0, (displayWidth - this.frameSize) / 2)
    const maxOffsetY = Math.max(0, (displayHeight - this.frameSize) / 2)

    this.offsetX = this.clamp(this.offsetX, -maxOffsetX, maxOffsetX)
    this.offsetY = this.clamp(this.offsetY, -maxOffsetY, maxOffsetY)

    Object.assign(this.imageTarget.style, {
      width: `${displayWidth}px`,
      height: `${displayHeight}px`,
      left: "50%",
      top: "50%",
      marginLeft: `${this.offsetX}px`,
      marginTop: `${this.offsetY}px`
    })
  }

  async buildCroppedFile() {
    const canvas = document.createElement("canvas")
    const outputSize = this.hasOutputSizeValue ? this.outputSizeValue : 512
    const displayWidth = this.imageTarget.naturalWidth * this.scale
    const displayHeight = this.imageTarget.naturalHeight * this.scale
    const cropWidth = this.frameSize / this.scale
    const cropHeight = this.frameSize / this.scale
    const sourceX = this.clamp(((displayWidth - this.frameSize) / 2 - this.offsetX) / this.scale, 0, this.imageTarget.naturalWidth - cropWidth)
    const sourceY = this.clamp(((displayHeight - this.frameSize) / 2 - this.offsetY) / this.scale, 0, this.imageTarget.naturalHeight - cropHeight)

    canvas.width = outputSize
    canvas.height = outputSize

    const context = canvas.getContext("2d")
    if (!context) throw new Error("Avatar crop could not be rendered.")

    context.drawImage(
      this.imageTarget,
      sourceX,
      sourceY,
      cropWidth,
      cropHeight,
      0,
      0,
      outputSize,
      outputSize
    )

    const blob = await new Promise((resolve) => {
      canvas.toBlob(resolve, "image/png")
    })

    if (!blob) throw new Error("Avatar crop could not be saved.")

    const stem = this.fileStem(this.inputTarget.files[0]?.name)
    return new File([blob], `${stem}-avatar.png`, { type: "image/png" })
  }

  renderPreview(file) {
    this.revokePreviewUrl()
    this.previewUrl = URL.createObjectURL(file)

    const image = document.createElement("img")
    image.src = this.previewUrl
    image.alt = this.previewAltValue || "Avatar preview"
    image.className = "notae-account-avatar-image"

    this.previewPanelTarget.replaceChildren(image)
  }

  resetSelection() {
    if (this.hasInputTarget) this.inputTarget.value = ""
    this.revokeObjectUrl()
    this.imageTarget.removeAttribute("src")
    this.imageLoaded = false
    this.setSaveDisabled(true)
  }

  setSaveDisabled(disabled) {
    if (!this.hasSaveButtonTarget) return

    this.saveButtonTarget.disabled = disabled
  }

  clamp(value, min, max) {
    return Math.min(Math.max(value, min), max)
  }

  fileStem(filename) {
    if (!filename || filename.length === 0) return "avatar"

    return filename.replace(/\.[^.]+$/, "").replace(/[^a-z0-9-_]+/gi, "-").replace(/^-+|-+$/g, "") || "avatar"
  }

  revokeObjectUrl() {
    if (!this.objectUrl) return

    URL.revokeObjectURL(this.objectUrl)
    this.objectUrl = null
  }

  revokePreviewUrl() {
    if (!this.previewUrl) return

    URL.revokeObjectURL(this.previewUrl)
    this.previewUrl = null
  }
}
