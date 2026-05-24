import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["elapsed"]
  static values = { startedAt: String }

  connect() {
    this.render()
    this.timer = window.setInterval(() => this.render(), 1000)
  }

  disconnect() {
    if (!this.timer) return

    window.clearInterval(this.timer)
    this.timer = null
  }

  render() {
    if (!this.hasElapsedTarget) return

    const startedAt = this.startedDate()
    if (!startedAt) return

    this.elapsedTarget.textContent = this.formatElapsed(Date.now() - startedAt.getTime())
  }

  startedDate() {
    const raw = this.startedAtValue?.trim()
    if (!raw) return null

    const parsed = new Date(raw)
    return Number.isNaN(parsed.getTime()) ? null : parsed
  }

  formatElapsed(milliseconds) {
    const totalSeconds = Math.max(Math.floor(milliseconds / 1000), 0)
    const hours = Math.floor(totalSeconds / 3600)
    const minutes = Math.floor((totalSeconds % 3600) / 60)
    const seconds = totalSeconds % 60
    const pad = (value) => value.toString().padStart(2, "0")

    return `${pad(hours)}:${pad(minutes)}:${pad(seconds)}`
  }
}
