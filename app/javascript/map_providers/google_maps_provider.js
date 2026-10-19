import { BaseMapProvider } from "map_providers/base_map_provider"

export class GoogleMapsProvider extends BaseMapProvider {
  render(center, stops, buses) {
    if (typeof google === "undefined" || !google.maps) {
      this.canvas.innerHTML = `<div class="flex h-full items-center justify-center text-sm text-gray-500 p-6 text-center">Google Maps가 로드되지 않았습니다.</div>`
      return
    }

    this.map = new google.maps.Map(this.canvas, {
      center: { lat: center.lat, lng: center.lng },
      zoom: 14,
      mapTypeControl: false,
      streetViewControl: false,
      fullscreenControl: false
    })

    stops.forEach((stop) => {
      new google.maps.Marker({
        position: { lat: stop.lat, lng: stop.lng },
        map: this.map,
        title: stop.name,
        icon: {
          path: google.maps.SymbolPath.CIRCLE,
          scale: 6,
          fillColor: "#3b82f6",
          fillOpacity: 1,
          strokeColor: "#ffffff",
          strokeWeight: 2
        }
      })
    })

    buses.forEach((bus) => {
      new google.maps.Marker({
        position: { lat: bus.lat, lng: bus.lng },
        map: this.map,
        title: bus.number,
        icon: {
          path: google.maps.SymbolPath.BACKWARD_CLOSED_ARROW,
          scale: 6,
          fillColor: "#ef4444",
          fillOpacity: 1,
          strokeColor: "#ffffff",
          strokeWeight: 2
        }
      })
    })
  }

  static isAvailable() {
    return typeof google !== "undefined" && !!google.maps
  }
}
