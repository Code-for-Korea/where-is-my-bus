import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["count", "button"]
  static values  = { url: String, liked: Boolean }

  async like() {
    if (this.likedValue) return

    try {
      const res = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Accept": "application/json"
        }
      })
      const data = await res.json()
      this.countTarget.textContent = data.count
      this.likedValue = true
      if (this.hasButtonTarget) {
        this.buttonTarget.classList.add("opacity-50", "cursor-not-allowed")
      }
    } catch {
      // 네트워크 오류 시 무시
    }
  }
}
