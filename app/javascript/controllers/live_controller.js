import { Controller } from "@hotwired/stimulus"

// Live household updates over SSE. Subscribes to the household stream on the
// dashboard and the public wall; on task_update events it swaps the affected
// person card with a freshly fetched fragment, and shows a browser
// notification when the event concerns the current user. Pauses when the tab
// is hidden to save battery on the kiosk.
export default class extends Controller {
  static values = { householdId: Number, userId: Number, token: String }

  connect() {
    this.connectStream()

    this.onVisibilityChange = () => {
      if (document.hidden) {
        this.disconnectStream()
      } else {
        this.connectStream()
        this.refreshAll()
      }
    }
    document.addEventListener("visibilitychange", this.onVisibilityChange)
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisibilityChange)
    this.disconnectStream()
  }

  connectStream() {
    if (this.source) return
    this.source = new EventSource(this.streamUrl)
    this.source.addEventListener("task_update", (event) => {
      this.handleEvent(JSON.parse(event.data))
    })
  }

  disconnectStream() {
    this.source?.close()
    this.source = null
  }

  get streamUrl() {
    const params = this.hasTokenValue ? `?token=${encodeURIComponent(this.tokenValue)}` : ""
    return `/households/${this.householdIdValue}/stream${params}`
  }

  cardUrl(userId) {
    const params = this.hasTokenValue ? `?token=${encodeURIComponent(this.tokenValue)}` : ""
    return `/households/${this.householdIdValue}/cards/${userId}${params}`
  }

  handleEvent(data) {
    if (this.hasUserIdValue && data.assigned_to_id === this.userIdValue) {
      this.notify(data)
    }
    this.refreshCard(data)
  }

  async refreshCard(data) {
    if (!data.assigned_to_id) return this.refreshAll()

    const card = this.element.querySelector(`[data-user-id="${data.assigned_to_id}"]`)
    if (!card) return this.refreshAll()

    const response = await fetch(this.cardUrl(data.assigned_to_id), { headers: { Accept: "text/html" } })
    if (!response.ok) return
    const html = await response.text()
    const template = document.createElement("template")
    template.innerHTML = html.trim()
    card.replaceWith(template.content)
  }

  async refreshAll() {
    const response = await fetch(window.location.href, { headers: { Accept: "text/html" } })
    if (!response.ok) return
    const html = await response.text()
    const doc = new DOMParser().parseFromString(html, "text/html")
    const freshGrid = doc.querySelector(".dashboard-grid")
    if (freshGrid) {
      this.element.innerHTML = freshGrid.innerHTML
    }
  }

  notify(data) {
    if (!("Notification" in window) || Notification.permission !== "granted") return

    new Notification("Family Status", {
      body: `Task updated (#${data.task_id})`,
      tag: `task-${data.task_id}`
    })
  }
}