import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["startButton", "stopButton", "status", "fileInput", "captureMode"]

  connect() {
    this.mediaRecorder = null
    this.stream = null
    this.chunks = []
  }

  disconnect() {
    this.stopStream()
  }

  async start(event) {
    event.preventDefault()
    if (this.mediaRecorder?.state === "recording") return

    if (!navigator.mediaDevices?.getUserMedia || typeof window.MediaRecorder === "undefined") {
      this.updateStatus("Microphone recording is not supported in this browser.")
      return
    }

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      const mimeType = this.supportedMimeType()
      this.mediaRecorder = mimeType ? new MediaRecorder(this.stream, { mimeType }) : new MediaRecorder(this.stream)
      this.chunks = []

      this.mediaRecorder.ondataavailable = (recordingEvent) => {
        if (recordingEvent.data?.size > 0) this.chunks.push(recordingEvent.data)
      }
      this.mediaRecorder.onstop = () => this.persistRecording()
      this.mediaRecorder.start()

      this.captureModeTarget.value = "in_person_mic"
      this.startButtonTarget.disabled = true
      this.stopButtonTarget.disabled = false
      this.updateStatus("Recording in progress...")
    } catch (error) {
      this.updateStatus(`Microphone access failed: ${error.message}`)
      this.stopStream()
    }
  }

  stop(event) {
    event.preventDefault()
    if (!this.mediaRecorder || this.mediaRecorder.state !== "recording") return

    this.mediaRecorder.stop()
    this.startButtonTarget.disabled = false
    this.stopButtonTarget.disabled = true
    this.updateStatus("Finalizing recording...")
  }

  supportedMimeType() {
    const mimeCandidates = ["audio/webm;codecs=opus", "audio/webm", "audio/mp4"]
    return mimeCandidates.find((type) => MediaRecorder.isTypeSupported(type))
  }

  persistRecording() {
    if (!this.hasFileInputTarget || this.chunks.length === 0) {
      this.updateStatus("Recording complete.")
      this.stopStream()
      return
    }

    const mimeType = this.mediaRecorder?.mimeType || "audio/webm"
    const extension = mimeType.includes("mp4") ? "m4a" : "webm"
    const blob = new Blob(this.chunks, { type: mimeType })
    const file = new File([blob], `meeting-capture-${Date.now()}.${extension}`, { type: mimeType })
    const dataTransfer = new DataTransfer()
    dataTransfer.items.add(file)
    this.fileInputTarget.files = dataTransfer.files

    this.updateStatus("Recording ready. Submit to upload and process.")
    this.stopStream()
  }

  stopStream() {
    if (this.stream) {
      this.stream.getTracks().forEach((track) => track.stop())
    }
    this.stream = null
  }

  updateStatus(message) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
  }
}
