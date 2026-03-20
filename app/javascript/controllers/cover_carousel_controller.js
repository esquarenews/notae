import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["screen", "label", "dot"]
  static values = { initialIndex: Number }

  connect() {
    this.index = this.hasInitialIndexValue ? this.normalizeIndex(this.initialIndexValue) : 0
    this.render()
  }

  previous() {
    this.goTo(this.index - 1)
  }

  next() {
    this.goTo(this.index + 1)
  }

  select(event) {
    this.goTo(event.params.index)
  }

  goTo(index) {
    if (this.screenTargets.length === 0) return

    this.index = this.normalizeIndex(index)
    this.render()
  }

  normalizeIndex(index) {
    const total = this.screenTargets.length
    if (total === 0) return 0

    const normalized = Number(index)
    if (!Number.isFinite(normalized)) return 0

    return ((Math.trunc(normalized) % total) + total) % total
  }

  render() {
    this.screenTargets.forEach((screen, index) => {
      const isActive = index === this.index
      screen.hidden = !isActive
      screen.classList.toggle("is-active", isActive)
    })

    if (this.hasLabelTarget) {
      const activeScreen = this.screenTargets[this.index]
      this.labelTarget.textContent = activeScreen?.dataset.coverCarouselLabel || ""
    }

    this.dotTargets.forEach((dot, index) => {
      const isActive = index === this.index
      dot.classList.toggle("is-active", isActive)
      dot.setAttribute("aria-current", isActive ? "true" : "false")
    })
  }
}
