import { Controller } from "@hotwired/stimulus"
import { passkeysSupported, createPasskey, postJSON, friendlyError } from "../lib/webauthn"

// "Add a passkey" on the account page.
export default class extends Controller {
  static targets = ["button", "error", "unsupported"]
  static values = { optionsUrl: String, createUrl: String }

  connect() {
    const supported = passkeysSupported()
    this.buttonTarget.hidden = !supported
    if (this.hasUnsupportedTarget) this.unsupportedTarget.hidden = supported
  }

  async add() {
    this.showError(null)
    this.buttonTarget.disabled = true
    try {
      const options = await postJSON(this.optionsUrlValue)
      const credential = await createPasskey(options)
      const result = await postJSON(this.createUrlValue, { credential })
      window.location.assign(result.redirect)
    } catch (error) {
      this.buttonTarget.disabled = false
      this.showError(friendlyError(error))
    }
  }

  showError(message) {
    this.errorTarget.textContent = message || ""
    this.errorTarget.hidden = !message
  }
}
