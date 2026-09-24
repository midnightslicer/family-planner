// Browser half of passkeys. The server sends options in the WebAuthn JSON
// shape (binary fields as base64url); these helpers turn them into the
// ArrayBuffers navigator.credentials wants, and turn the resulting
// credential back into JSON for the server to verify.

export function passkeysSupported() {
  return window.isSecureContext && typeof window.PublicKeyCredential === "function" && !!navigator.credentials
}

export async function conditionalMediationAvailable() {
  if (!passkeysSupported() || !PublicKeyCredential.isConditionalMediationAvailable) return false
  try {
    return await PublicKeyCredential.isConditionalMediationAvailable()
  } catch {
    return false
  }
}

export async function createPasskey(options) {
  const publicKey = {
    ...options,
    challenge: decode(options.challenge),
    user: { ...options.user, id: decode(options.user.id) },
    excludeCredentials: (options.excludeCredentials || []).map((c) => ({ ...c, id: decode(c.id) }))
  }
  const credential = await navigator.credentials.create({ publicKey })
  const response = credential.response
  return {
    id: credential.id,
    rawId: encode(credential.rawId),
    type: credential.type,
    response: {
      clientDataJSON: encode(response.clientDataJSON),
      attestationObject: encode(response.attestationObject),
      transports: typeof response.getTransports === "function" ? response.getTransports() : []
    }
  }
}

// `signal` lets a pending conditional (autofill) request be aborted when the
// person clicks the explicit passkey button instead.
export async function getPasskey(options, { conditional = false, signal } = {}) {
  const publicKey = {
    ...options,
    challenge: decode(options.challenge),
    allowCredentials: (options.allowCredentials || []).map((c) => ({ ...c, id: decode(c.id) }))
  }
  const request = { publicKey, signal }
  if (conditional) request.mediation = "conditional"
  const credential = await navigator.credentials.get(request)
  const response = credential.response
  return {
    id: credential.id,
    rawId: encode(credential.rawId),
    type: credential.type,
    response: {
      clientDataJSON: encode(response.clientDataJSON),
      authenticatorData: encode(response.authenticatorData),
      signature: encode(response.signature),
      userHandle: response.userHandle ? encode(response.userHandle) : null
    }
  }
}

// POSTs to the app with the page's CSRF token and returns the parsed JSON
// reply. A FormData body goes as a normal form post (so Rails nests
// user[...] fields); anything else is sent as JSON.
export async function postJSON(url, body = {}) {
  const token = document.querySelector("meta[name='csrf-token']")?.content
  const isForm = body instanceof FormData
  const headers = { Accept: "application/json", "X-CSRF-Token": token || "" }
  if (!isForm) headers["Content-Type"] = "application/json"
  const response = await fetch(url, {
    method: "POST",
    credentials: "same-origin",
    headers,
    body: isForm ? body : JSON.stringify(body)
  })
  const data = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(data.error || "Something went wrong. Please try again.")
  return data
}

// Maps the DOMExceptions browsers throw to something a person can act on.
export function friendlyError(error) {
  switch (error?.name) {
    case "NotAllowedError":
      return "The passkey request was cancelled or timed out."
    case "InvalidStateError":
      return "This device already has a passkey for your account."
    case "SecurityError":
      return "Passkeys need a secure (https) connection to this site."
    case "AbortError":
      return null
    default:
      return error?.message || "Something went wrong with the passkey."
  }
}

function decode(base64url) {
  const base64 = base64url.replace(/-/g, "+").replace(/_/g, "/")
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4)
  const binary = atob(padded)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes.buffer
}

function encode(buffer) {
  const bytes = new Uint8Array(buffer)
  let binary = ""
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i])
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}
