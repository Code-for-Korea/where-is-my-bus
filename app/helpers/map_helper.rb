module MapHelper
  # 지도 제공자·API 키는 관리자 화면(/admin/setting)에서 설정한 settings 테이블이 단일 소스다.
  # API 키는 브라우저로 전송되는 값이라 도메인/리퍼러 제한은 각 콘솔에서 설정해야 한다.
  def google_maps_api_key
    Setting.fetch(:google_maps_api_key)
  end

  def kakao_maps_app_key
    Setting.fetch(:kakao_maps_app_key)
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
