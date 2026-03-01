import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  formFor(event) {
    return event.target?.form || event.target?.closest("form")
  }

  submit(event) {
    const form = this.formFor(event)
    if (!form) return

    form.requestSubmit()
  }

  submitOnEnter(event) {
    event.preventDefault()
    const form = this.formFor(event)
    if (!form) return

    const createNextOnEnter = event.target?.dataset?.autoSubmitCreateNextRowOnEnter === "true"
    if (createNextOnEnter) {
      const createNextField = form.querySelector('input[name="db_row[create_next_row]"]')
      if (createNextField) createNextField.value = "1"
    }

    form.requestSubmit()
  }

  submitAndCreateNextOnEnter(event) {
    this.submitOnEnter(event)
  }

  navigate(event) {
    const destination = event.target?.value?.toString().trim()
    if (!destination) return

    window.location.assign(destination)
  }
}
