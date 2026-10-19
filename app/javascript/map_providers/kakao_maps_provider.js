import { BaseMapProvider } from "map_providers/base_map_provider"

// Kakao Maps JS SDK v2 — 공식 로드 계약: `autoload=false`로 스크립트를 읽은 뒤
// `kakao.maps.load(cb)`로 v3 본체를 로드한다(Google의 `&callback=` 파라미터는 없음).
const SVG_NS = "http://www.w3.org/2000/svg"

function markerImageSrc(svg) {
  return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`
}

// Google provider와 같은 시각 체계 — 정류장 파란 원, 버스 빨간 화살표(흰 테두리)
const STOP_SVG = `<svg xmlns="${SVG_NS}" width="14" height="14" viewBox="0 0 14 14"><circle cx="7" cy="7" r="5.5" fill="#3b82f6" stroke="#ffffff" stroke-width="2"/></svg>`
const BUS_SVG = `<svg xmlns="${SVG_NS}" width="16" height="16" viewBox="0 0 16 16"><path d="M10.5 2.5 L5 8 L10.5 13.5" fill="none" stroke="#ef4444" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/></svg>`

export class KakaoMapsProvider extends BaseMapProvider {
  render(center, stops, buses) {
    if (!KakaoMapsProvider.isAvailable()) {
      this.canvas.innerHTML = `<div class="flex h-full items-center justify-center text-sm text-gray-500 p-6 text-center">Kakao Maps가 로드되지 않았습니다.</div>`
      return
    }

    this.map = new kakao.maps.Map(this.canvas, {
      center: new kakao.maps.LatLng(center.lat, center.lng),
      level: 3
    })

    const stopIcon = new kakao.maps.MarkerImage(
      markerImageSrc(STOP_SVG),
      new kakao.maps.Size(14, 14),
      { offset: new kakao.maps.Point(7, 7) }
    )
    const busIcon = new kakao.maps.MarkerImage(
      markerImageSrc(BUS_SVG),
      new kakao.maps.Size(16, 16),
      { offset: new kakao.maps.Point(8, 8) }
    )

    stops.forEach((stop) => {
      new kakao.maps.Marker({
        map: this.map,
        position: new kakao.maps.LatLng(stop.lat, stop.lng),
        title: stop.name,
        image: stopIcon
      })
    })

    buses.forEach((bus) => {
      new kakao.maps.Marker({
        map: this.map,
        position: new kakao.maps.LatLng(bus.lat, bus.lng),
        title: bus.number,
        image: busIcon
      })
    })
  }

  static isAvailable() {
    return typeof kakao !== "undefined" && !!kakao.maps && typeof kakao.maps.Map === "function"
  }
}
