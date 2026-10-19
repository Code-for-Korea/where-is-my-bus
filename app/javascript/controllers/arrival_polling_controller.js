import { Controller } from "@hotwired/stimulus"
import { ga4Event } from "ga4"

// 버스가 가까울수록 자주 확인한다 — 배차가 긴 노선에서 도착 임박 신호가 늦지 않도록.
// 요청은 읽기 전용이라 SQLite 쓰기(GPS 수신)와 잠금을 경합하지 않는다.
const POLL_INTERVAL_MS = {
  far: 10000,  // 3개 정류장 이상 전 / 운행 정보 없음
  mid: 5000,   // 2개 정류장 전
  near: 3000   // 1개 정류장 전 이하
}

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
    clearTimeout(this.timer)
    document.removeEventListener("debug:refresh", this._onDebugRefresh)
    document.removeEventListener("turbo:before-cache", this._onBeforeCache)
  }

  async poll() {
    clearTimeout(this.timer)

    // 진행 중 요청이 있으면 스킵 — 응답이 다음 폴링을 예약한다
    if (this._polling) return
    this._polling = true

    let delay = POLL_INTERVAL_MS.far
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

      delay = this.nextDelayMs(data)
    } catch {
      // 네트워크 오류 시 현재 표시 유지하고 기본 주기로 재시도
    } finally {
      this._polling = false
      this.schedulePoll(delay)
    }
  }

  schedulePoll(delay) {
    this.timer = setTimeout(() => {
      if (document.hidden) {
        this.schedulePoll(delay)
      } else {
        this.poll()
      }
    }, delay)
  }

  nextDelayMs(data) {
    if (data.status === "no_data" || data.status === "no_trip") return POLL_INTERVAL_MS.far

    const stops = data.stops_away
    if (stops == null) return POLL_INTERVAL_MS.far
    if (stops <= 1)    return POLL_INTERVAL_MS.near
    if (stops === 2)   return POLL_INTERVAL_MS.mid
    return POLL_INTERVAL_MS.far
  }
}
