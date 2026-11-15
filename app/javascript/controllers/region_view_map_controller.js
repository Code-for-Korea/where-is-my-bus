import { Controller } from "@hotwired/stimulus"

// 지역 상세 화면의 읽기 전용 지도. 지역의 영역(bbox)을 사각형으로 보여 주고 그 범위로 맞춘다.
// 영역이 없으면 가까운 상위 지역의 영역을 점선으로, 그것도 없으면 세계 지도를 보여 준다.
// 지도는 보조 수단이라 Leaflet을 못 불러오면 지도 영역만 숨긴다.
export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    ownBounds: Array,      // 이 지역이 직접 가진 [[남, 서], [북, 동]]. 없으면 빈 배열
    fallbackBounds: Array  // 상위 지역까지 포함한 영역. 없으면 빈 배열
  }

  static WORLD = { center: [ 20, 0 ], zoom: 2 }

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

    this.map = L.map(this.canvasTarget)
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
    }).addTo(this.map)

    if (this.valid(this.ownBoundsValue)) {
      this.show(L, this.ownBoundsValue, { color: "#4f46e5", weight: 2, fillOpacity: 0.08 })
    } else if (this.valid(this.fallbackBoundsValue)) {
      this.show(L, this.fallbackBoundsValue, { color: "#6b7280", weight: 2, dashArray: "6 6", fillOpacity: 0.04 })
    } else {
      this.map.setView(this.constructor.WORLD.center, this.constructor.WORLD.zoom)
    }
  }

  disconnect() {
    this.connected = false
    this.map?.remove()
    this.map = null
  }

  valid(bounds) {
    return Array.isArray(bounds) && bounds.length === 2
  }

  show(L, bounds, style) {
    L.rectangle(bounds, style).addTo(this.map)
    this.map.fitBounds(bounds, { padding: [ 16, 16 ] })
  }
}
