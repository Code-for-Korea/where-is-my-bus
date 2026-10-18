import { Controller } from "@hotwired/stimulus"
import { GoogleMapsProvider } from "map_providers/google_maps_provider"
import { KakaoMapsProvider } from "map_providers/kakao_maps_provider"
import { NaverMapsProvider } from "map_providers/naver_maps_provider"

const PROVIDERS = {
  google: GoogleMapsProvider,
  kakao: KakaoMapsProvider,
  naver: NaverMapsProvider
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
    this.render()
  }

  render() {
    const ProviderClass = PROVIDERS[this.providerValue] || GoogleMapsProvider
    const provider = new ProviderClass(this.canvasTarget, {})
    provider.render(this.centerValue, this.stopsValue, this.busesValue)
  }
}
