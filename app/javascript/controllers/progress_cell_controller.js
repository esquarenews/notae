import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["confetti"]
  static values = {
    cellId: String,
    value: Number
  }

  connect() {
    if (window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches) {
      this.clearCelebration()
      return
    }

    if (this.shouldCelebrate()) {
      this.launchConfetti()
    } else {
      this.clearCelebration()
    }
  }

  prepare(event) {
    const nextValue = Number(event.params.nextValue)
    if (Number.isNaN(nextValue)) return

    if (nextValue >= 10 && this.valueValue < 10) {
      window.sessionStorage?.setItem(this.storageKey(), "1")
    } else {
      window.sessionStorage?.removeItem(this.storageKey())
    }
  }

  shouldCelebrate() {
    if (this.valueValue < 10) return false
    if (!window.sessionStorage) return false

    const shouldCelebrate = window.sessionStorage.getItem(this.storageKey()) === "1"
    if (shouldCelebrate) {
      window.sessionStorage.removeItem(this.storageKey())
    }
    return shouldCelebrate
  }

  launchConfetti() {
    if (!this.hasConfettiTarget) return

    this.clearCelebration()
    const fragment = document.createDocumentFragment()
    const colors = ["#8b5cf6", "#6366f1", "#3b82f6", "#a855f7", "#60a5fa", "#c084fc"]

    for (let index = 0; index < 18; index += 1) {
      const piece = document.createElement("span")
      piece.className = "notae-db-progress-confetti-piece"
      piece.style.setProperty("--notae-progress-confetti-color", colors[index % colors.length])
      piece.style.setProperty("--notae-progress-confetti-offset", `${(Math.random() * 72) - 36}px`)
      piece.style.setProperty("--notae-progress-confetti-delay", `${Math.random() * 0.18}s`)
      piece.style.setProperty("--notae-progress-confetti-rotation", `${(Math.random() * 180) - 90}deg`)
      fragment.appendChild(piece)
    }

    this.confettiTarget.appendChild(fragment)
    window.setTimeout(() => this.clearCelebration(), 1400)
  }

  clearCelebration() {
    if (this.hasConfettiTarget) {
      this.confettiTarget.innerHTML = ""
    }
  }

  storageKey() {
    return `notae-progress-complete:${this.cellIdValue}`
  }
}
