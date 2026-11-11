import { Controller } from "@hotwired/stimulus"

// 지역 폼의 영역(bbox) 지도. 지도를 원하는 범위에 맞춘 뒤 버튼으로 남·서·북·동 입력칸을 채운다.
// 지도는 보조 수단이라 Leaflet을 못 불러와도 숫자 칸으로 입력할 수 있다.
//
// 시작 위치: 입력칸의 영역 → 이 지역의 저장된 영역 → 상위 지역(없으면 전국)의 영역 → 세계 지도
export default class extends Controller {
  static targets = ["south", "west", "north", "east", "canvas", "status"]
  static values = {
    initialBounds: Array,   // 이 지역이 가진 [[남, 서], [북, 동]]. 없으면 빈 배열
    fallbackBounds: Array   // 상위 지역 또는 전국의 범위. 없으면 빈 배열
  }

  static WORLD_CENTER = [ 20, 0 ]
  static WORLD_ZOOM = 2

  async connect() {
    this.connected = true
    let L
    try {
      L = await import("leaflet")
    } catch (error) {
      console.error("Leaflet을 불러오지 못했습니다", error)
      this.canvasTarget.classList.add("hidden")
      this.showStatus("지도를 불러오지 못했습니다. 영역을 직접 입력하세요.", true)
      return
    }
    if (!this.connected) return // 불러오는 사이 다른 화면으로 이동했다

    this.L = L
    this.map = L.map(this.canvasTarget)
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
    }).addTo(this.map)

    this.setInitialView()
  }

  disconnect() {
    this.connected = false
    this.map?.remove()
    this.map = null
    this.rectangle = null
  }

  setInitialView() {
    const current = this.inputBounds()
    if (current) {
      this.drawRectangle(current)
      this.map.fitBounds(current)
    } else if (this.hasBounds(this.initialBoundsValue)) {
      this.map.fitBounds(this.initialBoundsValue)
    } else if (this.hasBounds(this.fallbackBoundsValue)) {
      this.map.fitBounds(this.fallbackBoundsValue)
    } else {
      this.map.setView(this.constructor.WORLD_CENTER, this.constructor.WORLD_ZOOM)
    }
  }

  // 지금 보이는 지도 범위를 입력칸에 쓴다. 저장은 폼을 제출할 때 된다.
  useCurrentView() {
    if (!this.map) return
    const view = this.map.getBounds()
    // 축소한 세계 지도는 ±180, ±90을 넘을 수 있어 서버가 받는 범위로 자른다.
    const bounds = [
      [ this.clamp(view.getSouth(), 90), this.clamp(view.getWest(), 180) ],
      [ this.clamp(view.getNorth(), 90), this.clamp(view.getEast(), 180) ]
    ]
    this.southTarget.value = bounds[0][0].toFixed(6)
    this.westTarget.value = bounds[0][1].toFixed(6)
    this.northTarget.value = bounds[1][0].toFixed(6)
    this.eastTarget.value = bounds[1][1].toFixed(6)
    this.drawRectangle(bounds)
    this.showStatus("현재 지도 범위를 영역 칸에 채웠습니다. 저장하면 반영됩니다.")
  }

  clear() {
    this.allInputs().forEach((input) => { input.value = "" })
    this.removeRectangle()
    this.showStatus("영역을 비웠습니다. 저장하면 반영됩니다.")
  }

  // 입력칸을 직접 고치면 사각형이 따라간다(지도는 움직이지 않는다). 올바른 영역이 아니면 사각형을 지운다.
  syncFromInputs() {
    if (!this.map) return
    const bounds = this.inputBounds()
    if (bounds) {
      this.drawRectangle(bounds)
    } else {
      this.removeRectangle()
    }
  }

  drawRectangle(bounds) {
    if (this.rectangle) {
      this.rectangle.setBounds(bounds)
    } else {
      this.rectangle = this.L.rectangle(bounds, { color: "#4f46e5", weight: 2, fillOpacity: 0.1 }).addTo(this.map)
    }
  }

  removeRectangle() {
    this.rectangle?.remove()
    this.rectangle = null
  }

  allInputs() {
    return [ this.southTarget, this.westTarget, this.northTarget, this.eastTarget ]
  }

  // 네 칸이 모두 범위 안의 숫자이고 남 <= 북, 서 <= 동일 때만 [[남, 서], [북, 동]]. 아니면 null.
  inputBounds() {
    const south = this.parseCoordinate(this.southTarget.value, 90)
    const west = this.parseCoordinate(this.westTarget.value, 180)
    const north = this.parseCoordinate(this.northTarget.value, 90)
    const east = this.parseCoordinate(this.eastTarget.value, 180)
    if ([ south, west, north, east ].includes(null)) return null
    if (south > north || west > east) return null
    return [ [ south, west ], [ north, east ] ]
  }

  parseCoordinate(text, limit) {
    if (text.trim() === "") return null
    const value = Number(text)
    return Number.isFinite(value) && Math.abs(value) <= limit ? value : null
  }

  clamp(value, limit) {
    return Math.max(-limit, Math.min(limit, value))
  }

  hasBounds(bounds) {
    return Array.isArray(bounds) && bounds.length === 2
  }

  showStatus(message, isError = false) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("text-red-600", isError)
    this.statusTarget.classList.toggle("text-gray-400", !isError)
  }
}
