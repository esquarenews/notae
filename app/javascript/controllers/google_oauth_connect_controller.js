import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["label", "ownerScope"]
  static values = {
    url: String
  }

  navigate(event) {
    if (!this.hasUrlValue) return

    event.preventDefault()

    const destination = new URL(this.urlValue, window.location.origin)
    const label = this.hasLabelTarget ? this.labelTarget.value.toString().trim() : ""
    const ownerScope = this.hasOwnerScopeTarget ? this.ownerScopeTarget.value.toString().trim() : ""

    if (label.length > 0) destination.searchParams.set("label", label)
    if (ownerScope.length > 0) destination.searchParams.set("owner_scope", ownerScope)

    window.location.assign(destination.toString())
  }
}
