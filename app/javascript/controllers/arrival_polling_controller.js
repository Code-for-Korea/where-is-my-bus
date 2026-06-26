import { Controller } from "@hotwired/stimulus"
import { ga4Event } from "../ga4"

export default class extends Controller {
  static targets = ["eta", "stopsAway", "busMarker"]
  static values  = {
    url: String,
    stopName: String,
    busNumber: String,
    noDataLine1: String,
    noDataLine2: String,
    arrivedLine1: String,
    arrivedLine2: String,
    stopsAwaySuffix: String,
    etaPrefix: String,
    etaSuffixBefore: String,
    etaSuffixAfter: String
  }

  connect() {
    this._statusFired = false
    this.poll()
    this.timer = setInterval(() => {
      if (!document.hidden) this.poll()
    }, 5000)
    this._onDebugRefresh = () => this.poll()
    document.addEventListener("debug:refresh", this._onDebugRefresh)

    this._onBeforeCache = () => {
      if (this.hasStopsAwayTarget) this.stopsAwayTarget.innerHTML = ""
      if (this.hasEtaTarget)       this.etaTarget.innerHTML = ""
      if (this.hasBusMarkerTarget) this.busMarkerTarget.style.left = "50%"
    }
    document.addEventListener("turbo:before-cache", this._onBeforeCache)
  }

  disconnect() {
    clearInterval(this.timer)
    document.removeEventListener("debug:refresh", this._onDebugRefresh)
    document.removeEventListener("turbo:before-cache", this._onBeforeCache)
  }

  async poll() {
    try {
      const res  = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      const data = await res.json()

      if (data.status === "no_data" || data.status === "no_trip") {
        if (!this._statusFired) {
          ga4Event("arrival_status", { status: data.status, stop_name: this.stopNameValue, bus_number: this.busNumberValue })
          this._statusFired = true
        }
        if (this.hasStopsAwayTarget) this.stopsAwayTarget.innerHTML = ""
        if (this.hasEtaTarget)       this.etaTarget.innerHTML = `${this.noDataLine1Value}<br>${this.noDataLine2Value}`
        return
      }

      if (!this._statusFired) {
        ga4Event("arrival_status", { status: "running", stop_name: this.stopNameValue, bus_number: this.busNumberValue })
        this._statusFired = true
      }

      if (data.stops_away === 0) {
        if (this.hasStopsAwayTarget) this.stopsAwayTarget.innerHTML = ""
        if (this.hasEtaTarget)       this.etaTarget.innerHTML = `${this.arrivedLine1Value}<br>${this.arrivedLine2Value}`
      } else {
        if (this.hasStopsAwayTarget) {
          this.stopsAwayTarget.innerHTML = `${data.stops_away}${this.stopsAwaySuffixValue}`
        }
        if (this.hasEtaTarget) {
          this.etaTarget.innerHTML = `${this.etaPrefixValue}${data.eta_minutes}${this.etaSuffixBeforeValue}<br>${this.etaSuffixAfterValue}`
        }
      }

      if (this.hasBusMarkerTarget) {
        let pct
        if (data.bar_pct != null) {
          pct = data.bar_pct
        } else {
          const stops = data.stops_away ?? 1
          if      (stops >= 3) pct = 3
          else if (stops === 2) pct = 15
          else if (stops === 1) pct = 30
          else                  pct = 90
        }
        this.busMarkerTarget.style.left = `${pct}%`
      }
    } catch {
      // 네트워크 오류 시 현재 표시 유지
    }
  }
}
