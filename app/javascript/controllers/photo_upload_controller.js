import { Controller } from "@hotwired/stimulus"

// Photo picker with a crop step, for people, pets and locations (rendered by
// shared/_photo_picker). Choosing a file opens a dialog where the photo can be
// dragged and zoomed under a mask (round for faces, square for places); "Use
// photo" renders that square at `size` px and puts it back into the file
// input. With `autosave` (the profile) it then saves the form; otherwise the
// photo goes up with the rest of the form.
//
// Doing it in the browser means a 6 MB phone photo uploads as ~20 KB, the
// server needs no image library, and re-encoding through a canvas drops the
// photo's metadata (camera, GPS location). Previews use data: URLs because
// the CSP allows those for images and not blob: URLs.
//
// Without JavaScript the plain file input stays visible and uploads as-is.
const MAX_ZOOM = 4

export default class extends Controller {
  static targets = ["input", "choose", "preview", "error", "remove", "dialog", "canvas", "zoom"]
  static values = {
    shape: { type: String, default: "round" },
    size: { type: Number, default: 256 },
    autosave: { type: Boolean, default: true }
  }

  connect() {
    this.inputTarget.hidden = true
    this.chooseTarget.hidden = false
  }

  disconnect() {
    this.bitmap?.close?.()
  }

  choose() {
    this.inputTarget.value = ""
    this.inputTarget.click()
  }

  // A file was picked: decode it and open the cropper.
  async open() {
    const file = this.inputTarget.files[0]
    this.errorTarget.hidden = true
    if (!file) return

    try {
      this.bitmap?.close?.()
      this.bitmap = await createImageBitmap(file)
    } catch {
      this.inputTarget.value = ""
      this.showError("That file couldn't be read as a picture. Try a JPEG or PNG.")
      return
    }

    this.dialogTarget.showModal()
    this.sizeStage()
    this.zoomTarget.value = 1
    this.zoom = 1
    // Start centred, just covering the circle.
    const { width, height } = this.bitmap
    const scale = this.baseScale
    this.x = (this.stage - width * scale) / 2
    this.y = (this.stage - height * scale) / 2
    this.draw()
  }

  cancel() {
    this.inputTarget.value = ""
    this.dialogTarget.close()
  }

  // The dialog's own Escape/close: same as Cancel unless "Use photo" closed
  // it. The close event arrives after close() returns, so the flag is
  // cleared here, not in apply(): clearing it there made this handler wipe
  // the cropped photo out of the input before forms without autosave were
  // submitted.
  closed() {
    if (!this.saving) this.inputTarget.value = ""
    this.saving = false
  }

  async apply() {
    this.saving = true
    const canvas = document.createElement("canvas")
    const output = this.sizeValue
    canvas.width = canvas.height = output
    this.paint(canvas.getContext("2d"), output / this.stage)

    // WebP where the browser can encode it (Safari can't), JPEG otherwise.
    let blob = await toBlob(canvas, "image/webp")
    if (!blob || blob.type !== "image/webp") blob = await toBlob(canvas, "image/jpeg")
    const ext = blob.type === "image/webp" ? "webp" : "jpg"

    const transfer = new DataTransfer()
    transfer.items.add(new File([blob], `photo.${ext}`, { type: blob.type }))
    this.inputTarget.files = transfer.files
    if (this.hasRemoveTarget) this.removeTarget.checked = false

    this.showPreview(canvas.toDataURL("image/png"))
    this.dialogTarget.close()
    if (this.autosaveValue) this.element.closest("form").requestSubmit()
  }

  // ---- Dragging, zooming, nudging ----

  grab(event) {
    event.preventDefault()
    this.canvasTarget.setPointerCapture(event.pointerId)
    this.drag = { x: event.clientX, y: event.clientY }
  }

  move(event) {
    if (!this.drag) return
    const ratio = this.stage / this.canvasTarget.getBoundingClientRect().width
    this.x += (event.clientX - this.drag.x) * ratio
    this.y += (event.clientY - this.drag.y) * ratio
    this.drag = { x: event.clientX, y: event.clientY }
    this.draw()
  }

  release() {
    this.drag = null
  }

  zoomed() {
    this.setZoom(parseFloat(this.zoomTarget.value))
  }

  wheel(event) {
    event.preventDefault()
    this.setZoom(this.zoom * (event.deltaY < 0 ? 1.08 : 1 / 1.08))
  }

  nudge(event) {
    const step = event.shiftKey ? 20 : 5
    const moves = { ArrowLeft: [step, 0], ArrowRight: [-step, 0], ArrowUp: [0, step], ArrowDown: [0, -step] }
    if (event.key === "+" || event.key === "=") return this.setZoom(this.zoom * 1.1)
    if (event.key === "-") return this.setZoom(this.zoom / 1.1)
    const delta = moves[event.key]
    if (!delta) return
    event.preventDefault()
    this.x += delta[0]
    this.y += delta[1]
    this.draw()
  }

  // ---- Drawing ----

  get baseScale() {
    return this.stage / Math.min(this.bitmap.width, this.bitmap.height)
  }

  setZoom(zoom) {
    zoom = Math.min(MAX_ZOOM, Math.max(1, zoom))
    // Zoom about the centre of the circle.
    const before = this.baseScale * this.zoom
    const after = this.baseScale * zoom
    const centre = this.stage / 2
    this.x = centre - ((centre - this.x) * after) / before
    this.y = centre - ((centre - this.y) * after) / before
    this.zoom = zoom
    this.zoomTarget.value = zoom
    this.draw()
  }

  // The canvas's layout width, not getBoundingClientRect(): the dialog opens
  // with a scale-up animation, and the transformed (~40%) size gave the
  // canvas too few pixels, so the crop preview looked blurry. (The upload is
  // rendered separately at full size and was always sharp.)
  sizeStage() {
    const canvas = this.canvasTarget
    const dpr = window.devicePixelRatio || 1
    this.stage = canvas.clientWidth || 280
    canvas.width = canvas.height = Math.round(this.stage * dpr)
    this.dpr = dpr
  }

  draw() {
    // Keep the photo covering the whole square, so no empty corners.
    const scale = this.baseScale * this.zoom
    const w = this.bitmap.width * scale
    const h = this.bitmap.height * scale
    this.x = Math.min(0, Math.max(this.stage - w, this.x))
    this.y = Math.min(0, Math.max(this.stage - h, this.y))

    const ctx = this.canvasTarget.getContext("2d")
    ctx.setTransform(1, 0, 0, 1, 0, 0)
    ctx.clearRect(0, 0, this.canvasTarget.width, this.canvasTarget.height)
    this.paint(ctx, this.dpr)
    this.shade(ctx)
  }

  // Dim everything outside the mask (on screen only, not in the upload) and
  // outline it. Colours come from the theme tokens.
  shade(ctx) {
    const styles = getComputedStyle(this.canvasTarget)
    const size = this.stage * this.dpr
    const r = size / 2
    const outline = (inset) => {
      if (this.shapeValue === "square") ctx.roundRect(inset, inset, size - inset * 2, size - inset * 2, size * 0.08)
      else ctx.arc(r, r, r - inset, 0, Math.PI * 2)
    }
    ctx.save()
    ctx.beginPath()
    ctx.rect(0, 0, size, size)
    outline(1)
    ctx.fillStyle = styles.getPropertyValue("--crop-shade").trim()
    ctx.fill("evenodd")
    ctx.beginPath()
    outline(this.dpr)
    ctx.lineWidth = 2 * this.dpr
    ctx.strokeStyle = styles.getPropertyValue("--accent").trim()
    ctx.stroke()
    ctx.restore()
  }

  paint(ctx, factor) {
    const scale = this.baseScale * this.zoom
    ctx.imageSmoothingQuality = "high"
    ctx.drawImage(
      this.bitmap,
      this.x * factor, this.y * factor,
      this.bitmap.width * scale * factor, this.bitmap.height * scale * factor
    )
  }

  showPreview(url) {
    const img = document.createElement("img")
    img.src = url
    img.alt = ""
    this.previewTarget.replaceChildren(img)
    this.previewTarget.classList.remove("is-new")
    void this.previewTarget.offsetWidth // restart the pop animation
    this.previewTarget.classList.add("is-new")
  }

  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }
}

function toBlob(canvas, type) {
  return new Promise((resolve) => canvas.toBlob(resolve, type, 0.9))
}
