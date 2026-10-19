import { BaseMapProvider } from "map_providers/base_map_provider"
import L from "leaflet"

// OpenStreetMap 타일 + Leaflet — API 키가 필요 없다(사용 정책상 과도한 타일 요청만 금지).
// 자체호스팅 모듈이라 비동기 로드가 없고 render가 즉시 실행된다.
const OSM_TILE_URL = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
const OSM_ATTRIBUTION = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> 기여자'

function busIcon() {
  return L.divIcon({
    className: "",
    html: `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><path d="M10.5 2.5 L5 8 L10.5 13.5" fill="none" stroke="#ef4444" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
    iconSize: [16, 16],
    iconAnchor: [8, 8]
  })
}

export class OsmProvider extends BaseMapProvider {
  render(center, stops, buses) {
    this.map = L.map(this.canvas).setView([center.lat, center.lng], 14)
    L.tileLayer(OSM_TILE_URL, { attribution: OSM_ATTRIBUTION }).addTo(this.map)

    stops.forEach((stop) => {
      L.circleMarker([stop.lat, stop.lng], {
        radius: 6,
        color: "#ffffff",
        weight: 2,
        fillColor: "#3b82f6",
        fillOpacity: 1
      }).addTo(this.map).bindTooltip(stop.name)
    })

    buses.forEach((bus) => {
      L.marker([bus.lat, bus.lng], { icon: busIcon() }).addTo(this.map)
        .bindTooltip(bus.number)
    })
  }
}
