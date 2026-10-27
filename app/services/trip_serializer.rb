# driver_app 응답에 담는 운행 JSON. 운행 시작·종료·차량 조회가 같은 모양을 쓴다.
# position은 서버가 보는 버스 위치(이전·현재·다음 정류장 이름)로, 앱이 근무 중 화면에 보여준다.
class TripSerializer
  def self.call(trip)
    return nil unless trip

    { id: trip.id, routeId: trip.route_id, routeName: trip.route.name, startedAt: trip.started_at.iso8601,
      position: TripPosition.call(trip).to_h }
  end
end
