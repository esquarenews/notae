import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit(event) {
    event.preventDefault()

    const form = this.element
    if (!(form instanceof HTMLFormElement)) return

    const action = form.getAttribute("action")
    if (!action) return

    const destination = new URL(action, window.location.origin)
    const params = new URLSearchParams(new FormData(form))
    params.forEach((value, key) => destination.searchParams.set(key, value))

    window.location.assign(destination.toString())
  }
}
