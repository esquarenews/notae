import { Controller } from "@hotwired/stimulus"
import { emojiSearchMatches } from "controllers/emoji_search"

export default class extends Controller {
  static targets = ["form", "input", "searchInput", "option", "section", "emptyState"]

  connect() {
    this.filter()
  }

  choose(event) {
    event.preventDefault()

    const iconValue = event.currentTarget.dataset.iconValue
    if (!iconValue || !this.hasFormTarget || !this.hasInputTarget) return

    this.inputTarget.value = iconValue
    this.formTarget.requestSubmit()
  }

  filter() {
    const query = this.hasSearchInputTarget ? this.searchInputTarget.value.trim() : ""
    const allowTypos = query.length > 0 && !this.optionTargets.some((option) => {
      const searchText = `${option.dataset.searchText || ""} ${option.dataset.iconValue || ""}`
      return emojiSearchMatches(searchText, query, { allowTypos: false })
    })
    let anyVisible = false

    this.sectionTargets.forEach((section) => {
      const options = section.querySelectorAll("[data-emoji-picker-target='option']")
      let visibleOptions = 0

      options.forEach((option) => {
        const searchText = `${option.dataset.searchText || ""} ${option.dataset.iconValue || ""}`
        const matches = emojiSearchMatches(searchText, query, { allowTypos })

        option.hidden = !matches
        option.setAttribute("aria-hidden", matches ? "false" : "true")

        if (matches) visibleOptions += 1
      })

      const showSection = visibleOptions > 0
      section.hidden = !showSection
      if (query.length > 0 && showSection) section.open = true
      if (showSection) anyVisible = true
    })

    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.hidden = query.length === 0 || anyVisible
    }
  }
}
