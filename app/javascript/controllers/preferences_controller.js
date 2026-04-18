import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "autoTimeZoneForm",
    "autoTimeZoneToggle",
    "autoTimeZoneValue",
    "timeZoneSelect",
    "themeSelect",
    "openLinksToggle"
  ]

  connect() {
    this.applyThemeClass(this.currentThemePreference())
    this.syncTimeZoneInputState()
    this.syncOpenLinksPreference()
    this.syncSystemTimeZone(false)
  }

  handleThemeChange() {
    this.applyThemeClass(this.currentThemePreference())
  }

  handleAutoTimeZoneChange() {
    this.syncTimeZoneInputState()
    if (this.autoTimeZoneToggleTarget.checked) {
      this.syncSystemTimeZone(true)
      return
    }

    this.autoTimeZoneFormTarget.requestSubmit()
  }

  handleOpenLinksChange() {
    this.syncOpenLinksPreference()
  }

  syncSystemTimeZone(submit) {
    if (!this.hasAutoTimeZoneValueTarget) return

    const detectedTimeZone = Intl.DateTimeFormat().resolvedOptions().timeZone
    if (!detectedTimeZone) return

    const previousValue = this.autoTimeZoneValueTarget.value
    this.autoTimeZoneValueTarget.value = detectedTimeZone

    if (submit || (this.autoTimeZoneToggleTarget.checked && previousValue !== detectedTimeZone)) {
      this.autoTimeZoneFormTarget.requestSubmit()
    }
  }

  currentThemePreference() {
    return this.hasThemeSelectTarget ? this.themeSelectTarget.value : null
  }

  applyThemeClass(themePreference) {
    if (!(document.body instanceof HTMLElement)) return

    document.body.classList.remove("notae-theme-light", "notae-theme-dark", "notae-theme-system")
    document.body.classList.add(`notae-theme-${themePreference || "light"}`)
  }

  syncTimeZoneInputState() {
    if (!this.hasTimeZoneSelectTarget || !this.hasAutoTimeZoneToggleTarget) return

    this.timeZoneSelectTarget.disabled = this.autoTimeZoneToggleTarget.checked
  }

  syncOpenLinksPreference() {
    if (!(document.body instanceof HTMLElement) || !this.hasOpenLinksToggleTarget) return

    document.body.dataset.linkPreferencesOpenLinksInNewWindowValue = this.openLinksToggleTarget.checked ? "true" : "false"
  }
}
