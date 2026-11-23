import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import {
  pushKey, pushSupported, isIos, isStandalone, currentSubscription, endpointDigest,
  subscribe, unsubscribe, post, pushUnavailable, notificationsSupported, showLocalNotification
} from "../lib/push"

// "This device" on the Notifications page (shared/_push_panel). Shows one of:
//
//   unavailable  the server has no push key
//   unsupported  this browser can't do push
//   ios          iPhone/iPad in a Safari tab: add to Home Screen first
//   prompt       a "Turn on notifications" button (never prompts by itself)
//   denied       blocked in the browser/phone settings: how to undo that
//   on           subscribed and known to the server: "Send a test", "Turn off"
//   local        notifications allowed but no push in this browser (Brave on
//                a computer): they show while the app is open in a tab
//
// Also marks this device's row in the device list (`device` targets carry
// a SHA-256 of their endpoint in data-digest).
export default class extends Controller {
  static targets = ["state", "checking", "error", "notice", "device", "button", "brave"]
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
    if (isIos() && !isStandalone() && !pushSupported()) return "ios"
    if (!notificationsSupported()) return "unsupported"
    if (Notification.permission === "denied") return "denied"
    if (!pushSupported()) return Notification.permission === "granted" ? "local" : "prompt"

    const subscription = await currentSubscription()
    if (!subscription) return Notification.permission === "granted" && pushUnavailable() ? "local" : "prompt"

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
      if (!pushSupported()) {
        const permission = await Notification.requestPermission()
        this.show(permission === "granted" ? "local" : permission === "denied" ? "denied" : "prompt")
        return
      }
      const permission = await subscribe(this.subscribeUrlValue)
      if (permission === "granted") {
        this.reload()
      } else {
        this.show(permission === "denied" ? "denied" : "prompt")
      }
    } catch (error) {
      if (error.pushUnavailable) {
        this.show("local")
      } else {
        this.fail(error)
      }
    } finally {
      this.busy(false)
    }
  }

  // "Show a test" where there's no push: straight from this page.
  async testLocal() {
    this.busy(true)
    try {
      const shown = await showLocalNotification(document.title.split(" · ").pop(), { body: "Notifications are working in this browser.", tag: "test" })
      if (shown) this.say("Shown. Nothing? Check that notifications for this site are allowed in your browser and computer settings.")
      else this.fail(new Error("This browser wouldn't show it. Try reloading the page."))
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
    this.braveTargets.forEach((element) => (element.hidden = !navigator.brave))
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
