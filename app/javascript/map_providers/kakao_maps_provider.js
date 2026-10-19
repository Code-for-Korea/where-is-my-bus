import { BaseMapProvider } from "map_providers/base_map_provider"

export class KakaoMapsProvider extends BaseMapProvider {
  render(_center, _stops, _buses) {
    this.canvas.innerHTML = `<div class="flex h-full items-center justify-center text-sm text-gray-500 p-6 text-center">Kakao Maps는 아직 지원되지 않습니다.</div>`
    console.warn("Kakao Maps provider is a P0 stub")
  }

  static isAvailable() {
    return false
  }
}
