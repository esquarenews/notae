import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["draftTypeSelect", "targetSystemSelect", "section"]
  static values = { targetMatrix: Object }

  connect() {
    this.sync()
  }

  sync() {
    const draftType = this.currentDraftType()
    if (!draftType) return

    this.toggleSections(draftType)
    this.syncTargetSystems(draftType)
  }

  currentDraftType() {
    if (this.hasDraftTypeSelectTarget) return this.draftTypeSelectTarget.value

    const hiddenDraftType = this.element.querySelector("input[name='agent_action[draft_type]']")
    return hiddenDraftType?.value || ""
  }

  toggleSections(draftType) {
    this.sectionTargets.forEach((section) => {
      const draftTypes = (section.dataset.draftTypes || "").split(/\s+/).filter(Boolean)
      section.hidden = !draftTypes.includes(draftType)
    })
  }

  syncTargetSystems(draftType) {
    if (!this.hasTargetSystemSelectTarget) return

    const allowedSystems = this.targetMatrixValue[draftType] || []
    let selectedValueAllowed = false

    Array.from(this.targetSystemSelectTarget.options).forEach((option) => {
      const allowed = allowedSystems.includes(option.value)
      option.disabled = !allowed
      option.hidden = !allowed
      if (allowed && option.selected) selectedValueAllowed = true
    })

    if (!selectedValueAllowed) {
      const firstAllowed = Array.from(this.targetSystemSelectTarget.options).find((option) => !option.disabled)
      if (firstAllowed) this.targetSystemSelectTarget.value = firstAllowed.value
    }
  }
}
