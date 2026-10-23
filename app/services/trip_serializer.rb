# driver_app 응답에 담는 운행 JSON. 운행 시작·종료·노선 조회가 같은 모양을 쓴다.
class TripSerializer
  def self.call(trip)
    return nil unless trip

    { id: trip.id, routeId: trip.route_id, routeName: trip.route.name, startedAt: trip.started_at.iso8601 }
  end
end
