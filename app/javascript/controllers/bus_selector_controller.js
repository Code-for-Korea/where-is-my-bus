import { Controller } from "@hotwired/stimulus"
import { ga4Event } from "ga4"

// 정류장 → 노선을 고르는 바텀시트. origin/main의 "지역 → 노선 → 정류장" 선택을 우리 데이터에 맞게 바꿨다.
export default class extends Controller {
  static targets = ["stop", "route", "overlay"]
  static values  = { autoOpen: Boolean, selectErrorMessage: String }

  connect() {
    if (this.hasStopTarget && this.stopTarget.value) this.filterRoutes()
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

  onStopChange() {
    this.filterRoutes()
  }

  // 고른 정류장에 서는 노선만 보이게 하고, 하나뿐이면 자동으로 고른다.
  filterRoutes() {
    const stopId = this.stopTarget.value
    let matches = []

    Array.from(this.routeTarget.options).forEach((option) => {
      if (!option.value) return
      const served = stopId === "" || option.dataset.stops.split(",").includes(stopId)
      option.hidden = !served
      option.disabled = !served
      if (served) matches.push(option)
    })

    const selected = this.routeTarget.selectedOptions[0]
    if (selected && selected.value && selected.disabled) this.routeTarget.value = ""
    if (stopId !== "" && matches.length === 1) this.routeTarget.value = matches[0].value
  }

  confirm() {
    const stopId = this.stopTarget.value
    const routeId = this.routeTarget.value
    if (!stopId || !routeId) {
      this.showError(this.selectErrorMessageValue || "정류장과 노선을 선택해주세요.")
      return
    }

    this.hideError()
    ga4Event("select_bus", {
      bus_number: this.routeTarget.selectedOptions[0]?.text,
      stop_name:  this.stopTarget.selectedOptions[0]?.text
    })
    window.location.href = `/stops/${stopId}/routes/${routeId}`
  }

  showError(message) {
    const el = this.element.querySelector("[data-error-toast]")
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
