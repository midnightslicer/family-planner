import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// The pets "Where" board: drag a pet chip onto a place (a house has three
// zones: inside, outside, penned up), or tap chips to pick them and then
// tap the place. Pointer events, so a finger drags as well as a mouse.
// The chip moves at once and the move posts in the background
// (PetLocationsController#create, a turbo stream back with the flash); the
// household's live refresh then morphs the board to what was saved.
export default class extends Controller {
  static targets = ["zone", "comment", "status"]
  static values = { url: String }

  disconnect() {
    this.endDrag()
  }

  // ---- Dragging ----

  press(event) {
    if (event.button !== 0) return
    this.drag = { pet: event.currentTarget, x: event.clientX, y: event.clientY, id: event.pointerId, started: false }
    this.onMove = (e) => this.dragMove(e)
    this.onUp = (e) => this.dragEnd(e)
    window.addEventListener("pointermove", this.onMove)
    window.addEventListener("pointerup", this.onUp)
    window.addEventListener("pointercancel", this.onUp)
  }

  dragMove(event) {
    const drag = this.drag
    if (!drag || event.pointerId !== drag.id) return
    if (!drag.started) {
      if (Math.hypot(event.clientX - drag.x, event.clientY - drag.y) < 6) return
      this.startDrag(drag)
    }
    event.preventDefault()
    drag.ghost.style.transform = `translate(${event.clientX - drag.offsetX}px, ${event.clientY - drag.offsetY}px)`
    const zone = this.zoneAt(event.clientX, event.clientY)
    if (zone !== drag.over) {
      drag.over?.classList.remove("is-over")
      zone?.classList.add("is-over")
      drag.over = zone
    }
  }

  startDrag(drag) {
    drag.started = true
    // Dragging a picked chip takes every picked one along.
    drag.pets = drag.pet.classList.contains("is-selected") ? this.selectedPets() : [ drag.pet ]
    const rect = drag.pet.getBoundingClientRect()
    drag.offsetX = drag.x - rect.left
    drag.offsetY = drag.y - rect.top
    const ghost = drag.pet.cloneNode(true)
    ghost.removeAttribute("id")
    ghost.classList.add("move-ghost")
    ghost.style.width = `${rect.width}px`
    if (drag.pets.length > 1) ghost.dataset.count = drag.pets.length
    document.body.append(ghost)
    drag.ghost = ghost
    drag.pets.forEach((pet) => pet.classList.add("is-dragging"))
    this.element.classList.add("is-dragging")
  }

  dragEnd(event) {
    const drag = this.drag
    if (!drag || event.pointerId !== drag.id) return
    if (drag.started) {
      // The click that follows a drag isn't a tap.
      this.justDragged = true
      setTimeout(() => { this.justDragged = false }, 0)
      const zone = event.type === "pointerup" ? this.zoneAt(event.clientX, event.clientY) : null
      const pets = drag.pets
      this.endDrag()
      if (zone) this.moveTo(zone, pets)
    } else {
      this.endDrag()
    }
  }

  endDrag() {
    window.removeEventListener("pointermove", this.onMove)
    window.removeEventListener("pointerup", this.onUp)
    window.removeEventListener("pointercancel", this.onUp)
    const drag = this.drag
    this.drag = null
    if (!drag?.started) return
    drag.ghost.remove()
    drag.over?.classList.remove("is-over")
    drag.pets.forEach((pet) => pet.classList.remove("is-dragging"))
    this.element.classList.remove("is-dragging")
  }

  zoneAt(x, y) {
    const zone = document.elementFromPoint(x, y)?.closest("[data-move-board-target~='zone']")
    return zone && this.element.contains(zone) ? zone : null
  }

  // ---- Tapping ----

  tapPet(event) {
    event.stopPropagation()
    if (this.justDragged) return
    const pet = event.currentTarget
    const picked = !pet.classList.contains("is-selected")
    pet.classList.toggle("is-selected", picked)
    pet.setAttribute("aria-pressed", picked)
    const count = this.selectedPets().length
    this.say(count ? `${count} picked. Tap where ${count === 1 ? "it is" : "they are"}.` : "")
  }

  tapZone(event) {
    if (event.type === "keydown") {
      if (event.target !== event.currentTarget) return
      event.preventDefault()
    }
    const pets = this.selectedPets()
    if (pets.length === 0) return this.say("Tap a pet first, or drag it here.")
    this.moveTo(event.currentTarget, pets)
  }

  selectedPets() {
    return [ ...this.element.querySelectorAll(".move-pet.is-selected") ]
  }

  // ---- Moving ----

  moveTo(zone, pets) {
    pets.forEach((pet) => {
      pet.classList.remove("is-selected")
      pet.setAttribute("aria-pressed", "false")
    })
    const moving = pets.filter((pet) => pet.parentElement !== zone)
    if (moving.length === 0) return this.say("")
    moving.forEach((pet) => {
      zone.append(pet)
      pet.classList.remove("is-moved")
      void pet.offsetWidth // restart the landing animation
      pet.classList.add("is-moved")
    })
    this.say(`Saving: ${zone.dataset.label}…`)
    this.save(zone, moving)
  }

  async save(zone, pets) {
    const body = new FormData()
    pets.forEach((pet) => body.append("check_in[pet_ids][]", pet.dataset.petId))
    body.append("check_in[location_id]", zone.dataset.locationId)
    if (zone.dataset.spot) body.append("check_in[spot]", zone.dataset.spot)
    body.append("check_in[penned]", zone.dataset.penned || "0")
    const comment = this.hasCommentTarget ? this.commentTarget.value.trim() : ""
    if (comment) body.append("check_in[comment]", comment)

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        body,
        credentials: "same-origin",
        headers: {
          Accept: "text/vnd.turbo-stream.html",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        }
      })
      const html = await response.text()
      if (html) Turbo.renderStreamMessage(html)
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      if (this.hasCommentTarget) this.commentTarget.value = ""
      this.say("")
    } catch (error) {
      console.warn("Couldn't save the move", error)
      this.say("Couldn't save that. Check the connection and try again.")
      // Put the board back to what's actually saved.
      Turbo.visit(window.location.href, { action: "replace" })
    }
  }

  say(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}
