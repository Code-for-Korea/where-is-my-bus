import { BaseMapProvider } from "map_providers/base_map_provider"

export class NaverMapsProvider extends BaseMapProvider {
  render(_center, _stops, _buses) {
    this.canvas.innerHTML = `<div class="flex h-full items-center justify-center text-sm text-gray-500 p-6 text-center">Naver Maps는 아직 지원되지 않습니다.</div>`
    console.warn("Naver Maps provider is a P0 stub")
  }

  static isAvailable() {
    return false
  }
}
