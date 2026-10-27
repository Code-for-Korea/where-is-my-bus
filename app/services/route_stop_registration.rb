# 노선에 정류장 추가/제거 + 그 정류장 geofence의 노선 group 연결/해제.
# 정차 순서 변경(update)은 지원하지 않는다 — docs/future-improvements.md 11번 참고.
class RouteStopRegistration < TraccarRegistration
  manages RouteStop

  class << self
    private

    def sync(route_stop)
      TraccarRouteStopLink.link(route_stop)
    end

    def unsync(route_stop)
      TraccarRouteStopLink.unlink(route_stop)
    end
  end
end
