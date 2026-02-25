import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["autoTimeZoneForm", "autoTimeZoneToggle", "autoTimeZoneValue"]

  connect() {
    this.syncSystemTimeZone(false)
  }

  handleAutoTimeZoneChange() {
    if (this.autoTimeZoneToggleTarget.checked) {
      this.syncSystemTimeZone(true)
      return
    }

    this.autoTimeZoneFormTarget.requestSubmit()
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
}
