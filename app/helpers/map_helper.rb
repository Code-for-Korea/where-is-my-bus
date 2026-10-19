module MapHelper
  def center_coordinate(route)
    stops = route.stops.select(&:coordinates?)
    return { lat: 37.5665, lng: 126.9780 } if stops.empty?

    {
      lat: (stops.sum(&:lat) / stops.size).to_f,
      lng: (stops.sum(&:lng) / stops.size).to_f
    }
  end
end
