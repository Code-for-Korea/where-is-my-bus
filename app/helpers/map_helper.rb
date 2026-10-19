module MapHelper
  # Traccar 수신 컨트롤러와 같은 우선순위: credentials → ENV.
  # API 키는 브라우저로 전송되는 값이라 도메인/리퍼러 제한은 Google Cloud 콘솔에서 설정해야 한다.
  def google_maps_api_key
    Rails.application.credentials.dig(:google_maps, :api_key) || ENV["GOOGLE_MAPS_API_KEY"]
  end

  # 카카오맵은 "JavaScript 키"를 appkey로 사용하며, 카카오 개발자 콘솔에 Web 플랫폼 도메인 등록이 필요하다.
  def kakao_maps_app_key
    Rails.application.credentials.dig(:kakao_maps, :app_key) || ENV["KAKAO_MAPS_APP_KEY"]
  end

  def center_coordinate(route)
    stops = route.stops.select(&:coordinates?)
    return { lat: 37.5665, lng: 126.9780 } if stops.empty?

    {
      lat: (stops.sum(&:lat) / stops.size).to_f,
      lng: (stops.sum(&:lng) / stops.size).to_f
    }
  end
end
