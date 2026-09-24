import { Controller } from "@hotwired/stimulus"
import { passkeysSupported, conditionalMediationAvailable, getPasskey, postJSON, friendlyError } from "../lib/webauthn"

// Passkey sign-in on the sign-in page. Where the browser supports it, saved
// passkeys are offered right in the email field's autofill; the button
// starts the same ceremony explicitly (and works with phones via QR code).
export default class extends Controller {
  static targets = ["button", "error"]
  static values = { optionsUrl: String, createUrl: String }

  async connect() {
    if (!passkeysSupported()) return

    this.buttonTarget.hidden = false
    if (await conditionalMediationAvailable()) this.start(true)
  }

  disconnect() {
    this.controller?.abort()
  }

  signIn() {
    this.start(false)
  }

  async start(conditional) {
    this.controller?.abort()
    const controller = (this.controller = new AbortController())
    this.showError(null)
    try {
      const options = await postJSON(this.optionsUrlValue)
      const credential = await getPasskey(options, { conditional, signal: controller.signal })
      const result = await postJSON(this.createUrlValue, { credential })
      window.location.assign(result.redirect)
    } catch (error) {
      if (controller.signal.aborted) return
      // Dismissing the autofill prompt isn't an error worth showing.
      if (conditional && error?.name === "NotAllowedError") return
      this.showError(friendlyError(error))
    }
  }

  showError(message) {
    this.errorTarget.textContent = message || ""
    this.errorTarget.hidden = !message
  }
}
