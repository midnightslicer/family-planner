import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import {
  pushKey, pushSupported, isIos, isStandalone, currentSubscription, endpointDigest,
  subscribe, unsubscribe, post
} from "../lib/push"

// "This device" on the Notifications page (shared/_push_panel). Shows one of:
//
//   unavailable  the server has no push key
//   unsupported  this browser can't do push
//   ios          iPhone/iPad in a Safari tab: add to Home Screen first
//   prompt       a "Turn on notifications" button (never prompts by itself)
//   denied       blocked in the browser/phone settings: how to undo that
//   on           subscribed and known to the server: "Send a test", "Turn off"
//
// Also marks this device's row in the device list (`device` targets carry
// a SHA-256 of their endpoint in data-digest).
export default class extends Controller {
  static targets = ["state", "checking", "error", "notice", "device", "button"]
  static values = { subscribeUrl: String, unsubscribeUrl: String, testUrl: String, known: Array }

  connect() {
    this.refresh()
  }

  async refresh() {
    try {
      this.show(await this.currentState())
    } catch (error) {
      this.show("prompt")
      this.fail(error)
    }
  }

  async currentState() {
    if (!pushKey()) return "unavailable"
    if (!pushSupported()) return isIos() && !isStandalone() ? "ios" : "unsupported"
    if (Notification.permission === "denied") return "denied"

    const subscription = await currentSubscription()
    if (!subscription) return "prompt"

    const digest = await endpointDigest(subscription)
    this.deviceTargets.forEach((row) => {
      const marker = row.querySelector("[data-this-device]")
      if (marker) marker.hidden = row.dataset.digest !== digest
    })
    return Notification.permission === "granted" && this.knownValue.includes(digest) ? "on" : "prompt"
  }

  async enable() {
    this.busy(true)
    try {
      const permission = await subscribe(this.subscribeUrlValue)
      if (permission === "granted") {
        this.reload()
      } else {
        this.show(permission === "denied" ? "denied" : "prompt")
      }
    } catch (error) {
      this.fail(error)
    } finally {
      this.busy(false)
    }
  }

  async test() {
    this.busy(true)
    try {
      const subscription = await currentSubscription()
      await post(this.testUrlValue, { endpoint: subscription?.endpoint })
      this.say("Sent. It should arrive in a few seconds. Nothing? Check that notifications for this app are allowed in your phone's settings.")
    } catch (error) {
      this.fail(error)
      if (error.status === 410) {
        // The server forgot this device; show the "Turn on" state again.
        await currentSubscription().then((subscription) => subscription?.unsubscribe()).catch(() => {})
        this.show("prompt")
      }
    } finally {
      this.busy(false)
    }
  }

  async disable() {
    this.busy(true)
    try {
      await unsubscribe(this.unsubscribeUrlValue)
      this.reload()
    } catch (error) {
      this.fail(error)
    } finally {
      this.busy(false)
    }
  }

  // Re-render the page so the device list matches.
  reload() {
    Turbo.visit(window.location.href, { action: "replace" })
  }

  show(state) {
    if (this.hasCheckingTarget) this.checkingTarget.hidden = true
    this.stateTargets.forEach((element) => (element.hidden = element.dataset.state !== state))
    this.element.dataset.pushState = state
  }

  busy(on) {
    this.buttonTargets.forEach((button) => (button.disabled = on))
    if (on) {
      this.errorTarget.hidden = true
      this.noticeTarget.hidden = true
    }
  }

  say(message) {
    this.noticeTarget.textContent = message
    this.noticeTarget.hidden = false
  }

  fail(error) {
    this.errorTarget.textContent = error?.message || "Something went wrong. Try again."
    this.errorTarget.hidden = false
  }
}
