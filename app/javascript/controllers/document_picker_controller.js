import { Controller } from "@hotwired/stimulus"

const SEARCH_DEBOUNCE_MS = 160

export default class extends Controller {
  static targets = ["searchInput", "hiddenInput", "results", "loading", "emptyState"]
  static values = {
    searchUrl: String,
    emptyText: String
  }

  connect() {
    this.loaded = false
    this.lastQuery = null
    this.searchTimer = null
    this.abortController = null
  }

  disconnect() {
    if (this.searchTimer) window.clearTimeout(this.searchTimer)
    if (this.abortController) this.abortController.abort()
  }

  ensureLoaded() {
    if (this.loaded) return

    this.fetchResults("")
  }

  queueSearch() {
    if (this.searchTimer) window.clearTimeout(this.searchTimer)

    this.searchTimer = window.setTimeout(() => {
      this.fetchResults(this.searchQuery())
    }, SEARCH_DEBOUNCE_MS)
  }

  choose(event) {
    event.preventDefault()

    const button = event.currentTarget
    const targetId = button.dataset.documentPickerId
    if (!targetId || !this.hasHiddenInputTarget) return

    this.hiddenInputTarget.value = targetId
    this.hiddenInputTarget.form?.requestSubmit()
  }

  async fetchResults(query) {
    if (!this.hasResultsTarget || !this.hasSearchUrlValue || !this.searchUrlValue) return
    if (this.loaded && this.lastQuery === query) return

    if (this.abortController) this.abortController.abort()
    this.abortController = new AbortController()
    this.setLoading(true)

    try {
      const requestUrl = new URL(this.searchUrlValue, window.location.origin)
      if (query.length > 0) {
        requestUrl.searchParams.set("q", query)
      } else {
        requestUrl.searchParams.delete("q")
      }

      const response = await fetch(requestUrl.toString(), {
        headers: {
          Accept: "application/json",
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin",
        signal: this.abortController.signal
      })
      if (!response.ok) return

      const payload = await response.json()
      const results = Array(payload?.data?.results)
      this.renderResults(results)
      this.loaded = true
      this.lastQuery = query
    } catch (error) {
      if (error.name !== "AbortError") {
        this.renderResults([])
      }
    } finally {
      this.setLoading(false)
    }
  }

  renderResults(results) {
    if (!this.hasResultsTarget) return

    this.resultsTarget.innerHTML = ""

    results.forEach((result) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "notae-document-picker-result"
      button.dataset.action = "document-picker#choose"
      button.dataset.documentPickerId = result.id

      const label = document.createElement("span")
      label.className = "notae-document-picker-result-label"
      label.textContent = result.label || "Untitled"
      button.appendChild(label)

      if (result.meta) {
        const meta = document.createElement("span")
        meta.className = "notae-document-picker-result-meta"
        meta.textContent = result.meta
        button.appendChild(meta)
      }

      this.resultsTarget.appendChild(button)
    })

    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.hidden = results.length > 0
      if (!this.emptyStateTarget.hidden && this.hasEmptyTextValue && this.emptyTextValue) {
        this.emptyStateTarget.textContent = this.emptyTextValue
      }
    }
  }

  setLoading(loading) {
    if (!this.hasLoadingTarget) return

    this.loadingTarget.hidden = !loading
  }

  searchQuery() {
    return this.hasSearchInputTarget ? this.searchInputTarget.value.trim() : ""
  }
}
