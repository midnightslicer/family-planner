import { Controller } from "@hotwired/stimulus"
import { passkeysSupported, createPasskey, postJSON, friendlyError } from "../lib/webauthn"

// Sign-up forms (setup wizard, invitation links). Where passkeys work, the
// form defaults to creating one: submitting first asks the server to check
// the profile fields and hand back registration options, then the browser
// creates the passkey and the form is submitted with it attached. "Use a
// password instead" switches to a plain password field.
export default class extends Controller {
  static targets = ["passwordSection", "password", "passkeySection", "credential", "error", "submit", "toggle"]
  static values = { optionsUrl: String }

  connect() {
    this.usePasskey = passkeysSupported()
    if (this.hasToggleTarget) this.toggleTarget.hidden = !passkeysSupported()
    this.onSubmit = this.submit.bind(this)
    this.element.addEventListener("submit", this.onSubmit)
    this.render()
  }

  disconnect() {
    this.element.removeEventListener("submit", this.onSubmit)
  }

  toggle() {
    this.usePasskey = !this.usePasskey
    this.showError(null)
    this.render()
    if (!this.usePasskey) this.passwordTarget.focus()
  }

  render() {
    this.passwordSectionTarget.hidden = this.usePasskey
    this.passwordTarget.required = !this.usePasskey
    this.passwordTarget.disabled = this.usePasskey
    this.passkeySectionTarget.hidden = !this.usePasskey
    const { passkeyLabel, passwordLabel } = this.submitTarget.dataset
    this.submitTarget.value = this.usePasskey ? passkeyLabel : passwordLabel
    if (this.hasToggleTarget) {
      this.toggleTarget.textContent = this.usePasskey ? "Use a password instead" : "Use a passkey instead"
    }
  }

  async submit(event) {
    if (!this.usePasskey || this.credentialTarget.value) return

    event.preventDefault()
    if (!this.element.reportValidity()) return

    this.showError(null)
    this.submitTarget.disabled = true
    try {
      const options = await postJSON(this.optionsUrlValue, new FormData(this.element))
      const credential = await createPasskey(options)
      this.credentialTarget.value = JSON.stringify(credential)
      this.submitTarget.disabled = false
      this.element.requestSubmit()
    } catch (error) {
      this.submitTarget.disabled = false
      this.showError(friendlyError(error))
    }
  }

  showError(message) {
    this.errorTarget.textContent = message || ""
    this.errorTarget.hidden = !message
  }
}
