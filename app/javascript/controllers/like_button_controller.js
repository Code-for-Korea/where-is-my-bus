import { Controller } from "@hotwired/stimulus"
import { ga4Event } from "../ga4"

export default class extends Controller {
  static targets = ["count", "button"]
  static values  = { url: String, liked: Boolean, stopName: String, busNumber: String }

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
      ga4Event("like_stop", { stop_name: this.stopNameValue, bus_number: this.busNumberValue })
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
