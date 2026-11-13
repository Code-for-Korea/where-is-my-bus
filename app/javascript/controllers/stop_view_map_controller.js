import { Controller } from "@hotwired/stimulus"

// 정류장 상세 화면의 읽기 전용 지도. 정류장 좌표에 마커 하나를 보여 준다.
// 지도는 보조 수단이라 Leaflet을 못 불러오면 지도 영역만 숨기고 나머지 정보는 그대로 보여 준다.
export default class extends Controller {
  static targets = ["canvas"]
  static values = { lat: Number, lng: Number }

  static ZOOM = 17

  async connect() {
    this.connected = true
    let L
    try {
      L = await import("leaflet")
    } catch (error) {
      console.error("Leaflet을 불러오지 못했습니다", error)
      this.canvasTarget.classList.add("hidden")
      return
    }
    if (!this.connected) return // 불러오는 사이 다른 화면으로 이동했다

    const position = [ this.latValue, this.lngValue ]
    this.map = L.map(this.canvasTarget).setView(position, this.constructor.ZOOM)
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
    }).addTo(this.map)
    L.marker(position).addTo(this.map)
  }

  disconnect() {
    this.connected = false
    this.map?.remove()
    this.map = null
  }
}
