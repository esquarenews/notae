import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["startButton", "stopButton", "status", "fileInput", "captureMode", "activityIndicator", "activityLabel", "submitButton", "deleteButton", "sessionTitleInput"]

  connect() {
    this.mediaRecorder = null
    this.stream = null
    this.chunks = []
    this.activeSessionTitle = ""
    this.setRecordingState(false, "Recorder idle.")
    this.syncReadyStateFromInput()
  }

  disconnect() {
    this.setRecordingState(false)
    this.stopStream()
  }

  async start(event) {
    event.preventDefault()
    if (this.mediaRecorder?.state === "recording") return
    this.clearCapturedFile()
    this.setRecordingReady(false)

    if (!navigator.mediaDevices?.getUserMedia || typeof window.MediaRecorder === "undefined") {
      this.updateStatus("Microphone recording is not supported in this browser.")
      return
    }

    if (!window.isSecureContext) {
      this.updateStatus("Microphone access requires a secure origin (https:// or localhost).")
      return
    }

    if (!this.microphoneFeatureAllowed()) {
      this.updateStatus("Microphone access is blocked by the page Permissions-Policy header. Restart the app after setting Permissions-Policy to include microphone=(self).")
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
      this.activeSessionTitle = this.currentSessionTitle()
      const recordingLabel = this.recordingInProgressLabel()
      this.setRecordingState(true, recordingLabel)
      this.updateStatus(recordingLabel)
    } catch (error) {
      this.activeSessionTitle = ""
      this.setRecordingState(false)
      this.updateStatus(this.microphoneErrorMessage(error))
      this.stopStream()
    }
  }

  stop(event) {
    event.preventDefault()
    if (!this.mediaRecorder || this.mediaRecorder.state !== "recording") return

    this.mediaRecorder.stop()
    this.startButtonTarget.disabled = false
    this.stopButtonTarget.disabled = true
    const finalizingLabel = this.finalizingLabel()
    this.setRecordingState(false, finalizingLabel)
    this.updateStatus(finalizingLabel)
  }

  supportedMimeType() {
    const mimeCandidates = ["audio/webm;codecs=opus", "audio/webm", "audio/mp4"]
    return mimeCandidates.find((type) => MediaRecorder.isTypeSupported(type))
  }

  persistRecording() {
    if (!this.hasFileInputTarget || this.chunks.length === 0) {
      this.setRecordingReady(false)
      this.setRecordingState(false)
      this.updateStatus("Recording complete.")
      this.activeSessionTitle = ""
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
    this.setRecordingReady(true)

    this.setRecordingState(false, "Recorder idle.")
    this.updateStatus("Recording ready. Submit for processing or delete recording.")
    this.activeSessionTitle = ""
    this.stopStream()
  }

  syncSessionTitle() {
    if (!this.mediaRecorder || this.mediaRecorder.state !== "recording") return
    this.activeSessionTitle = this.currentSessionTitle()
    const recordingLabel = this.recordingInProgressLabel()
    this.setRecordingState(true, recordingLabel)
    this.updateStatus(recordingLabel)
  }

  clearRecording(event) {
    if (event) event.preventDefault()
    if (this.mediaRecorder?.state === "recording") {
      this.mediaRecorder.stop()
    }
    this.stopStream()
    this.clearCapturedFile()
    this.chunks = []
    this.activeSessionTitle = ""
    this.setRecordingReady(false)
    this.startButtonTarget.disabled = false
    this.stopButtonTarget.disabled = true
    this.setRecordingState(false, "Recorder idle.")
    this.updateStatus("Recording deleted.")
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

  setRecordingState(active, label = null) {
    if (this.hasActivityIndicatorTarget) {
      this.activityIndicatorTarget.classList.toggle("is-active", active)
    }
    if (label && this.hasActivityLabelTarget) {
      this.activityLabelTarget.textContent = label
    }
  }

  syncReadyStateFromInput() {
    const hasFile = this.hasFileInputTarget && this.fileInputTarget.files && this.fileInputTarget.files.length > 0
    this.setRecordingReady(hasFile)
  }

  setRecordingReady(ready) {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.hidden = !ready
      this.submitButtonTarget.disabled = !ready
    }
    if (this.hasDeleteButtonTarget) {
      this.deleteButtonTarget.hidden = !ready
      this.deleteButtonTarget.disabled = !ready
    }
  }

  clearCapturedFile() {
    if (!this.hasFileInputTarget) return
    this.fileInputTarget.value = ""
  }

  currentSessionTitle() {
    if (!this.hasSessionTitleInputTarget) return ""
    return this.sessionTitleInputTarget.value.toString().trim()
  }

  recordingInProgressLabel() {
    if (this.activeSessionTitle.length > 0) {
      return `Recording in progress: ${this.activeSessionTitle}`
    }
    return "Recording in progress..."
  }

  finalizingLabel() {
    if (this.activeSessionTitle.length > 0) {
      return `Finalizing recording: ${this.activeSessionTitle}`
    }
    return "Finalizing recording..."
  }

  microphoneFeatureAllowed() {
    const policy = document.permissionsPolicy || document.featurePolicy
    if (!policy || typeof policy.allowsFeature !== "function") return true

    try {
      return policy.allowsFeature("microphone")
    } catch (_error) {
      return true
    }
  }

  microphoneErrorMessage(error) {
    const name = error?.name?.toString() || ""
    const message = error?.message?.toString()?.trim() || ""

    if (name === "NotAllowedError" || name === "PermissionDeniedError") {
      if (!this.microphoneFeatureAllowed()) {
        return "Microphone access failed: blocked by page Permissions-Policy. Restart the app and ensure the response header includes microphone=(self)."
      }
      if (!window.isSecureContext) {
        return "Microphone access failed: this page is not secure. Use https:// or localhost."
      }
      return "Microphone access failed: permission denied. Click the lock/camera icon in the address bar and allow Microphone for this site, then retry."
    }

    if (name === "NotFoundError" || name === "DevicesNotFoundError") {
      return "Microphone access failed: no microphone device was found."
    }

    if (name === "NotReadableError" || name === "TrackStartError") {
      return "Microphone access failed: your microphone is busy in another app."
    }

    if (name === "SecurityError") {
      return "Microphone access failed: blocked by browser security settings."
    }

    return `Microphone access failed: ${message || "Unable to access microphone."}`
  }
}
