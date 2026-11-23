// Browser half of push notifications. The layout carries two meta tags
// while someone is signed in and the server has a VAPID key:
//
//   <meta name="push-key" content="<base64url public key>">
//   <meta name="push-user" content="<user id>">
//
// subscribe() asks permission (it must run straight from a tap) and
// registers this browser with the server. syncSubscription() runs on every
// page load and quietly repairs things without ever prompting: after the
// server's key changed (resubscribe) or someone else signed in on this
// device (the server moves the device to them).

const SYNCED = "push-synced" // localStorage: "<user id>|<endpoint>" the server last accepted

export function pushKey() {
  return document.querySelector('meta[name="push-key"]')?.content || ""
}

function pushUser() {
  return document.querySelector('meta[name="push-user"]')?.content || ""
}

export function pushSupported() {
  return window.isSecureContext && "serviceWorker" in navigator && "PushManager" in window && "Notification" in window
}

// iPhones and iPads only offer push to apps added to the Home Screen.
export function isIos() {
  return /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)
}

export function isStandalone() {
  return window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true
}

export async function registration() {
  return navigator.serviceWorker.register("/service-worker.js", { scope: "/" })
}

export async function currentSubscription() {
  if (!pushSupported()) return null
  const reg = await navigator.serviceWorker.getRegistration("/")
  return reg ? reg.pushManager.getSubscription() : null
}

// Asks for permission (call from a click), then subscribes and registers.
// Returns the permission the person chose.
export async function subscribe(url) {
  const permission = await Notification.requestPermission()
  if (permission !== "granted") return permission

  const reg = await registration()
  await navigator.serviceWorker.ready
  let subscription = await reg.pushManager.getSubscription()
  if (subscription && !sameKey(subscription)) {
    await subscription.unsubscribe()
    subscription = null
  }
  subscription ||= await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: decode(pushKey()) })
  await register(url, subscription)
  return permission
}

export async function unsubscribe(url) {
  const subscription = await currentSubscription()
  if (!subscription) return
  await post(url, { endpoint: subscription.endpoint }).catch(() => {})
  await subscription.unsubscribe()
  localStorage.removeItem(SYNCED)
}

export async function syncSubscription(url) {
  try {
    if (!pushKey() || !pushUser() || !pushSupported() || Notification.permission !== "granted") return
    let subscription = await currentSubscription()
    if (!subscription) return // never turned on here, or turned off: leave it

    if (!sameKey(subscription)) {
      // The server has a new key (storage/.vapid_key was lost or replaced):
      // the old subscription is dead, and permission is already granted.
      await subscription.unsubscribe()
      const reg = await registration()
      subscription = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: decode(pushKey()) })
    }
    if (localStorage.getItem(SYNCED) !== marker(subscription)) await register(url, subscription)
  } catch (error) {
    console.warn("Couldn't check this device's notifications", error)
  }
}

export async function register(url, subscription) {
  await post(url, { subscription: subscription.toJSON() })
  localStorage.setItem(SYNCED, marker(subscription))
}

// The server lists your devices by a SHA-256 of their endpoint, so the page
// can tell which one is this browser without echoing endpoints back.
export async function endpointDigest(subscription) {
  const bytes = new TextEncoder().encode(subscription.endpoint)
  const digest = await crypto.subtle.digest("SHA-256", bytes)
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("")
}

export async function post(url, body) {
  const token = document.querySelector("meta[name='csrf-token']")?.content
  const response = await fetch(url, {
    method: "POST",
    credentials: "same-origin",
    headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": token || "" },
    body: JSON.stringify(body)
  })
  if (!response.ok) {
    let message = `The server said ${response.status}.`
    try {
      message = (await response.json()).error || message
    } catch {}
    throw Object.assign(new Error(message), { status: response.status })
  }
  return response.status === 204 ? {} : response.json().catch(() => ({}))
}

function marker(subscription) {
  return `${pushUser()}|${subscription.endpoint}`
}

function sameKey(subscription) {
  const key = subscription.options?.applicationServerKey
  if (!key) return true // older browsers don't say; assume it's ours
  return encode(key) === pushKey()
}

function decode(base64url) {
  const base64 = base64url.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(base64url.length / 4) * 4, "=")
  return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0))
}

function encode(buffer) {
  return btoa(String.fromCharCode(...new Uint8Array(buffer))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}
