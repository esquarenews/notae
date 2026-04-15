import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["typeSelect", "panel", "draftInput", "list", "hiddenInputs"]
  static values = { dropdown: String }

  connect() {
    this.render()
  }

  typeChanged() {
    this.render()
  }

  handleKeydown(event) {
    if (event.key !== "Enter") return

    event.preventDefault()
    this.addOption()
  }

  addOption() {
    if (!this.isDropdownType()) return

    const value = this.draftInputTarget.value.trim()
    if (!value.length) return

    const existingValues = this.optionValues()
    if (existingValues.includes(value)) {
      this.draftInputTarget.value = ""
      return
    }

    const row = document.createElement("button")
    row.type = "button"
    row.className = "notae-db-column-option-pill"
    row.setAttribute("aria-label", `Remove ${value}`)
    row.dataset.value = value
    row.innerHTML = `
      <span class="notae-db-column-option-pill-label"></span>
      <span class="notae-db-column-option-pill-remove">×</span>
    `
    row.querySelector(".notae-db-column-option-pill-label").textContent = value
    row.addEventListener("click", () => {
      row.remove()
      this.syncHiddenInputs()
    })

    this.listTarget.appendChild(row)
    this.draftInputTarget.value = ""
    this.syncHiddenInputs()
  }

  render() {
    const show = this.isDropdownType()
    this.panelTarget.hidden = !show
    if (!show) {
      this.hiddenInputsTarget.innerHTML = ""
      this.listTarget.innerHTML = ""
      this.draftInputTarget.value = ""
    }
  }

  optionValues() {
    return Array.from(this.listTarget.querySelectorAll(".notae-db-column-option-pill"))
      .map((node) => node.dataset.value)
      .filter(Boolean)
  }

  syncHiddenInputs() {
    this.hiddenInputsTarget.innerHTML = ""
    this.optionValues().forEach((value) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "db_property[select_options_json][]"
      input.value = value
      this.hiddenInputsTarget.appendChild(input)
    })
  }

  isDropdownType() {
    return this.typeSelectTarget.value === this.dropdownValue
  }
}
