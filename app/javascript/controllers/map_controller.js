import { Controller } from "@hotwired/stimulus"
import { GoogleMapsProvider } from "map_providers/google_maps_provider"
import { KakaoMapsProvider } from "map_providers/kakao_maps_provider"
import { NaverMapsProvider } from "map_providers/naver_maps_provider"

// readyEvent가 정의된 provider는 SDK 비동기 로드 완료까지 대기한다.
// naver는 P0 stub이라 readyEvent 없이 바로 render(안내 메시지 표시)한다.
const PROVIDERS = {
  google: { provider: GoogleMapsProvider, readyEvent: "google-maps:ready" },
  kakao: { provider: KakaoMapsProvider, readyEvent: "kakao-maps:ready" },
  naver: { provider: NaverMapsProvider, readyEvent: null }
}

export default class extends Controller {
  static targets = ["canvas"]
  static values = {
    provider: String,
    stops: Array,
    buses: Array,
    center: Object
  }

  connect() {
    const target = PROVIDERS[this.providerValue] || PROVIDERS.google

    if (target.readyEvent && !target.provider.isAvailable()) {
      this.waitFor(target.readyEvent)
    } else {
      this.render()
    }
  }

  disconnect() {
    if (this.onReady) {
      window.removeEventListener(this.readyEventName, this.onReady)
      this.onReady = null
    }
  }

  waitFor(readyEvent) {
    this.readyEventName = readyEvent
    this.onReady = () => {
      window.removeEventListener(readyEvent, this.onReady)
      this.onReady = null
      this.render()
    }
    window.addEventListener(readyEvent, this.onReady)
  }

  render() {
    const target = PROVIDERS[this.providerValue] || PROVIDERS.google
    const provider = new target.provider(this.canvasTarget, {})
    provider.render(this.centerValue, this.stopsValue, this.busesValue)
  }
}
