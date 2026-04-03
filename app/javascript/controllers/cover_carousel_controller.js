import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "screen",
    "label",
    "dot",
    "uploadForm",
    "uploadSubmit",
    "uploadSpinner",
    "applyForm",
    "applyAction",
    "applyAssetId",
    "applyRemoteId",
    "unsplashDialog",
    "unsplashSearchInput",
    "unsplashGrid",
    "unsplashStatus",
    "unsplashStatusLabel",
    "unsplashEmptyState",
    "unsplashPageLabel",
    "unsplashPreviousButton",
    "unsplashNextButton"
  ]

  static values = {
    initialIndex: Number,
    unsplashUrl: String,
    perPage: Number
  }

  connect() {
    this.index = this.hasInitialIndexValue ? this.normalizeIndex(this.initialIndexValue) : 0
    this.unsplashCache = new Map()
    this.unsplashState = { query: "", page: 1, totalPages: 1 }
    this.searchTimer = null
    this.render()
  }

  disconnect() {
    if (this.searchTimer) window.clearTimeout(this.searchTimer)
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

  startInlineSubmit() {
    this.element.classList.add("is-submitting")
  }

  startUploadSubmit() {
    this.startInlineSubmit()
    if (this.hasUploadSubmitTarget) this.uploadSubmitTarget.disabled = true
    if (this.hasUploadSpinnerTarget) this.uploadSpinnerTarget.hidden = false
  }

  openUnsplash(event) {
    if (event) event.preventDefault()
    if (!this.hasUnsplashDialogTarget) return

    this.unsplashDialogTarget.showModal()
    if (this.hasUnsplashSearchInputTarget) this.unsplashSearchInputTarget.focus()

    const currentQuery = this.currentUnsplashQuery()
    const page = this.unsplashState.query === currentQuery ? this.unsplashState.page : 1
    this.loadUnsplashPage(page)
  }

  closeUnsplash(event) {
    if (event) event.preventDefault()
    if (!this.hasUnsplashDialogTarget || !this.unsplashDialogTarget.open) return

    this.unsplashDialogTarget.close()
  }

  backdropClose(event) {
    if (!this.hasUnsplashDialogTarget) return
    if (event.target !== this.unsplashDialogTarget) return

    this.closeUnsplash()
  }

  queueUnsplashSearch() {
    if (this.searchTimer) window.clearTimeout(this.searchTimer)

    this.searchTimer = window.setTimeout(() => {
      this.loadUnsplashPage(1)
    }, 220)
  }

  previousUnsplashPage() {
    const previousPage = Math.max(1, this.unsplashState.page - 1)
    if (previousPage === this.unsplashState.page) return

    this.loadUnsplashPage(previousPage)
  }

  nextUnsplashPage() {
    const nextPage = this.unsplashState.page + 1
    if (this.unsplashState.totalPages > 0 && nextPage > this.unsplashState.totalPages) return

    this.loadUnsplashPage(nextPage)
  }

  selectUnsplash(event) {
    event.preventDefault()

    const photoId = event.currentTarget.dataset.photoId
    if (!photoId || !this.hasApplyFormTarget) return

    this.startInlineSubmit()
    this.showUnsplashLoading("Downloading cover…")
    this.applyActionTarget.value = "unsplash"
    this.applyAssetIdTarget.value = ""
    this.applyRemoteIdTarget.value = photoId
    this.applyFormTarget.requestSubmit()
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

  async loadUnsplashPage(page, options = {}) {
    const prefetch = options.prefetch === true
    const query = this.currentUnsplashQuery()
    const cacheKey = this.unsplashCacheKey(query, page)
    const cached = this.unsplashCache.get(cacheKey)

    if (cached) {
      if (!prefetch) this.renderUnsplashPage(cached)
      if (!prefetch) this.prefetchNextPage(cached)
      return cached
    }

    if (!this.hasUnsplashUrlValue || this.unsplashUrlValue.length === 0) {
      if (!prefetch) this.showUnsplashError("Unsplash is not configured.")
      return null
    }

    if (!prefetch) {
      this.showUnsplashLoading(query.length === 0 ? "Loading popular covers…" : "Searching Unsplash…")
    }

    const url = new URL(this.unsplashUrlValue, window.location.origin)
    url.searchParams.set("page", String(page))
    url.searchParams.set("per_page", String(this.perPage()))
    if (query.length > 0) url.searchParams.set("q", query)

    try {
      const response = await fetch(url.toString(), {
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      })
      const data = await response.json().catch(() => ({}))

      if (!response.ok) {
        throw new Error(data.error || "Unable to load Unsplash covers.")
      }

      const normalized = {
        photos: Array.isArray(data.photos) ? data.photos : [],
        page: Number(data.page || page),
        totalPages: Number(data.total_pages || 0),
        query
      }

      this.unsplashCache.set(cacheKey, normalized)
      if (!prefetch) this.renderUnsplashPage(normalized)
      if (!prefetch) this.prefetchNextPage(normalized)
      return normalized
    } catch (error) {
      if (!prefetch) this.showUnsplashError(error.message || "Unable to load Unsplash covers.")
      return null
    }
  }

  renderUnsplashPage(data) {
    this.unsplashState = {
      query: data.query,
      page: data.page,
      totalPages: data.totalPages
    }

    if (this.hasUnsplashGridTarget) {
      this.unsplashGridTarget.innerHTML = data.photos.map((photo) => this.unsplashCardHtml(photo)).join("")
      this.unsplashGridTarget.hidden = data.photos.length === 0
    }

    if (this.hasUnsplashEmptyStateTarget) {
      this.unsplashEmptyStateTarget.hidden = data.photos.length > 0
    }

    if (this.hasUnsplashStatusTarget) {
      this.unsplashStatusTarget.hidden = true
      this.unsplashStatusTarget.classList.remove("is-error")
    }

    if (this.hasUnsplashPageLabelTarget) {
      this.unsplashPageLabelTarget.textContent = data.totalPages > 0 ? `Page ${data.page} of ${data.totalPages}` : `Page ${data.page}`
    }

    if (this.hasUnsplashPreviousButtonTarget) {
      this.unsplashPreviousButtonTarget.disabled = data.page <= 1
    }

    if (this.hasUnsplashNextButtonTarget) {
      this.unsplashNextButtonTarget.disabled = data.totalPages > 0 ? data.page >= data.totalPages : data.photos.length < this.perPage()
    }
  }

  prefetchNextPage(data) {
    const nextPage = data.page + 1
    if (data.totalPages > 0 && nextPage > data.totalPages) return

    this.loadUnsplashPage(nextPage, { prefetch: true })
  }

  showUnsplashLoading(message) {
    if (this.hasUnsplashStatusTarget) {
      this.unsplashStatusTarget.hidden = false
      this.unsplashStatusTarget.classList.remove("is-error")
    }
    if (this.hasUnsplashStatusLabelTarget) this.unsplashStatusLabelTarget.textContent = message
    if (this.hasUnsplashGridTarget) this.unsplashGridTarget.hidden = true
    if (this.hasUnsplashEmptyStateTarget) this.unsplashEmptyStateTarget.hidden = true
  }

  showUnsplashError(message) {
    if (this.hasUnsplashGridTarget) this.unsplashGridTarget.hidden = true
    if (this.hasUnsplashEmptyStateTarget) this.unsplashEmptyStateTarget.hidden = true
    if (!this.hasUnsplashStatusTarget) return

    this.unsplashStatusTarget.hidden = false
    this.unsplashStatusTarget.classList.add("is-error")
    if (this.hasUnsplashStatusLabelTarget) this.unsplashStatusLabelTarget.textContent = message
  }

  currentUnsplashQuery() {
    return this.hasUnsplashSearchInputTarget ? this.unsplashSearchInputTarget.value.trim() : ""
  }

  perPage() {
    return this.hasPerPageValue ? this.perPageValue : 12
  }

  unsplashCacheKey(query, page) {
    return `${query.toLowerCase()}::${page}`
  }

  unsplashCardHtml(photo) {
    const imageUrl = this.escapeHtml(photo.preview_url || photo.full_url || "")
    const altText = this.escapeHtml(photo.alt || "Unsplash photo")
    const artistName = this.escapeHtml(photo.artist_name || "Unsplash artist")
    const artistUrl = this.escapeHtml(photo.artist_url || "#")
    const sourceName = this.escapeHtml(photo.source_name || "Unsplash")
    const sourceUrl = this.escapeHtml(photo.source_url || "#")
    const photoId = this.escapeHtml(photo.id || "")

    return `
      <article class="notae-cover-unsplash-card">
        <button type="button"
                class="notae-cover-unsplash-tile"
                title="Double-click to use this cover"
                data-action="dblclick->cover-carousel#selectUnsplash"
                data-photo-id="${photoId}">
          <img src="${imageUrl}" alt="${altText}" loading="lazy" decoding="async">
        </button>
        <div class="notae-cover-unsplash-meta">
          <strong>${artistName}</strong>
          <span>Double-click to use</span>
          <p class="notae-cover-picker-credit">
            Photo by
            <a href="${artistUrl}" target="_blank" rel="noopener noreferrer">${artistName}</a>
            on
            <a href="${sourceUrl}" target="_blank" rel="noopener noreferrer">${sourceName}</a>
          </p>
        </div>
      </article>
    `
  }

  escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;")
  }
}
