import { Controller } from "@hotwired/stimulus"

// Submits its form when a control changes (the household switcher).
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
