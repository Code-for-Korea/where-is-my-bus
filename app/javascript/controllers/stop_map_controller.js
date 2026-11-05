import { Controller } from "@hotwired/stimulus"

// 정류장 폼의 좌표 선택 지도. 위도/경도 입력칸과 Leaflet 마커를 양방향으로 맞춘다.
// 지도는 보조 수단이라 Leaflet을 못 불러와도 입력칸으로 등록할 수 있다.
//
// 시작 위치: 입력칸의 좌표 → 등록된 정류장들의 중심 → 브라우저 현재 위치 → 고정 기본 위치
export default class extends Controller {
  static targets = ["lat", "lng", "canvas", "status"]
  static values = {
    center: Array,   // 등록된 정류장 좌표의 평균. 정류장이 없으면 빈 배열
    fallback: Array  // 마지막 수단인 고정 위치
  }

  static ZOOM = { stop: 17, center: 14, located: 16, fallback: 14 }
  static LOCATE_TIMEOUT_MS = 5000

  async connect() {
    this.connected = true
    let L
    try {
      L = await import("leaflet")
    } catch (error) {
      console.error("Leaflet을 불러오지 못했습니다", error)
      this.canvasTarget.classList.add("hidden")
      this.showStatus("지도를 불러오지 못했습니다. 위도와 경도를 직접 입력하세요.", true)
      return
    }
    if (!this.connected) return // 불러오는 사이 다른 화면으로 이동했다

    this.L = L
    this.map = L.map(this.canvasTarget)
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
    }).addTo(this.map)
    this.map.on("click", (event) => this.placeMarker(event.latlng.wrap(), { writeInputs: true }))
    this.map.once("dragstart", () => { this.userMovedMap = true })

    this.setInitialView()
  }

  disconnect() {
    this.connected = false
    this.map?.remove()
    this.map = null
    this.marker = null
  }

  // 입력칸을 직접 고치면 마커가 따라간다. 숫자가 아니거나 범위를 벗어난 값은 무시한다.
  syncFromInputs() {
    if (!this.map) return
    const position = this.inputPosition()
    if (!position) return
    this.placeMarker(position, { writeInputs: false })
    this.map.panTo(position)
  }

  setInitialView() {
    const { ZOOM } = this.constructor
    const position = this.inputPosition()
    if (position) {
      this.placeMarker(position, { writeInputs: false })
      this.map.setView(position, ZOOM.stop)
    } else if (this.centerValue.length === 2) {
      this.map.setView(this.centerValue, ZOOM.center)
    } else {
      // 위치 응답을 기다리는 동안 기본 위치를 보여 주고, 얻으면 옮긴다.
      this.map.setView(this.fallbackValue, ZOOM.fallback)
      this.moveToCurrentLocation()
    }
  }

  moveToCurrentLocation() {
    if (!navigator.geolocation) return
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => {
        // 그 사이 사용자가 마커를 놓았거나 지도를 움직였으면 건드리지 않는다.
        if (!this.map || this.marker || this.userMovedMap) return
        this.map.setView([coords.latitude, coords.longitude], this.constructor.ZOOM.located)
      },
      () => {}, // 거부·시간 초과·미지원이면 기본 위치를 그대로 쓴다.
      { timeout: this.constructor.LOCATE_TIMEOUT_MS }
    )
  }

  placeMarker(latlng, { writeInputs }) {
    if (this.marker) {
      this.marker.setLatLng(latlng)
    } else {
      this.marker = this.L.marker(latlng, { draggable: true }).addTo(this.map)
      this.marker.on("dragend", () => this.writeInputs(this.marker.getLatLng().wrap()))
    }
    if (writeInputs) this.writeInputs(latlng)
  }

  // DB 컬럼 정밀도(소수점 6자리)에 맞춰 쓴다.
  writeInputs({ lat, lng }) {
    this.latTarget.value = lat.toFixed(6)
    this.lngTarget.value = lng.toFixed(6)
  }

  inputPosition() {
    const lat = this.parseCoordinate(this.latTarget.value, 90)
    const lng = this.parseCoordinate(this.lngTarget.value, 180)
    return lat === null || lng === null ? null : this.L.latLng(lat, lng)
  }

  parseCoordinate(text, limit) {
    if (text.trim() === "") return null
    const value = Number(text)
    return Number.isFinite(value) && Math.abs(value) <= limit ? value : null
  }

  showStatus(message, isError = false) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("text-red-600", isError)
    this.statusTarget.classList.toggle("text-gray-400", !isError)
  }
}
