import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["region", "route", "stop", "overlay"]
  static values  = { autoOpen: Boolean, selectErrorMessage: String }

  connect() {
    if (this.autoOpenValue) this.open()
  }

  open() {
    const el = this.hasOverlayTarget ? this.overlayTarget : this.element
    el.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    const el = this.hasOverlayTarget ? this.overlayTarget : this.element
    el.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  onRegionChange() {
    // DB 연결 후 동적 로딩 예정
  }

  onRouteChange() {
    // DB 연결 후 동적 로딩 예정
  }

  confirm() {
    const region = this.regionTarget.value
    const stopId = this.stopTarget.value
    if (!region || !stopId) {
      this.showError(this.selectErrorMessageValue || "지역과 정류장을 선택해주세요.")
      return
    }

    const selectedStop = this.stopTarget.options[this.stopTarget.selectedIndex]
    if (selectedStop && selectedStop.dataset.region && selectedStop.dataset.region !== region) {
      this.showError(this.selectErrorMessageValue || "지역과 정류장을 선택해주세요.")
      return
    }

    this.hideError()
    const locale = document.documentElement.lang
    const prefix = locale && locale !== "ko" ? `/${locale}` : ""
    window.location.href = `${prefix}/r/${region}/${stopId}`
  }

  showError(message) {
    let el = this.element.querySelector("[data-error-toast]")
    if (!el) return
    el.textContent = message
    el.classList.remove("opacity-0", "translate-y-2")
    el.classList.add("opacity-100", "translate-y-0")
    clearTimeout(this._errorTimer)
    this._errorTimer = setTimeout(() => this.hideError(), 3000)
  }

  hideError() {
    const el = this.element.querySelector("[data-error-toast]")
    if (!el) return
    el.classList.remove("opacity-100", "translate-y-0")
    el.classList.add("opacity-0", "translate-y-2")
  }
}
