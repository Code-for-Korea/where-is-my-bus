import { Controller } from "@hotwired/stimulus"

// 정류장 폼의 좌표 선택 지도. 위도/경도 입력칸과 Leaflet 마커를 양방향으로 맞춘다.
// 지도는 보조 수단이라 Leaflet을 못 불러와도 입력칸으로 등록할 수 있다.
//
// 시작 위치: 입력칸의 좌표 → 정류장에 고른 지역의 범위
//           → 브라우저 현재 위치 → 전국 범위 → 세계 지도
// 지역을 새로 고르면 마커·좌표가 있어도 지도는 그 지역으로 옮긴다(좌표는 바꾸지 않는다).
// 위치 응답을 기다리는 동안은 전국(없으면 세계) 지도를 보여 주고, 마커가 없고 지도를 움직이지 않았고
// 지역도 고르지 않았을 때만 현재 위치로 옮긴다.
export default class extends Controller {
  static targets = ["lat", "lng", "canvas", "status"]
  static values = {
    regionBounds: Array,   // 정류장에 고른 지역의 [[남, 서], [북, 동]]. 없으면 빈 배열
    countryBounds: Array   // 활성 최상위 지역 전체의 범위. 없으면 빈 배열
  }

  static ZOOM = { stop: 17, located: 16, world: 2 }
  static WORLD_CENTER = [ 20, 0 ]
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
    } else if (this.hasBounds(this.regionBoundsValue)) {
      this.fitBounds(this.regionBoundsValue)
    } else {
      // 위치 응답을 기다리는 동안 전국(없으면 세계) 지도를 보여 주고, 얻으면 옮긴다.
      this.showCountry()
      this.moveToCurrentLocation()
    }
  }

  // 지역 선택이 바뀌면 그 범위로 지도를 옮긴다. 마커와 입력한 좌표는 그대로 둔다(옮기는 건 보는 위치뿐).
  fitRegion(event) {
    if (!this.map) return
    this.regionChosen = true
    const bounds = event.detail?.bounds
    if (this.hasBounds(bounds)) this.fitBounds(bounds)
  }

  showCountry() {
    if (this.hasBounds(this.countryBoundsValue)) {
      this.fitBounds(this.countryBoundsValue)
    } else {
      this.map.setView(this.constructor.WORLD_CENTER, this.constructor.ZOOM.world)
    }
  }

  hasBounds(bounds) {
    return Array.isArray(bounds) && bounds.length === 2
  }

  // 아주 작은 영역이라도 정류장 입력에 적당한 확대 수준을 넘지 않게 한다.
  fitBounds(bounds) {
    this.map.fitBounds(bounds, { maxZoom: this.constructor.ZOOM.stop })
  }

  moveToCurrentLocation() {
    if (!navigator.geolocation) return
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => {
        // 그 사이 사용자가 마커를 놓았거나 지도를 움직였거나 지역을 골랐으면 건드리지 않는다.
        if (!this.map || this.marker || this.userMovedMap || this.regionChosen) return
        this.map.setView([coords.latitude, coords.longitude], this.constructor.ZOOM.located)
      },
      () => {}, // 거부·시간 초과·미지원이면 보이는 지도를 그대로 쓴다.
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
